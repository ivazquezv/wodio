drop policy if exists "Authenticated users can view their box" on public.boxes;
create policy "Authenticated users can view their box" on public.boxes for select to authenticated using (id=(select private.current_box_id()));
drop policy if exists "Box admins can update their box" on public.boxes;
create policy "Box admins can update their box" on public.boxes for update to authenticated using ((select private.is_box_admin(id))) with check ((select private.is_box_admin(id)));