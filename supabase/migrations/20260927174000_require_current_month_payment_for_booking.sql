alter table public.boxes
  add column if not exists booking_advance_days integer not null default 2,
  add column if not exists cancellation_cutoff_hours integer not null default 1,
  add column if not exists weekly_cancellation_limit integer not null default 2;

alter table public.boxes
  add constraint boxes_booking_advance_days_check check (booking_advance_days between 0 and 30),
  add constraint boxes_cancellation_cutoff_hours_check check (cancellation_cutoff_hours between 0 and 72),
  add constraint boxes_weekly_cancellation_limit_check check (weekly_cancellation_limit between 0 and 20);

create or replace function private.enforce_class_booking_rules()
returns trigger language plpgsql security definer set search_path = public, private
as $$
declare class_start timestamptz; class_box_id uuid; advance_days integer; cutoff_hours integer; weekly_limit integer; week_start timestamptz; cancellation_count integer;
begin
  if (select auth.uid()) <> new.user_id then return new; end if;
  select starts_at,box_id into class_start,class_box_id from public.classes where id=new.class_id;
  if class_start is null then raise exception 'La clase no existe.'; end if;
  select booking_advance_days,cancellation_cutoff_hours,weekly_cancellation_limit into advance_days,cutoff_hours,weekly_limit from public.boxes where id=class_box_id;
  if new.status='booked' and (tg_op='INSERT' or old.status<>'booked') and class_start > now()+make_interval(days=>advance_days) then
    raise exception 'Solo puedes reservar clases con un máximo de % días de antelación.',advance_days;
  end if;
  if tg_op='UPDATE' and old.status='booked' and new.status='cancelled' then
    if class_start <= now()+make_interval(hours=>cutoff_hours) then raise exception 'No puedes cancelar una clase durante las % horas anteriores a su inicio.',cutoff_hours; end if;
    week_start:=date_trunc('week',now());
    select count(*) into cancellation_count from public.class_booking_cancellations where user_id=new.user_id and cancelled_at>=week_start and cancelled_at<week_start+interval '7 days';
    if cancellation_count>=weekly_limit then raise exception 'Has alcanzado el límite de % cancelaciones esta semana.',weekly_limit; end if;
    insert into public.class_booking_cancellations(class_booking_id,user_id,class_id) values(new.id,new.user_id,new.class_id);
  end if;
  return new;
end;
$$;

-- Require a paid current-month payment before an athlete can reserve a class.
create or replace function private.enforce_class_booking_rules()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $function$
declare
  class_start timestamptz;
  class_box_id uuid;
  advance_days integer;
  cutoff_hours integer;
  weekly_limit integer;
  week_start timestamptz;
  cancellation_count integer;
  month_start timestamptz;
  month_end timestamptz;
  payment_exists boolean;
begin
  if (select auth.uid()) <> new.user_id then return new; end if;
  select starts_at, box_id into class_start, class_box_id from public.classes where id = new.class_id;
  if class_start is null then raise exception 'La clase no existe.'; end if;
  select booking_advance_days, cancellation_cutoff_hours, weekly_cancellation_limit into advance_days, cutoff_hours, weekly_limit from public.boxes where id = class_box_id;
  if new.status = 'booked' and (tg_op = 'INSERT' or old.status <> 'booked') then
    month_start := date_trunc('month', now()); month_end := month_start + interval '1 month';
    select exists (select 1 from public.payments p where p.user_id=new.user_id and p.box_id=class_box_id and p.status='paid' and p.paid_at >= month_start and p.paid_at < month_end) into payment_exists;
    if not payment_exists then raise exception 'No puedes reservar clases porque no consta el pago del mes en curso.'; end if;
    if class_start > now() + make_interval(days => advance_days) then raise exception 'Solo puedes reservar clases con un máximo de % días de antelación.', advance_days; end if;
  end if;
  if tg_op = 'UPDATE' and old.status = 'booked' and new.status = 'cancelled' then
    if class_start <= now() + make_interval(hours => cutoff_hours) then raise exception 'No puedes cancelar una clase durante las % horas anteriores a su inicio.', cutoff_hours; end if;
    week_start := date_trunc('week', now());
    select count(*) into cancellation_count from public.class_booking_cancellations where user_id=new.user_id and cancelled_at >= week_start and cancelled_at < week_start + interval '7 days';
    if cancellation_count >= weekly_limit then raise exception 'Has alcanzado el límite de % cancelaciones esta semana.', weekly_limit; end if;
    insert into public.class_booking_cancellations(class_booking_id,user_id,class_id) values (new.id,new.user_id,new.class_id);
  end if;
  return new;
end;
$function$;
