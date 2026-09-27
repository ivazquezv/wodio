create table if not exists public.box_payment_methods (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  method_key text not null,
  name text not null,
  icon text not null default 'ph-credit-card',
  enabled boolean not null default true,
  sort_order integer not null default 0,
  checkout_url text,
  instructions text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(box_id, method_key),
  check (method_key ~ '^[a-z0-9_]+$')
);

create index if not exists idx_box_payment_methods_box on public.box_payment_methods(box_id, enabled, sort_order);

alter table public.box_payment_methods enable row level security;

drop policy if exists "Members can view enabled payment methods" on public.box_payment_methods;
create policy "Members can view enabled payment methods"
on public.box_payment_methods for select to authenticated
using (
  enabled = true and exists (
    select 1 from public.user_box_memberships m
    where m.user_id=(select auth.uid()) and m.box_id=box_payment_methods.box_id
  )
);

drop policy if exists "Box admins manage payment methods" on public.box_payment_methods;
create policy "Box admins manage payment methods"
on public.box_payment_methods for all to authenticated
using (private.is_box_admin(box_id))
with check (private.is_box_admin(box_id));

create or replace function private.touch_box_payment_methods()
returns trigger language plpgsql set search_path=''
as $$ begin new.updated_at=now(); return new; end; $$;
drop trigger if exists trg_touch_box_payment_methods on public.box_payment_methods;
create trigger trg_touch_box_payment_methods before update on public.box_payment_methods
for each row execute function private.touch_box_payment_methods();

insert into public.box_payment_methods(box_id,method_key,name,icon,enabled,sort_order,checkout_url,instructions)
select b.id,v.method_key,v.name,v.icon,true,v.sort_order,null,v.instructions
from public.boxes b
cross join (values
 ('stripe','Stripe','ph-credit-card',10,'Pago seguro con tarjeta mediante Stripe.'),
 ('paypal','PayPal','ph-paypal-logo',20,'Paga con tu cuenta de PayPal.'),
 ('bizum','Bizum','ph-device-mobile',30,'Indica el número de Bizum del box o configura un enlace de pago.'),
 ('transfer','Transferencia bancaria','ph-bank',40,'Realiza la transferencia usando las instrucciones del box.'),
 ('direct_debit','Domiciliación','ph-arrows-clockwise',50,'El box gestionará el cobro mediante domiciliación.'),
 ('cash','Efectivo','ph-money',60,'Pago presencial en el box.')
) v(method_key,name,icon,sort_order,instructions)
on conflict (box_id,method_key) do nothing;

revoke all on table public.box_payment_methods from anon;
grant select, insert, update, delete on table public.box_payment_methods to authenticated;
