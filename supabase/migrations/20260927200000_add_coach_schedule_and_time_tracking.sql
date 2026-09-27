-- Calendario laboral y registro de jornada de coaches.
create table if not exists public.coach_availability (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  coach_id uuid not null references public.profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  valid_from date,
  valid_until date,
  notes text,
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);
create index if not exists coach_availability_box_coach_idx on public.coach_availability(box_id,coach_id,weekday);

create table if not exists public.coach_shifts (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  coach_id uuid not null references public.profiles(id) on delete cascade,
  class_id uuid references public.classes(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  shift_type text not null default 'class' check (shift_type in ('class','other')),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists coach_shifts_box_start_idx on public.coach_shifts(box_id,starts_at);
create index if not exists coach_shifts_coach_start_idx on public.coach_shifts(coach_id,starts_at);

create table if not exists public.coach_time_entries (
  id uuid primary key default gen_random_uuid(),
  box_id uuid not null references public.boxes(id) on delete cascade,
  coach_id uuid not null references public.profiles(id) on delete cascade,
  clock_in timestamptz not null,
  clock_out timestamptz,
  source text not null default 'web' check (source in ('web','admin','device')),
  notes text,
  created_at timestamptz not null default now(),
  check (clock_out is null or clock_out > clock_in)
);
create index if not exists coach_time_entries_box_in_idx on public.coach_time_entries(box_id,clock_in desc);
create index if not exists coach_time_entries_coach_in_idx on public.coach_time_entries(coach_id,clock_in desc);
create unique index if not exists coach_time_entries_one_open_idx on public.coach_time_entries(coach_id) where clock_out is null;

alter table public.coach_availability enable row level security;
alter table public.coach_shifts enable row level security;
alter table public.coach_time_entries enable row level security;

create policy "Box admins manage coach availability" on public.coach_availability for all to authenticated using (private.is_box_admin(box_id)) with check (private.is_box_admin(box_id));
create policy "Box members view coach availability" on public.coach_availability for select to authenticated using (box_id=private.current_box_id());
create policy "Box admins manage coach shifts" on public.coach_shifts for all to authenticated using (private.is_box_admin(box_id)) with check (private.is_box_admin(box_id));
create policy "Coaches view own shifts" on public.coach_shifts for select to authenticated using (box_id=private.current_box_id() and coach_id=auth.uid());
create policy "Box admins manage time entries" on public.coach_time_entries for all to authenticated using (private.is_box_admin(box_id)) with check (private.is_box_admin(box_id));
create policy "Coaches view own time entries" on public.coach_time_entries for select to authenticated using (box_id=private.current_box_id() and coach_id=auth.uid());
create policy "Coaches clock in" on public.coach_time_entries for insert to authenticated with check (box_id=private.current_box_id() and coach_id=auth.uid());
create policy "Coaches clock out own entry" on public.coach_time_entries for update to authenticated using (box_id=private.current_box_id() and coach_id=auth.uid()) with check (box_id=private.current_box_id() and coach_id=auth.uid());
