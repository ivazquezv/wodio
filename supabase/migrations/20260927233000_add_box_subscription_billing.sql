alter table public.boxes
  add column if not exists subscription_plan text,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists stripe_checkout_session_id text,
  add column if not exists subscription_status text;

alter table public.boxes drop constraint if exists boxes_subscription_plan_check;
alter table public.boxes add constraint boxes_subscription_plan_check
  check (subscription_plan is null or subscription_plan = any (array['demo','starter','pro','elite']));

alter table public.boxes drop constraint if exists boxes_subscription_status_check;
alter table public.boxes add constraint boxes_subscription_status_check
  check (subscription_status is null or subscription_status = any (array['trialing','pending_payment','active','past_due','canceled','incomplete','unpaid']));

alter table public.boxes drop constraint if exists boxes_status_check;
alter table public.boxes add constraint boxes_status_check
  check (status = any (array['pending','pending_payment','trial','active','suspended','cancelled']));

create unique index if not exists boxes_stripe_customer_id_uidx on public.boxes(stripe_customer_id) where stripe_customer_id is not null;
create unique index if not exists boxes_stripe_subscription_id_uidx on public.boxes(stripe_subscription_id) where stripe_subscription_id is not null;
create unique index if not exists boxes_stripe_checkout_session_id_uidx on public.boxes(stripe_checkout_session_id) where stripe_checkout_session_id is not null;

create or replace function private.current_box_id()
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select p.box_id
  from public.profiles p
  join public.boxes b on b.id = p.box_id
  where p.id = (select auth.uid())
    and (
      b.status = 'active'
      or (b.status = 'trial' and (b.trial_ends_at is null or b.trial_ends_at > now()))
    )
  limit 1
$function$;

revoke all on function private.current_box_id() from public, anon;
grant execute on function private.current_box_id() to authenticated;
