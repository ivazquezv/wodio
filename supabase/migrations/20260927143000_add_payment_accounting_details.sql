-- Add accounting dimensions to income records.
alter table public.payments
  add column if not exists category text,
  add column if not exists payment_method text,
  add column if not exists notes text;

comment on column public.payments.category is 'Accounting category for the income.';
comment on column public.payments.payment_method is 'Payment method used for the income.';
comment on column public.payments.notes is 'Optional accounting notes for the income.';
