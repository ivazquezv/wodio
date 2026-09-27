revoke execute on function public.get_super_admin_dashboard() from anon;
grant execute on function public.get_super_admin_dashboard() to authenticated;

revoke execute on function public.super_admin_update_box(uuid, text, text) from anon;
grant execute on function public.super_admin_update_box(uuid, text, text) to authenticated;
