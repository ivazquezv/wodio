create table if not exists public.box_hours (
 id uuid primary key default gen_random_uuid(),
 box_id uuid not null references public.boxes(id) on delete cascade,
 weekday smallint not null check (weekday between 0 and 6),
 open_time time,
 close_time time,
 closed boolean not null default false,
 notes text,
 unique(box_id,weekday),
 check ((closed=true and open_time is null and close_time is null) or (closed=false and open_time is not null and close_time is not null and close_time>open_time))
);
alter table public.box_hours enable row level security;
drop policy if exists "Box admins manage box hours" on public.box_hours;
create policy "Box admins manage box hours" on public.box_hours for all to authenticated using (private.is_box_admin(box_id)) with check (private.is_box_admin(box_id));
drop policy if exists "Box members view box hours" on public.box_hours;
create policy "Box members view box hours" on public.box_hours for select to authenticated using (box_id=private.current_box_id());