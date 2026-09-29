create table if not exists public.platform_feature_flag_usage (
  id uuid primary key default gen_random_uuid(),
  flag_key text not null references public.platform_feature_flags(key) on delete cascade,
  event_name text not null default 'use',
  user_id uuid references auth.users(id) on delete set null,
  box_id uuid references public.boxes(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_feature_flag_usage_flag_created
  on public.platform_feature_flag_usage(flag_key, created_at desc);
create index if not exists idx_feature_flag_usage_user_created
  on public.platform_feature_flag_usage(user_id, created_at desc);

alter table public.platform_feature_flags
  add column if not exists risk_level text not null default 'medium',
  add column if not exists risk_description text not null default '',
  add column if not exists usage_description text not null default '';

update public.platform_feature_flags
set
  description = case key
    when 'athlete_dashboard_v2' then 'Nueva versión del panel principal del atleta, con una experiencia más completa y preparada para futuras funcionalidades.'
    when 'booking_system' then 'Activa el sistema de reservas de clases y actividades del box.'
    when 'ai_workouts' then 'Activa funcionalidades de generación y asistencia de entrenamientos mediante IA.'
    when 'advanced_rankings' then 'Activa rankings avanzados de atletas, con clasificación y métricas adicionales.'
    else description end,
  risk_level = case key
    when 'athlete_dashboard_v2' then 'bajo'
    when 'booking_system' then 'medio'
    when 'ai_workouts' then 'alto'
    when 'advanced_rankings' then 'medio'
    else risk_level end,
  risk_description = case key
    when 'athlete_dashboard_v2' then 'Puede afectar la experiencia principal del atleta y generar regresiones de interfaz si la nueva versión no está estable.'
    when 'booking_system' then 'Puede afectar reservas, plazas y disponibilidad si hay errores de concurrencia o reglas de negocio incorrectas.'
    when 'ai_workouts' then 'Puede producir recomendaciones incorrectas y añade dependencia de servicios de IA, costes y controles de seguridad.'
    when 'advanced_rankings' then 'Puede afectar cálculos de clasificación y percepción de resultados si los datos o fórmulas son incorrectos.'
    else risk_description end,
  usage_description = case key
    when 'athlete_dashboard_v2' then 'Medir aperturas y acciones dentro del dashboard v2 por usuario y box.'
    when 'booking_system' then 'Medir consultas de disponibilidad, reservas, cancelaciones y usuarios activos en reservas.'
    when 'ai_workouts' then 'Medir solicitudes de generación de entrenamientos y usuarios que las utilizan.'
    when 'advanced_rankings' then 'Medir consultas de rankings y usuarios que interactúan con ellos.'
    else usage_description end;

alter table public.platform_feature_flag_usage enable row level security;
revoke all on public.platform_feature_flag_usage from anon, authenticated;
grant insert on public.platform_feature_flag_usage to authenticated;

drop policy if exists "feature flag usage insert" on public.platform_feature_flag_usage;

create or replace function public.track_feature_flag_usage(
  p_flag_key text,
  p_event_name text default 'use',
  p_box_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare uid uuid;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'authenticated_required';
  end if;
  if not exists (select 1 from public.platform_feature_flags f where f.key = p_flag_key) then
    raise exception 'unknown_feature_flag';
  end if;
  insert into public.platform_feature_flag_usage(flag_key,event_name,user_id,box_id)
  values(p_flag_key,coalesce(nullif(trim(p_event_name),''),'use'),uid,p_box_id);
end;
$$;

revoke all on function public.track_feature_flag_usage(text,text,uuid) from public, anon;
grant execute on function public.track_feature_flag_usage(text,text,uuid) to authenticated;

create or replace function public.get_super_admin_operations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare current_metrics jsonb; history jsonb; health jsonb; flags jsonb;
begin
 if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
 current_metrics := private.super_admin_current_metrics();
 history := (select coalesce(jsonb_agg(to_jsonb(x) order by x.metric_date desc),'[]'::jsonb)
             from (select * from public.platform_metrics_daily order by metric_date desc limit 12) x);
 health := private.get_super_admin_health();
 flags := (
   select coalesce(jsonb_agg(to_jsonb(f) order by f.name),'[]'::jsonb)
   from (
     select
       pf.*,
       coalesce(u.events_30d,0)::bigint as usage_events_30d,
       coalesce(u.unique_users_30d,0)::bigint as usage_unique_users_30d,
       coalesce(u.unique_boxes_30d,0)::bigint as usage_unique_boxes_30d,
       u.last_used_at
     from public.platform_feature_flags pf
     left join (
       select flag_key,
              count(*) filter (where created_at >= now()-interval '30 days') as events_30d,
              count(distinct user_id) filter (where created_at >= now()-interval '30 days') as unique_users_30d,
              count(distinct box_id) filter (where created_at >= now()-interval '30 days') as unique_boxes_30d,
              max(created_at) as last_used_at
       from public.platform_feature_flag_usage
       group by flag_key
     ) u on u.flag_key=pf.key
   ) f
 );
 return jsonb_build_object(
  'mrr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0),
  'arr_cents',coalesce((current_metrics->>'mrr_cents')::bigint,0)*12,
  'active_boxes',current_metrics->'active_boxes',
  'trial_expiring',(select count(*) from public.boxes where status='trial' and trial_ends_at between now() and now()+interval '7 days'),
  'suspended',current_metrics->'suspended_boxes',
  'pending_payments',(select count(*) from public.payments where status in ('pending','due','unpaid')),
  'feature_flags',flags,
  'history',history,
  'health',health
 );
end;
$$;

revoke all on function public.get_super_admin_operations() from public, anon;
grant execute on function public.get_super_admin_operations() to authenticated;