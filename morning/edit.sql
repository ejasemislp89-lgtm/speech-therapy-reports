-- =====================================================================
-- اجازهٔ ویرایش برای مربی‌ها در بخش صبح (یک‌بار اجرا شود)
-- Supabase -> SQL Editor -> New query -> Paste -> Run
-- به جدول‌های گزارش‌ها، حساب‌کتاب و مراجعین جدید دست نمی‌زند.
-- =====================================================================

-- ۱) کاردستی: مربی بتواند مورد تأییدنشدهٔ خودش را ویرایش کند.
--    (موردی که مدیر تأیید کرده با ویرایش دوباره به حالت «در انتظار تأیید» برمی‌گردد،
--     و تا وقتی تأیید نشده قابل ویرایش است.)
drop policy if exists m_crafts_edit on public.m_crafts;
create policy m_crafts_edit on public.m_crafts for update to anon, authenticated
  using (approved = false) with check (approved = false);

-- ۲) پیام محرمانه: مربی بتواند پیام خودش را تا وقتی مدیریت نخوانده ویرایش یا حذف کند.
--    هر پیام یک «کلید» تصادفی دارد که فقط روی گوشی خود مربی ذخیره می‌شود؛
--    بدون آن کلید هیچ‌کس پیام را نمی‌بیند، تغییر نمی‌دهد و پاک نمی‌کند.
alter table public.m_messages add column if not exists edit_token text;

create or replace function public.m_msg_send(p_trainer bigint, p_child bigint, p_body text, p_token text)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v bigint;
begin
  if p_body is null or length(btrim(p_body)) = 0 then
    raise exception 'empty body';
  end if;
  if p_token is null or length(p_token) < 16 then
    raise exception 'bad token';
  end if;
  insert into public.m_messages (trainer_id, child_id, body, is_read, edit_token)
  values (p_trainer, p_child, left(p_body, 4000), false, p_token)
  returning id into v;
  return v;
end $$;

create or replace function public.m_msg_save(p_id bigint, p_token text, p_body text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if p_token is null or length(p_token) < 16 then return false; end if;
  if p_body is null or length(btrim(p_body)) = 0 then return false; end if;
  update public.m_messages set body = left(p_body, 4000)
   where id = p_id and edit_token = p_token and is_read = false;
  get diagnostics n = row_count;
  return n > 0;
end $$;

create or replace function public.m_msg_remove(p_id bigint, p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare n int;
begin
  if p_token is null or length(p_token) < 16 then return false; end if;
  delete from public.m_messages
   where id = p_id and edit_token = p_token and is_read = false;
  get diagnostics n = row_count;
  return n > 0;
end $$;

revoke all on function public.m_msg_send(bigint, bigint, text, text) from public;
revoke all on function public.m_msg_save(bigint, text, text)        from public;
revoke all on function public.m_msg_remove(bigint, text)            from public;
grant execute on function public.m_msg_send(bigint, bigint, text, text) to anon, authenticated;
grant execute on function public.m_msg_save(bigint, text, text)         to anon, authenticated;
grant execute on function public.m_msg_remove(bigint, text)             to anon, authenticated;
