create or replace function public.get_box_users(p_box_id uuid)
returns table (
  id uuid,
  first_name text,
  last_name text,
  role text,
  created_at timestamptz,
  phone text,
  email text
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from private.get_box_users(p_box_id);
$$;

revoke all on function public.get_box_users(uuid) from public;
grant execute on function public.get_box_users(uuid) to authenticated;

notify pgrst, 'reload schema';
