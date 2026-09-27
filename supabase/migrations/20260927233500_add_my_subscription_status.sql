create or replace function public.get_my_subscription_status()
returns table(
  box_id uuid,
  box_name text,
  status text,
  subscription_plan text,
  subscription_status text,
  trial_ends_at timestamptz
)
language sql
stable
security definer
set search_path=''
as $function$
  select b.id, b.name, b.status, b.subscription_plan, b.subscription_status, b.trial_ends_at
  from public.profiles p
  join public.boxes b on b.id = p.box_id
  where p.id = (select auth.uid())
  limit 1
$function$;

revoke all on function public.get_my_subscription_status() from public, anon;
grant execute on function public.get_my_subscription_status() to authenticated;
