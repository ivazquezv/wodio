create table if not exists public.platform_feature_flag_incidents (
  id uuid primary key default gen_random_uuid(),
  flag_key text not null references public.platform_feature_flags(key) on delete cascade,
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  status text not null default 'open' check (status in ('open','resolved')),
  title text not null,
  description text not null default '',
  source_event text not null,
  occurrence_count bigint not null default 1,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  resolution_action text,
  resolution_note text,
  created_at timestamptz not null default now()
);

create index if not exists platform_feature_flag_incidents_status_idx
  on public.platform_feature_flag_incidents(status, last_seen_at desc);
create index if not exists platform_feature_flag_incidents_flag_idx
  on public.platform_feature_flag_incidents(flag_key, status);

alter table public.platform_feature_flag_incidents enable row level security;
revoke all on public.platform_feature_flag_incidents from anon, authenticated;
grant select on public.platform_feature_flag_incidents to authenticated;

drop policy if exists "super admins can read feature flag incidents" on public.platform_feature_flag_incidents;
create policy "super admins can read feature flag incidents"
on public.platform_feature_flag_incidents
for select to authenticated
using ((select private.is_super_admin()));

create or replace function private.refresh_super_admin_feature_flag_incidents()
returns void language plpgsql security definer set search_path=''
as $function$
declare r record;
begin
  if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
  for r in
    select u.flag_key, lower(u.event_name) as source_event, count(*)::bigint occurrence_count,
           min(u.created_at) first_seen_at, max(u.created_at) last_seen_at,
           max(pf.risk_level) risk_level, max(pf.name) flag_name
    from public.platform_feature_flag_usage u
    join public.platform_feature_flags pf on pf.key=u.flag_key
    where u.created_at >= now()-interval '30 days'
      and (lower(u.event_name) in ('error','failed','failure','incident')
           or lower(u.event_name) like 'error:%'
           or lower(u.event_name) like 'failed:%'
           or lower(u.event_name) like 'failure:%')
    group by u.flag_key, lower(u.event_name)
  loop
    update public.platform_feature_flag_incidents i
       set occurrence_count=r.occurrence_count,
           last_seen_at=r.last_seen_at,
           description='Se han registrado '||r.occurrence_count||' evento(s) de tipo '||r.source_event||' en los últimos 30 días.'
     where i.flag_key=r.flag_key and i.source_event=r.source_event and i.status='open';
    if not found then
      insert into public.platform_feature_flag_incidents
        (flag_key,severity,status,title,description,source_event,occurrence_count,first_seen_at,last_seen_at)
      values
        (r.flag_key,
         case lower(coalesce(r.risk_level,'medium'))
           when 'high' then 'high' when 'alto' then 'high'
           when 'critical' then 'critical' else 'medium' end,
         'open',
         'Incidencia detectada en '||r.flag_name,
         'Se han registrado '||r.occurrence_count||' evento(s) de tipo '||r.source_event||' en los últimos 30 días.',
         r.source_event,r.occurrence_count,r.first_seen_at,r.last_seen_at);
    end if;
  end loop;
end;
$function$;

revoke all on function private.refresh_super_admin_feature_flag_incidents() from public, anon, authenticated;

create or replace function public.super_admin_resolve_feature_flag_incident(
  p_incident_id uuid, p_action text, p_note text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare inc public.platform_feature_flag_incidents%rowtype;
        flag public.platform_feature_flags%rowtype;
        new_enabled boolean;
begin
  if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
  if p_action not in ('reviewed','keep_active','disable') then raise exception 'invalid_resolution_action'; end if;
  select * into inc from public.platform_feature_flag_incidents where id=p_incident_id for update;
  if not found then raise exception 'incident_not_found'; end if;
  if inc.status='resolved' then return jsonb_build_object('status','already_resolved','incident_id',inc.id); end if;
  select * into flag from public.platform_feature_flags where key=inc.flag_key for update;

  if p_action='disable' then
    new_enabled=false;
    update public.platform_feature_flags set enabled=false,updated_at=now() where key=inc.flag_key;
  else
    new_enabled=flag.enabled;
  end if;

  update public.platform_feature_flag_incidents
     set status='resolved',resolved_at=now(),resolved_by=auth.uid(),
         resolution_action=p_action,resolution_note=nullif(trim(coalesce(p_note,'')),'')
   where id=inc.id;

  insert into public.super_admin_audit_log
    (actor_id,action,entity_type,entity_id,entity_name,details)
  values
    (auth.uid(),'feature_flag_incident_resolved','feature_flag_incident',inc.id,flag.name,
     jsonb_build_object(
       'flag_key',inc.flag_key,'resolution_action',p_action,
       'resolution_note',nullif(trim(coalesce(p_note,'')),''),
       'flag_enabled_before',flag.enabled,'flag_enabled_after',new_enabled,
       'source_event',inc.source_event,'occurrence_count',inc.occurrence_count));

  return jsonb_build_object('status','resolved','incident_id',inc.id,'flag_key',inc.flag_key,'flag_enabled',new_enabled);
end;
$function$;

revoke all on function public.super_admin_resolve_feature_flag_incident(uuid,text,text) from public, anon, authenticated;
grant execute on function public.super_admin_resolve_feature_flag_incident(uuid,text,text) to authenticated;

create or replace function public.get_super_admin_operations()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare current_metrics jsonb; history jsonb; health jsonb; flags jsonb; incidents jsonb; resolved_incidents jsonb;
begin
  if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
  perform private.refresh_super_admin_feature_flag_incidents();
  current_metrics:=private.super_admin_current_metrics();
  history:=(select coalesce(jsonb_agg(to_jsonb(x) order by x.metric_date desc),'[]'::jsonb)
            from (select * from public.platform_metrics_daily order by metric_date desc limit 12) x);
  health:=private.get_super_admin_health();
  flags:=(select coalesce(jsonb_agg(to_jsonb(f) order by f.name),'[]'::jsonb)
          from (
            select pf.*,coalesce(u.events_30d,0)::bigint usage_events_30d,
                   coalesce(u.unique_users_30d,0)::bigint usage_unique_users_30d,
                   coalesce(u.unique_boxes_30d,0)::bigint usage_unique_boxes_30d,u.last_used_at
            from public.platform_feature_flags pf
            left join (
              select flag_key,
                     count(*) filter(where created_at>=now()-interval '30 days') events_30d,
                     count(distinct user_id) filter(where created_at>=now()-interval '30 days') unique_users_30d,
                     count(distinct box_id) filter(where created_at>=now()-interval '30 days') unique_boxes_30d,
                     max(created_at) last_used_at
              from public.platform_feature_flag_usage group by flag_key
            ) u on u.flag_key=pf.key
          ) f);
  incidents:=(select coalesce(jsonb_agg(to_jsonb(i) order by
               case i.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
               i.last_seen_at desc),'[]'::jsonb)
              from (
                select i.*,pf.name flag_name,pf.enabled flag_enabled
                from public.platform_feature_flag_incidents i
                join public.platform_feature_flags pf on pf.key=i.flag_key
                where i.status='open'
              ) i);
  resolved_incidents:=(select coalesce(jsonb_agg(to_jsonb(i) order by i.resolved_at desc),'[]'::jsonb)
              from (
                select i.*,pf.name flag_name,pf.enabled flag_enabled
                from public.platform_feature_flag_incidents i
                join public.platform_feature_flags pf on pf.key=i.flag_key
                where i.status='resolved'
                order by i.resolved_at desc
                limit 10
              ) i);
  return jsonb_build_object(
    'mrr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0),
    'arr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0)*12,
    'active_boxes',current_metrics->'active_boxes',
    'trial_expiring',(select count(*) from public.boxes where status='trial' and trial_ends_at between now() and now()+interval '7 days'),
    'suspended',current_metrics->'suspended_boxes',
    'pending_payments',(select count(*) from public.payments where status in ('pending','due','unpaid')),
    'feature_flags',flags,'incidents',incidents,'resolved_incidents',resolved_incidents,
    'health',health,'history',history);
end;
$function$;

revoke all on function public.get_super_admin_operations() from public, anon, authenticated;
grant execute on function public.get_super_admin_operations() to authenticated;
