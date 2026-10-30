create or replace function public.admin_delete_case_message(p_id uuid, p_pass text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_pass is distinct from 'admin1880' then
    raise exception 'unauthorized';
  end if;
  delete from public.case_messages where id = p_id;
end;
$$;
revoke all on function public.admin_delete_case_message(uuid, text) from public;
grant execute on function public.admin_delete_case_message(uuid, text) to anon, authenticated;
