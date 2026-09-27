create or replace function private.set_box_membership(
  p_user_id uuid,
  p_box_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path=''
as $function$
begin
  if not private.is_box_admin(p_box_id) then
    raise exception 'No tienes permisos para gestionar miembros de este box.';
  end if;

  if p_enabled then
    insert into public.user_box_memberships (user_id, box_id)
    values (p_user_id, p_box_id)
    on conflict (user_id, box_id) do nothing;
  else
    delete from public.user_box_memberships
    where user_id = p_user_id
      and box_id = p_box_id;
  end if;
end;
$function$;

create or replace function public.set_box_membership(
  p_user_id uuid,
  p_box_id uuid,
  p_enabled boolean
)
returns void
language sql
security invoker
set search_path=''
as $function$
  select private.set_box_membership(p_user_id, p_box_id, p_enabled)
$function$;

revoke all on function private.set_box_membership(uuid, uuid, boolean) from public, anon;
revoke all on function public.set_box_membership(uuid, uuid, boolean) from public, anon;
grant execute on function public.set_box_membership(uuid, uuid, boolean) to authenticated;
