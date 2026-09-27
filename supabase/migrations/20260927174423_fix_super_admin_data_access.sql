-- Ensure the super-admin dashboard can read platform-wide box data through PostgREST.
-- Authorization is enforced inside the SECURITY DEFINER function.
create or replace function public.get_super_admin_boxes()
returns table (
  id uuid,
  name text,
  slug text,
  contact_email text,
  status text,
  subscription_plan text,
  subscription_status text,
  trial_ends_at timestamptz,
  created_at timestamptz,
  owner_id uuid,
  user_count bigint,
  paid_payment_count bigint,
  paid_revenue_cents bigint,
  current_month_revenue_cents bigint,
  pending_revenue_cents bigint,
  last_payment_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.is_super_admin() then
    raise exception 'super_admin_required';
  end if;

  return query
  select
    b.id,
    b.name,
    b.slug,
    b.contact_email,
    b.status,
    b.subscription_plan,
    b.subscription_status,
    b.trial_ends_at,
    b.created_at,
    b.owner_id,
    coalesce((select count(distinct ubm.user_id) from public.user_box_memberships ubm where ubm.box_id = b.id), 0)::bigint,
    coalesce((select count(*) from public.payments p where p.box_id = b.id and p.status = 'paid'), 0)::bigint,
    coalesce((select sum(p.amount_cents) from public.payments p where p.box_id = b.id and p.status = 'paid'), 0)::bigint,
    coalesce((select sum(p.amount_cents) from public.payments p where p.box_id = b.id and p.status = 'paid' and p.paid_at >= date_trunc('month', now()) and p.paid_at < date_trunc('month', now()) + interval '1 month'), 0)::bigint,
    coalesce((select sum(p.amount_cents) from public.payments p where p.box_id = b.id and p.status in ('pending', 'due', 'unpaid')), 0)::bigint,
    (select max(p.paid_at) from public.payments p where p.box_id = b.id and p.status = 'paid')
  from public.boxes b
  order by
    case
      when b.status = 'active' then 0
      when b.status = 'trial' then 1
      when b.status = 'pending_payment' then 2
      when b.status = 'suspended' then 3
      else 4
    end,
    b.name;
end;
$function$;

grant execute on function public.get_super_admin_boxes() to authenticated;
