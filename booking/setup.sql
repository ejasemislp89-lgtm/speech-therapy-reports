-- =====================================================================
-- دفتر نوبت‌های کلینیک ترنم (نوبت‌دهی) — یک‌بار اجرا شود
-- Supabase -> SQL Editor -> New query -> Paste -> Run
-- به جدول‌های گزارش‌ها، حساب‌کتاب، بخش صبح و مراجعین جدید دست نمی‌زند.
-- =====================================================================

create extension if not exists pgcrypto;

-- 1) درمانگرها (هرکدام یک «کلید» دارند که لینک اختصاصی‌شان با آن ساخته می‌شود)
create table if not exists public.sch_therapists (
  id     bigint generated always as identity primary key,
  name   text not null unique,
  kind   text,
  token  text not null unique default encode(gen_random_bytes(9),'hex'),
  active boolean not null default true,
  sort   int not null default 0
);

-- 2) نوبت‌ها: هر ردیف = یک سانس نیم‌ساعته از یک روز برای یک درمانگر
--    slot_index از ۱ تا ۱۴ یعنی ۱۴:۰۰ تا ۲۱:۰۰ (شیفت عصر)
create table if not exists public.sch_appointments (
  id           bigint generated always as identity primary key,
  therapist_id bigint not null references public.sch_therapists(id) on delete cascade,
  appt_date    date not null,
  slot_index   int  not null check (slot_index between 1 and 14),
  client_name  text,
  service      text,
  status       text,
  phone        text,
  payment      text,
  note         text,
  updated_at   timestamptz not null default now(),
  created_by   text default (auth.jwt() ->> 'email'),
  unique (therapist_id, appt_date, slot_index)
);

create index if not exists sch_appt_date_idx on public.sch_appointments (appt_date);
create index if not exists sch_appt_th_idx   on public.sch_appointments (therapist_id, appt_date);

create or replace function public.sch_touch() returns trigger
language plpgsql set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists sch_touch on public.sch_appointments;
create trigger sch_touch before update on public.sch_appointments
  for each row execute function public.sch_touch();

-- 3) قفل دسترسی: فقط مدیر و منشی (همان ورود سیستم حساب‌کتاب)
alter table public.sch_therapists   enable row level security;
alter table public.sch_appointments enable row level security;

drop policy if exists sch_th_read  on public.sch_therapists;
drop policy if exists sch_th_admin on public.sch_therapists;
drop policy if exists sch_ap_rw    on public.sch_appointments;

create policy sch_th_read  on public.sch_therapists for select to authenticated
  using (public.acc_my_role() in ('admin','secretary'));
create policy sch_th_admin on public.sch_therapists for all to authenticated
  using (public.acc_my_role() = 'admin') with check (public.acc_my_role() = 'admin');
create policy sch_ap_rw on public.sch_appointments for all to authenticated
  using (public.acc_my_role() in ('admin','secretary'))
  with check (public.acc_my_role() in ('admin','secretary'));

revoke all on public.sch_therapists, public.sch_appointments from anon;
grant select, insert, update, delete on public.sch_therapists   to authenticated;
grant select, insert, update, delete on public.sch_appointments to authenticated;

-- 4) لینک اختصاصی درمانگر: بدون ورود، فقط خواندنی، فقط برنامه‌ی خودش
--    شماره تماس مراجع عمداً برگردانده نمی‌شود.
create or replace function public.sch_public_schedule(p_token text, p_from date, p_to date)
returns table (
  therapist_name text,
  appt_date      date,
  slot_index     int,
  client_name    text,
  service        text,
  status         text,
  payment        text,
  note           text
)
language sql
stable
security definer
set search_path = public
as $$
  select t.name, a.appt_date, a.slot_index, a.client_name, a.service, a.status, a.payment, a.note
  from public.sch_therapists t
  left join public.sch_appointments a
    on a.therapist_id = t.id
   and a.appt_date between p_from and least(p_to, p_from + 60)
  where t.token = p_token
    and t.active
    and length(p_token) >= 12
  order by a.appt_date, a.slot_index
$$;

revoke all on function public.sch_public_schedule(text, date, date) from public;
grant execute on function public.sch_public_schedule(text, date, date) to anon, authenticated;

-- 5) درمانگرها (همان نام‌هایی که در برگه‌ی «تنظیمات» گوگل شیت بود)
insert into public.sch_therapists (name, kind, sort) values
  ('آقای جاسمی',          'گفتاردرمانگر', 1),
  ('خانم امامی',          'گفتاردرمانگر', 2),
  ('خانم کیانی',          'گفتاردرمانگر', 3),
  ('آقای لب ابیان',       'گفتاردرمانگر', 4),
  ('آقای فتحعلی',         'گفتاردرمانگر', 5),
  ('خانم نادری',          'گفتاردرمانگر', 6),
  ('خانم نوری',           'گفتاردرمانگر', 7),
  ('خانم حق شناس',        'روانشناس',     8),
  ('خانم موسوی کاردرمان', 'کاردرمانگر',   9)
on conflict (name) do nothing;
