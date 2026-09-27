create table if not exists public.verifactu_config (
  box_id uuid primary key references public.boxes(id) on delete cascade,
  enabled boolean not null default false,
  mode text not null default 'verifactu' check (mode in ('verifactu','no_verifactu')),
  issuer_name text,
  issuer_nif text,
  issuer_address text,
  software_name text not null default 'WodIO',
  software_nif text,
  software_id text not null default 'WODIO',
  software_version text not null default '1.0.0',
  installation_number text,
  next_invoice_number bigint not null default 1 check (next_invoice_number > 0),
  invoice_series text not null default 'F',
  aeat_environment text not null default 'test' check (aeat_environment in ('test','production')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.verifactu_records (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete restrict,
  record_type text not null check (record_type in ('alta','anulacion')),
  invoice_series text not null,
  invoice_number text not null,
  invoice_date date not null,
  issuer_nif text not null,
  recipient_nif text,
  recipient_name text,
  description text,
  taxable_base_cents bigint not null default 0,
  vat_rate numeric(7,4),
  vat_amount_cents bigint not null default 0,
  total_amount_cents bigint not null,
  currency text not null default 'EUR',
  operation_date date,
  previous_series text,
  previous_number text,
  previous_date date,
  previous_hash text,
  hash_algorithm text not null default 'SHA-256',
  record_hash text not null,
  qr_url text,
  aeat_status text not null default 'pending' check (aeat_status in ('pending','sent','accepted','rejected','error')),
  aeat_request_id text,
  aeat_sent_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists verifactu_records_box_series_number_type_idx
  on public.verifactu_records(box_id, invoice_series, invoice_number, record_type);
create index if not exists verifactu_records_box_generated_idx
  on public.verifactu_records(box_id, generated_at desc);

alter table public.verifactu_config enable row level security;
alter table public.verifactu_records enable row level security;

create policy "Box admins can view VERI*FACTU config" on public.verifactu_config for select to authenticated
using (private.is_box_admin(box_id));
create policy "Box admins can insert VERI*FACTU config" on public.verifactu_config for insert to authenticated
with check (private.is_box_admin(box_id));
create policy "Box admins can update VERI*FACTU config" on public.verifactu_config for update to authenticated
using (private.is_box_admin(box_id))
with check (private.is_box_admin(box_id));

create policy "Box admins can view VERI*FACTU records" on public.verifactu_records for select to authenticated
using (private.is_box_admin(box_id));
create policy "Box admins can insert VERI*FACTU records" on public.verifactu_records for insert to authenticated
with check (private.is_box_admin(box_id));

revoke update, delete on public.verifactu_records from authenticated, anon;

create or replace function private.touch_verifactu_config()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_verifactu_config on public.verifactu_config;
create trigger trg_touch_verifactu_config
before update on public.verifactu_config
for each row execute function private.touch_verifactu_config();
