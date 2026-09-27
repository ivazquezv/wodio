alter table public.verifactu_config add column if not exists default_vat_rate numeric(5,2) not null default 21.00;

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.payments(id) on delete restrict,
  box_id uuid not null references public.boxes(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  series text not null,
  number bigint not null,
  issue_date date not null default current_date,
  operation_date date,
  issuer_name text not null,
  issuer_nif text,
  issuer_address text,
  issuer_city text,
  issuer_postal_code text,
  recipient_name text not null,
  recipient_email text,
  description text not null,
  payment_method text,
  base_cents integer not null,
  vat_rate numeric(5,2) not null default 21.00,
  vat_cents integer not null,
  total_cents integer not null,
  currency text not null default 'EUR',
  created_at timestamptz not null default now(),
  unique(series,number)
);

create index if not exists idx_invoices_box_date on public.invoices(box_id,issue_date desc);
create index if not exists idx_invoices_user_date on public.invoices(user_id,issue_date desc);
alter table public.invoices enable row level security;

drop policy if exists "Users can view own invoices" on public.invoices;
create policy "Users can view own invoices" on public.invoices for select to authenticated using ((select auth.uid())=user_id);
drop policy if exists "Admins can view box invoices" on public.invoices;
create policy "Admins can view box invoices" on public.invoices for select to authenticated using (private.is_box_admin(box_id));

drop policy if exists "Users can create own pending payments" on public.payments;
create policy "Users can create own pending payments" on public.payments for insert to authenticated
with check (user_id=(select auth.uid()) and box_id=(select private.current_box_id()) and status='pending');

create or replace function private.create_invoice_for_payment(p_payment_id uuid)
returns table(invoice_id uuid, invoice_series text, invoice_number bigint)
language plpgsql security definer set search_path=''
as $$
declare p public.payments; prof public.profiles; bx public.boxes; cfg public.verifactu_config; existing public.invoices;
n bigint; rate numeric(5,2); base integer; vat integer; inv_id uuid; recipient_email text; series text;
begin
 select * into p from public.payments where id=p_payment_id;
 if not found then raise exception 'Pago no encontrado'; end if;
 if p.status <> 'paid' then raise exception 'Solo se puede facturar un pago realizado'; end if;
 if (select auth.uid()) <> p.user_id and not private.is_box_admin(p.box_id) then raise exception 'No autorizado'; end if;
 select * into existing from public.invoices where payment_id=p.id;
 if found then return query select existing.id,existing.series,existing.number; return; end if;
 select * into prof from public.profiles where id=p.user_id;
 select email into recipient_email from auth.users where id=p.user_id;
 select * into bx from public.boxes where id=p.box_id;
 select * into cfg from public.verifactu_config where box_id=p.box_id for update;
 if cfg.id is not null then
   n:=coalesce(cfg.next_invoice_number,1); rate:=coalesce(cfg.default_vat_rate,21.00); series:=coalesce(nullif(cfg.invoice_series,''),'F');
   update public.verifactu_config set next_invoice_number=n+1,updated_at=now() where box_id=p.box_id;
 else
   n:=1; rate:=21.00; series:='F';
   insert into public.verifactu_config(box_id,enabled,mode,invoice_series,next_invoice_number,default_vat_rate) values(p.box_id,false,'no_verifactu',series,2,rate) on conflict(box_id) do nothing;
 end if;
 base:=round(p.amount_cents/(1+rate/100.0)); vat:=p.amount_cents-base;
 insert into public.invoices(payment_id,box_id,user_id,series,number,issue_date,operation_date,issuer_name,issuer_nif,issuer_address,issuer_city,issuer_postal_code,recipient_name,recipient_email,description,payment_method,base_cents,vat_rate,vat_cents,total_cents,currency)
 values(p.id,p.box_id,p.user_id,series,n,current_date,p.due_date,coalesce(bx.name,'Box'),bx.tax_id,bx.address,bx.city,bx.postal_code,trim(coalesce(prof.first_name,'')||' '||coalesce(prof.last_name,'')),recipient_email,p.concept,p.payment_method,base,rate,vat,p.amount_cents,coalesce(p.currency,'EUR')) returning id into inv_id;
 return query select inv_id,series,n;
end;
$$;
revoke all on function private.create_invoice_for_payment(uuid) from public;
grant execute on function private.create_invoice_for_payment(uuid) to authenticated;

create or replace function public.create_invoice_for_payment(p_payment_id uuid)
returns table(invoice_id uuid, invoice_series text, invoice_number bigint)
language sql security definer set search_path=''
as $$ select * from private.create_invoice_for_payment(p_payment_id); $$;
revoke all on function public.create_invoice_for_payment(uuid) from public;
grant execute on function public.create_invoice_for_payment(uuid) to authenticated;
grant select on public.invoices to authenticated;