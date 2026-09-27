create table if not exists public.class_booking_cancellations (
  id uuid primary key default gen_random_uuid(),
  class_booking_id uuid not null references public.class_bookings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  cancelled_at timestamptz not null default now()
);

alter table public.class_booking_cancellations enable row level security;

drop policy if exists "Users can view their cancellation history" on public.class_booking_cancellations;
create policy "Users can view their cancellation history"
on public.class_booking_cancellations for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function private.enforce_class_booking_rules()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  class_start timestamptz;
  week_start timestamptz;
  cancellation_count integer;
begin
  if (select auth.uid()) <> new.user_id then
    return new;
  end if;

  select starts_at into class_start from public.classes where id = new.class_id;

  if class_start is null then
    raise exception 'La clase no existe.';
  end if;

  if new.status = 'booked' and (tg_op = 'INSERT' or old.status <> 'booked') then
    if class_start > now() + interval '2 days' then
      raise exception 'Solo puedes reservar clases con un máximo de 2 días de antelación.';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.status = 'booked' and new.status = 'cancelled' then
    if class_start <= now() + interval '1 hour' then
      raise exception 'No puedes cancelar una clase durante la hora anterior a su inicio.';
    end if;

    week_start := date_trunc('week', now());

    select count(*) into cancellation_count
    from public.class_booking_cancellations
    where user_id = new.user_id
      and cancelled_at >= week_start
      and cancelled_at < week_start + interval '7 days';

    if cancellation_count >= 2 then
      raise exception 'Has alcanzado el límite de 2 cancelaciones esta semana.';
    end if;

    insert into public.class_booking_cancellations(class_booking_id,user_id,class_id)
    values (new.id,new.user_id,new.class_id);
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_class_booking_rules on public.class_bookings;
create trigger enforce_class_booking_rules
before insert or update of status, class_id, user_id on public.class_bookings
for each row execute function private.enforce_class_booking_rules();

grant select on public.class_booking_cancellations to authenticated;
