-- Platform health, recurring revenue metrics and daily historical snapshots.
create table if not exists public.platform_metrics_daily (
  metric_date date primary key,
  active_boxes integer not null default 0,
  trial_boxes integer not null default 0,
  suspended_boxes integer not null default 0,
  total_users integer not null default 0,
  mrr_cents bigint not null default 0,
  arr_cents bigint not null default 0,
  paid_revenue_cents bigint not null default 0,
  pending_revenue_cents bigint not null default 0,
  created_at timestamptz not null default now()
);

alter table public.platform_metrics_daily enable row level security;
revoke all on table public.platform_metrics_daily from anon, authenticated;
grant select on table public.platform_metrics_daily to authenticated;
drop policy if exists "super admins can read platform metrics" on public.platform_metrics_daily;
create policy "super admins can read platform metrics"
on public.platform_metrics_daily for select to authenticated
using (private.is_super_admin());

create or replace function private.super_admin_current_metrics()
returns jsonb language sql stable security definer set search_path=''
as $function$
select jsonb_build_object(
  'active_boxes', (select count(*) from public.boxes where status='active' and subscription_status='active'),
  'trial_boxes', (select count(*) from public.boxes where status='trial'),
  'suspended_boxes', (select count(*) from public.boxes where status='suspended'),
  'total_users', (select count(*) from public.profiles where role <> 'super_admin'),
  'mrr_cents', coalesce((select sum(case subscription_plan when 'starter' then 2900 when 'pro' then 4900 when 'elite' then 7900 else 0 end) from public.boxes where status='active' and subscription_status='active'),0),
  'paid_revenue_cents', coalesce((select sum(amount_cents) from public.payments where status='paid'),0),
  'pending_revenue_cents', coalesce((select sum(amount_cents) from public.payments where status in ('pending','due','unpaid')),0)
);
$function$;

create or replace function public.record_super_admin_metrics_snapshot()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v jsonb;
begin
  if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
  v := private.super_admin_current_metrics();
  insert into public.platform_metrics_daily(metric_date,active_boxes,trial_boxes,suspended_boxes,total_users,mrr_cents,arr_cents,paid_revenue_cents,pending_revenue_cents)
  values(current_date,coalesce((v->>'active_boxes')::int,0),coalesce((v->>'trial_boxes')::int,0),coalesce((v->>'suspended_boxes')::int,0),coalesce((v->>'total_users')::int,0),coalesce((v->>'mrr_cents')::bigint,0),coalesce((v->>'mrr_cents')::bigint,0)*12,coalesce((v->>'paid_revenue_cents')::bigint,0),coalesce((v->>'pending_revenue_cents')::bigint,0))
  on conflict(metric_date) do update set active_boxes=excluded.active_boxes,trial_boxes=excluded.trial_boxes,suspended_boxes=excluded.suspended_boxes,total_users=excluded.total_users,mrr_cents=excluded.mrr_cents,arr_cents=excluded.arr_cents,paid_revenue_cents=excluded.paid_revenue_cents,pending_revenue_cents=excluded.pending_revenue_cents;
  return jsonb_build_object('current',v,'history',(select coalesce(jsonb_agg(to_jsonb(x) order by x.metric_date desc),'[]'::jsonb) from (select * from public.platform_metrics_daily order by metric_date desc limit 12) x));
end;
$function$;

create or replace function private.get_super_admin_health()
returns jsonb language sql stable security definer set search_path=''
as $function$
with checks as (
 select 'expired_trials' key,'Trials caducados' label,count(*)::int value from public.boxes where status='trial' and trial_ends_at is not null and trial_ends_at < now()
 union all select 'subscription_mismatch','Suscripciones inconsistentes',count(*)::int from public.boxes where status='active' and (subscription_status <> 'active' or subscription_plan not in ('starter','pro','elite'))
 union all select 'missing_stripe','Boxes activos sin suscripción Stripe',count(*)::int from public.boxes where status='active' and (stripe_subscription_id is null or stripe_subscription_id='')
 union all select 'overdue_payments','Pagos vencidos',count(*)::int from public.payments where status in ('pending','due','unpaid') and due_date < current_date
 union all select 'suspended_boxes','Boxes suspendidos',count(*)::int from public.boxes where status='suspended'
 union all select 'no_payments','Boxes sin pagos',count(*)::int from public.boxes b where not exists (select 1 from public.payments p where p.box_id=b.id)
), summary as (select coalesce(sum(value),0)::int problems from checks), last_snapshot as (select max(metric_date) metric_date from public.platform_metrics_daily)
select jsonb_build_object(
 'status',case when (select problems from summary)>=3 then 'critical' when (select problems from summary)>0 then 'degraded' else 'healthy' end,
 'problem_count',(select problems from summary),'last_snapshot',(select metric_date from last_snapshot),
 'checks',(select coalesce(jsonb_agg(to_jsonb(c) order by c.value desc,c.label),'[]'::jsonb) from checks c)
);
$function$;

create or replace function public.get_super_admin_operations()
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare current_metrics jsonb; history jsonb; health jsonb;
begin
 if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
 current_metrics := private.super_admin_current_metrics();
 history := (select coalesce(jsonb_agg(to_jsonb(x) order by x.metric_date desc),'[]'::jsonb) from (select * from public.platform_metrics_daily order by metric_date desc limit 12) x);
 health := private.get_super_admin_health();
 return jsonb_build_object(
  'mrr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0),
  'arr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0)*12,
  'active_boxes',current_metrics->'active_boxes',
  'trial_expiring',(select count(*) from public.boxes where status='trial' and trial_ends_at between now() and now()+interval '7 days'),
  'suspended',current_metrics->'suspended_boxes',
  'pending_payments',(select count(*) from public.payments where status in ('pending','due','unpaid')),
  'feature_flags',(select coalesce(jsonb_agg(to_jsonb(f) order by f.name),'[]'::jsonb) from public.platform_feature_flags f),
  'history',history,'health',health
 );
end;
$function$;

revoke execute on function private.super_admin_current_metrics() from public,anon,authenticated;
revoke execute on function private.get_super_admin_health() from public,anon,authenticated;
revoke execute on function public.record_super_admin_metrics_snapshot() from public;
revoke execute on function public.get_super_admin_operations() from public;
grant execute on function public.record_super_admin_metrics_snapshot() to authenticated;
grant execute on function public.get_super_admin_operations() to authenticated;
