create table if not exists public.super_admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  entity_name text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists super_admin_audit_log_created_at_idx
  on public.super_admin_audit_log(created_at desc);

alter table public.super_admin_audit_log enable row level security;

revoke all on table public.super_admin_audit_log from anon, authenticated;
grant select on table public.super_admin_audit_log to authenticated;

drop policy if exists "super admins can read audit log" on public.super_admin_audit_log;
create policy "super admins can read audit log"
on public.super_admin_audit_log
for select
to authenticated
using (private.is_super_admin());

create or replace function private.get_super_admin_activity()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
  from (
    select
      a.id,
      a.action,
      a.entity_type,
      a.entity_id,
      a.entity_name,
      a.details,
      a.created_at,
      coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), u.email, 'Super admin') as actor_name
    from public.super_admin_audit_log a
    left join public.profiles p on p.id = a.actor_id
    left join auth.users u on u.id = a.actor_id
    where private.is_super_admin()
    order by a.created_at desc
    limit 30
  ) x;
$function$;

create or replace function public.get_super_admin_activity()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select private.get_super_admin_activity();
$function$;

revoke execute on function private.get_super_admin_activity() from public;
revoke execute on function private.get_super_admin_activity() from anon;
revoke execute on function private.get_super_admin_activity() from authenticated;
revoke execute on function public.get_super_admin_activity() from anon;
grant execute on function public.get_super_admin_activity() to authenticated;

create or replace function private.super_admin_update_box(p_box_id uuid, p_status text default null, p_plan text default null)
returns public.boxes
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_box public.boxes;
  v_status text;
  v_plan text;
  v_subscription_status text;
begin
  if not private.is_super_admin() then raise exception 'super_admin_required'; end if;
  if p_box_id is null then raise exception 'box_id_required'; end if;
  if p_status is not null and p_status not in ('active','suspended','trial','pending_payment') then raise exception 'invalid_status'; end if;
  if p_plan is not null and p_plan not in ('demo','starter','pro','elite') then raise exception 'invalid_plan'; end if;

  select * into v_box from public.boxes where id = p_box_id for update;
  if not found then raise exception 'box_not_found'; end if;

  v_status := coalesce(p_status, v_box.status);
  v_plan := coalesce(p_plan, v_box.subscription_plan);
  v_subscription_status := case
    when v_status = 'suspended' then 'suspended'
    when v_status = 'pending_payment' then 'pending_payment'
    when v_status = 'trial' then 'trialing'
    when v_status = 'active' then 'active'
    else coalesce(v_box.subscription_status, 'active')
  end;

  update public.boxes
  set status=v_status,
      subscription_plan=v_plan,
      subscription_status=v_subscription_status,
      trial_ends_at=case
        when v_plan='demo' and v_status='trial' and (v_box.trial_ends_at is null or v_box.trial_ends_at < now()) then now()+interval '7 days'
        when v_plan <> 'demo' then null
        else v_box.trial_ends_at
      end,
      updated_at=now()
  where id=p_box_id
  returning * into v_box;

  insert into public.super_admin_audit_log(actor_id,action,entity_type,entity_id,entity_name,details)
  values(auth.uid(),'box_updated','box',v_box.id,v_box.name,jsonb_build_object(
    'status',v_box.status,
    'plan',v_box.subscription_plan,
    'subscription_status',v_box.subscription_status
  ));

  return v_box;
end;
$function$;

revoke execute on function private.super_admin_update_box(uuid,text,text) from public;
revoke execute on function private.super_admin_update_box(uuid,text,text) from anon;
revoke execute on function private.super_admin_update_box(uuid,text,text) from authenticated;
revoke execute on function public.super_admin_update_box(uuid,text,text) from anon;
grant execute on function public.super_admin_update_box(uuid,text,text) to authenticated;
