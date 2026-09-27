create table if not exists public.finance_audit_log (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  record_type text not null check (record_type in ('payment','expense')),
  record_id uuid not null,
  action text not null default 'update' check (action in ('update')),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now(),
  reason text not null,
  old_data jsonb not null,
  new_data jsonb not null
);
create index if not exists finance_audit_log_box_changed_at_idx on public.finance_audit_log(box_id, changed_at desc);
create index if not exists finance_audit_log_record_idx on public.finance_audit_log(record_type, record_id, changed_at desc);
alter table public.finance_audit_log enable row level security;
drop policy if exists "Box admins can view finance audit log" on public.finance_audit_log;
create policy "Box admins can view finance audit log" on public.finance_audit_log for select to authenticated using (private.is_box_admin(box_id));

create or replace function private.audit_finance_change() returns trigger language plpgsql security definer set search_path = public, private as $$
declare audit_reason text;
begin
  audit_reason := nullif(trim(current_setting('wodio.audit_reason', true)), '');
  if audit_reason is null then raise exception 'Es obligatorio indicar el motivo del cambio.'; end if;
  insert into public.finance_audit_log(box_id,record_type,record_id,action,changed_by,changed_at,reason,old_data,new_data)
  values (NEW.box_id,case when TG_TABLE_NAME='payments' then 'payment' else 'expense' end,OLD.id,'update',auth.uid(),now(),audit_reason,to_jsonb(OLD),to_jsonb(NEW));
  return NEW;
end; $$;
drop trigger if exists payments_finance_audit on public.payments;
create trigger payments_finance_audit after update on public.payments for each row execute function private.audit_finance_change();
drop trigger if exists expenses_finance_audit on public.expenses;
create trigger expenses_finance_audit after update on public.expenses for each row execute function private.audit_finance_change();

create or replace function private.update_payment_with_audit(p_id uuid,p_reason text,p_data jsonb) returns public.payments language plpgsql security definer set search_path = public, private as $$
declare v_row public.payments; v_box uuid;
begin
 if auth.uid() is null then raise exception 'Sesión no válida.'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'El motivo del cambio es obligatorio.'; end if;
 select box_id into v_box from public.payments where id=p_id;
 if v_box is null then raise exception 'Ingreso no encontrado.'; end if;
 if not private.is_box_admin(v_box) then raise exception 'No tienes permisos para modificar este ingreso.'; end if;
 perform set_config('wodio.audit_reason',trim(p_reason),true);
 update public.payments set
 user_id=case when p_data ? 'user_id' then (p_data->>'user_id')::uuid else user_id end,
 concept=case when p_data ? 'concept' then p_data->>'concept' else concept end,
 amount_cents=case when p_data ? 'amount_cents' then (p_data->>'amount_cents')::integer else amount_cents end,
 status=case when p_data ? 'status' then p_data->>'status' else status end,
 due_date=case when p_data ? 'due_date' then nullif(p_data->>'due_date','')::date else due_date end,
 paid_at=case when p_data ? 'paid_at' then nullif(p_data->>'paid_at','')::timestamptz else paid_at end,
 category=case when p_data ? 'category' then nullif(p_data->>'category','') else category end,
 payment_method=case when p_data ? 'payment_method' then nullif(p_data->>'payment_method','') else payment_method end,
 provider_reference=case when p_data ? 'provider_reference' then nullif(p_data->>'provider_reference','') else provider_reference end,
 notes=case when p_data ? 'notes' then nullif(p_data->>'notes','') else notes end,
 updated_at=now()
 where id=p_id returning * into v_row;
 return v_row;
end; $$;

create or replace function private.update_expense_with_audit(p_id uuid,p_reason text,p_data jsonb) returns public.expenses language plpgsql security definer set search_path = public, private as $$
declare v_row public.expenses; v_box uuid;
begin
 if auth.uid() is null then raise exception 'Sesión no válida.'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'El motivo del cambio es obligatorio.'; end if;
 select box_id into v_box from public.expenses where id=p_id;
 if v_box is null then raise exception 'Gasto no encontrado.'; end if;
 if not private.is_box_admin(v_box) then raise exception 'No tienes permisos para modificar este gasto.'; end if;
 perform set_config('wodio.audit_reason',trim(p_reason),true);
 update public.expenses set
 concept=case when p_data ? 'concept' then p_data->>'concept' else concept end,
 amount_cents=case when p_data ? 'amount_cents' then (p_data->>'amount_cents')::integer else amount_cents end,
 expense_date=case when p_data ? 'expense_date' then (p_data->>'expense_date')::date else expense_date end,
 category=case when p_data ? 'category' then nullif(p_data->>'category','') else category end,
 supplier=case when p_data ? 'supplier' then nullif(p_data->>'supplier','') else supplier end,
 notes=case when p_data ? 'notes' then nullif(p_data->>'notes','') else notes end,
 updated_at=now()
 where id=p_id returning * into v_row;
 return v_row;
end; $$;

revoke all on function private.update_payment_with_audit(uuid,text,jsonb) from public,anon;
revoke all on function private.update_expense_with_audit(uuid,text,jsonb) from public,anon;
grant execute on function private.update_payment_with_audit(uuid,text,jsonb) to authenticated;
grant execute on function private.update_expense_with_audit(uuid,text,jsonb) to authenticated;
revoke all on function private.audit_finance_change() from public,anon,authenticated;

create or replace function public.update_payment_with_audit(p_id uuid,p_reason text,p_data jsonb) returns public.payments language sql security invoker set search_path = public, private as $$ select private.update_payment_with_audit(p_id,p_reason,p_data); $$;
create or replace function public.update_expense_with_audit(p_id uuid,p_reason text,p_data jsonb) returns public.expenses language sql security invoker set search_path = public, private as $$ select private.update_expense_with_audit(p_id,p_reason,p_data); $$;
revoke execute on function public.update_payment_with_audit(uuid,text,jsonb) from public,anon;
revoke execute on function public.update_expense_with_audit(uuid,text,jsonb) from public,anon;
grant execute on function public.update_payment_with_audit(uuid,text,jsonb) to authenticated; grant execute on function public.update_expense_with_audit(uuid,text,jsonb) to authenticated;
grant select on table public.finance_audit_log to authenticated;
