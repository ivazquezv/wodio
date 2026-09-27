create or replace function private.get_super_admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if not private.is_super_admin() then
    raise exception 'super_admin_required';
  end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'boxes', (select count(*) from public.boxes),
      'active_boxes', (select count(*) from public.boxes where status = 'active'),
      'trial_boxes', (select count(*) from public.boxes where status = 'trial'),
      'pending_boxes', (select count(*) from public.boxes where status = 'pending_payment'),
      'suspended_boxes', (select count(*) from public.boxes where status = 'suspended'),
      'users', (select count(*) from public.profiles where role <> 'super_admin'),
      'revenue_cents', coalesce((select sum(amount_cents) from public.payments where status = 'paid'), 0),
      'month_revenue_cents', coalesce((select sum(amount_cents) from public.payments where status = 'paid' and paid_at >= date_trunc('month', now()) and paid_at < date_trunc('month', now()) + interval '1 month'), 0),
      'pending_cents', coalesce((select sum(amount_cents) from public.payments where status in ('pending','due','unpaid')), 0)
    ),
    'boxes', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.sort_order, x.name)
      from (
        select b.id,b.name,b.slug,b.contact_email,b.phone,b.city,b.status,b.subscription_plan,b.subscription_status,b.trial_ends_at,b.created_at,b.owner_id,
          case when b.status='active' then 0 when b.status='trial' then 1 when b.status='pending_payment' then 2 when b.status='suspended' then 3 else 4 end as sort_order,
          (select count(distinct ubm.user_id)::bigint from public.user_box_memberships ubm where ubm.box_id=b.id) as user_count,
          (select count(*)::bigint from public.payments p where p.box_id=b.id and p.status='paid') as paid_payment_count,
          coalesce((select sum(p.amount_cents)::bigint from public.payments p where p.box_id=b.id and p.status='paid'),0) as paid_revenue_cents,
          coalesce((select sum(p.amount_cents)::bigint from public.payments p where p.box_id=b.id and p.status='paid' and p.paid_at >= date_trunc('month',now()) and p.paid_at < date_trunc('month',now())+interval '1 month'),0) as current_month_revenue_cents,
          coalesce((select sum(p.amount_cents)::bigint from public.payments p where p.box_id=b.id and p.status in ('pending','due','unpaid')),0) as pending_revenue_cents,
          (select max(p.paid_at) from public.payments p where p.box_id=b.id and p.status='paid') as last_payment_at
        from public.boxes b
      ) x
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.box_name nulls last,x.last_name nulls last,x.first_name nulls last)
      from (
        select p.id,p.first_name,p.last_name,p.role,p.box_id,b.name as box_name,p.created_at,au.email,
          (select count(*)::bigint from public.payments pay where pay.user_id=p.id) as payment_count,
          coalesce((select sum(pay.amount_cents)::bigint from public.payments pay where pay.user_id=p.id and pay.status='paid'),0) as paid_amount_cents
        from public.profiles p
        left join public.boxes b on b.id=p.box_id
        left join auth.users au on au.id=p.id
        where p.role <> 'super_admin'
      ) x
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.payment_date desc nulls last,x.created_at desc)
      from (
        select p.id,p.box_id,b.name as box_name,p.user_id,
          coalesce(nullif(trim(concat_ws(' ',pr.first_name,pr.last_name)),''),au.email,'Usuario') as user_name,
          p.concept,p.amount_cents,p.currency,p.status,p.category,p.payment_method,p.due_date,p.paid_at,p.provider,p.created_at,
          coalesce(p.paid_at,p.created_at) as payment_date
        from public.payments p
        left join public.boxes b on b.id=p.box_id
        left join public.profiles pr on pr.id=p.user_id
        left join auth.users au on au.id=p.user_id
      ) x
    ), '[]'::jsonb)
  ) into result;
  return result;
end;
$function$;

create or replace function public.get_super_admin_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_super_admin_dashboard();
$function$;

revoke all on function public.get_super_admin_dashboard() from public;
grant execute on function public.get_super_admin_dashboard() to authenticated;