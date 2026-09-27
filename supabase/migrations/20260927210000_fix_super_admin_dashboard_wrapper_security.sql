create or replace function public.get_super_admin_dashboard()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select private.get_super_admin_dashboard();
$function$;

revoke execute on function private.get_super_admin_dashboard() from public;
revoke execute on function private.get_super_admin_dashboard() from anon;
revoke execute on function private.get_super_admin_dashboard() from authenticated;
revoke execute on function public.get_super_admin_dashboard() from anon;
grant execute on function public.get_super_admin_dashboard() to authenticated;
