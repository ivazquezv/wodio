alter table public.profiles add column if not exists phone text;

create or replace function private.get_box_users(p_box_id uuid)
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
security definer
set search_path = ''
as $$
  select p.id,p.first_name,p.last_name,p.role,p.created_at,p.phone,u.email
  from public.profiles p
  join auth.users u on u.id=p.id
  where p.box_id=p_box_id
    and private.is_box_admin(p_box_id)
  order by p.created_at desc;
$$;

revoke all on function private.get_box_users(uuid) from public;
grant execute on function private.get_box_users(uuid) to authenticated;