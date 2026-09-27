-- Allow coaches to view and mark attendance only for classes assigned to them.
drop policy if exists "Coaches can view bookings for their classes" on public.class_bookings;
create policy "Coaches can view bookings for their classes"
on public.class_bookings for select to authenticated
using (exists (select 1 from public.classes c where c.id=class_bookings.class_id and c.coach_id=(select auth.uid()) and c.box_id=(select private.current_box_id())));

drop policy if exists "Coaches can mark attendance for their classes" on public.class_bookings;
create policy "Coaches can mark attendance for their classes"
on public.class_bookings for update to authenticated
using (exists (select 1 from public.classes c where c.id=class_bookings.class_id and c.coach_id=(select auth.uid()) and c.box_id=(select private.current_box_id())))
with check (exists (select 1 from public.classes c where c.id=class_bookings.class_id and c.coach_id=(select auth.uid()) and c.box_id=(select private.current_box_id())) and status in ('booked','attended','absent','cancelled'));
