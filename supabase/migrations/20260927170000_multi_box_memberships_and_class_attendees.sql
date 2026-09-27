create table if not exists public.user_box_memberships (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 box_id uuid not null references public.boxes(id) on delete cascade,
 created_at timestamptz not null default now(),
 unique(user_id,box_id)
);
alter table public.user_box_memberships enable row level security;
create index if not exists user_box_memberships_user_idx on public.user_box_memberships(user_id);
create index if not exists user_box_memberships_box_idx on public.user_box_memberships(box_id);
insert into public.user_box_memberships(user_id,box_id) select id,box_id from public.profiles where box_id is not null on conflict(user_id,box_id) do nothing;
create policy "Users can view their box memberships" on public.user_box_memberships for select to authenticated using (user_id=auth.uid());
create policy "Box admins can add memberships" on public.user_box_memberships for insert to authenticated with check (private.is_box_admin(box_id));
create policy "Box admins can remove memberships" on public.user_box_memberships for delete to authenticated using (private.is_box_admin(box_id));
drop policy if exists "Users can view member boxes" on public.boxes;
create policy "Users can view member boxes" on public.boxes for select to authenticated using (id=private.current_box_id() or exists(select 1 from public.user_box_memberships m where m.user_id=auth.uid() and m.box_id=boxes.id));
create or replace function private.switch_active_box(p_box_id uuid) returns public.profiles language plpgsql security definer set search_path=public,private as $$ declare r public.profiles; begin if auth.uid() is null then raise exception 'Sesión no válida.'; end if; if not exists(select 1 from public.user_box_memberships where user_id=auth.uid() and box_id=p_box_id) then raise exception 'No tienes acceso a este box.'; end if; update public.profiles set box_id=p_box_id,updated_at=now() where id=auth.uid() returning * into r; return r; end $$;
revoke all on function private.switch_active_box(uuid) from public,anon; grant execute on function private.switch_active_box(uuid) to authenticated;
create or replace function public.switch_active_box(p_box_id uuid) returns public.profiles language sql security invoker set search_path=public,private as $$ select private.switch_active_box(p_box_id); $$;
revoke execute on function public.switch_active_box(uuid) from public,anon; grant execute on function public.switch_active_box(uuid) to authenticated;
drop policy if exists "Users can view attendees in their box classes" on public.class_bookings;
create policy "Users can view attendees in their box classes" on public.class_bookings for select to authenticated using (exists(select 1 from public.classes c where c.id=class_bookings.class_id and c.box_id=private.current_box_id()));
drop policy if exists "Users can view member athlete profiles in their box" on public.profiles;
create policy "Users can view member athlete profiles in their box" on public.profiles for select to authenticated using (role='athlete' and exists(select 1 from public.user_box_memberships m where m.user_id=profiles.id and m.box_id=private.current_box_id()));