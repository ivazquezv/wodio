alter table public.boxes add column if not exists stripe_account_id text;
alter table public.boxes add column if not exists stripe_connect_status text not null default 'not_connected';
alter table public.boxes add column if not exists stripe_connect_charges_enabled boolean not null default false;
alter table public.boxes add column if not exists stripe_connect_payouts_enabled boolean not null default false;
alter table public.boxes add column if not exists stripe_connect_details_submitted boolean not null default false;
alter table public.boxes add column if not exists stripe_connect_updated_at timestamptz;
create index if not exists boxes_stripe_account_id_idx on public.boxes(stripe_account_id);