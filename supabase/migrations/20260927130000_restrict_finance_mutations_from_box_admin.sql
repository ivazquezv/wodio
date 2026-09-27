-- Finance records are immutable from the box admin role.
-- Admins may still create new income/expense records, but cannot edit or delete existing ones.
drop policy if exists "Admins can update payments" on public.payments;
drop policy if exists "Admins can delete payments" on public.payments;
drop policy if exists expenses_admin_update on public.expenses;
drop policy if exists expenses_admin_delete on public.expenses;
