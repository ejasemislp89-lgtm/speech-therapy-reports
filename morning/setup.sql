-- =====================================================================
-- راه‌اندازی سیستم مربی‌های صبح (مرکز کم‌شنوایی) — یک‌بار اجرا شود
-- Supabase  ->  SQL Editor  ->  New query  ->  Paste  ->  Run
-- فقط جدول‌های تازه با پیشوند m_ می‌سازد.
-- به جدول «reports» (گزارش درمانگران) و جدول‌های acc_* (حساب‌کتاب) دست نمی‌زند.
-- اجرای دوباره‌ی آن ضرری ندارد.
-- =====================================================================

-- 1) مدیرهای این سیستم ---------------------------------------------------
create table if not exists public.m_admins (email text primary key);
alter table public.m_admins enable row level security;

create or replace function public.m_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.m_admins
                 where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')))
$$;
revoke all on function public.m_is_admin() from public;
grant execute on function public.m_is_admin() to anon, authenticated;

-- 2) جدول‌ها --------------------------------------------------------------
create table if not exists public.m_trainers (
  id     bigint generated always as identity primary key,
  name   text not null unique,
  level  int  not null,
  active boolean not null default true
);

create table if not exists public.m_classes (
  id         bigint generated always as identity primary key,
  trainer_id bigint not null references public.m_trainers(id),
  kind       text not null default 'group' check (kind in ('group', 'single')),
  day_group  text check (day_group in ('even', 'odd')),   -- کلاس گروهی: زوج یا فرد
  weekdays   int[],                                      -- کلاس تکی: ۰=شنبه ... ۵=پنجشنبه
  slot       text not null,                              -- مثلاً 08-10
  title      text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.m_children (
  id           bigint generated always as identity primary key,
  name         text not null,
  parent_phone text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists public.m_enrollments (
  class_id bigint not null references public.m_classes(id) on delete cascade,
  child_id bigint not null references public.m_children(id) on delete cascade,
  primary key (class_id, child_id)
);

create table if not exists public.m_attendance (
  id          bigint generated always as identity primary key,
  class_id    bigint not null references public.m_classes(id) on delete cascade,
  child_id    bigint not null references public.m_children(id) on delete cascade,
  trainer_id  bigint references public.m_trainers(id),
  att_date    date not null,
  status      text not null check (status in ('p', 'a', 'e')),        -- حاضر / غایب / مرخصی
  rating      text check (rating in ('vg', 'g', 'm', 'w')),           -- بسیار خوب / خوب / متوسط / ضعیف
  followup    text,                                                   -- نتیجه‌ی پیگیری غیبت
  followup_at timestamptz,
  recorded_at timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (class_id, child_id, att_date)
);
create index if not exists m_att_date_idx  on public.m_attendance (att_date);
create index if not exists m_att_child_idx on public.m_attendance (child_id, att_date);

create table if not exists public.m_messages (
  id         bigint generated always as identity primary key,
  trainer_id bigint references public.m_trainers(id),
  child_id   bigint references public.m_children(id) on delete set null,
  body       text not null check (length(body) between 1 and 4000),
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3) دسترسی‌ها (RLS) -------------------------------------------------------
alter table public.m_trainers    enable row level security;
alter table public.m_classes     enable row level security;
alter table public.m_children    enable row level security;
alter table public.m_enrollments enable row level security;
alter table public.m_attendance  enable row level security;
alter table public.m_messages    enable row level security;

drop policy if exists m_trainers_read  on public.m_trainers;
drop policy if exists m_trainers_admin on public.m_trainers;
create policy m_trainers_read  on public.m_trainers for select to anon, authenticated using (true);
create policy m_trainers_admin on public.m_trainers for all to authenticated
  using (public.m_is_admin()) with check (public.m_is_admin());

-- صفحه‌ی مربی (ورود با رمز مشترک) کلاس، کودک و حضور را می‌خواند و ثبت می‌کند
drop policy if exists m_classes_rw     on public.m_classes;
drop policy if exists m_children_rw    on public.m_children;
drop policy if exists m_enrollments_rw on public.m_enrollments;
drop policy if exists m_attendance_rw  on public.m_attendance;
create policy m_classes_rw     on public.m_classes     for all to anon, authenticated using (true) with check (true);
create policy m_children_rw    on public.m_children    for all to anon, authenticated using (true) with check (true);
create policy m_enrollments_rw on public.m_enrollments for all to anon, authenticated using (true) with check (true);
create policy m_attendance_rw  on public.m_attendance  for all to anon, authenticated using (true) with check (true);

-- پیام محرمانه: مربی فقط می‌فرستد (حتی خودش هم نمی‌تواند بخواند)؛ فقط مدیر می‌خواند
drop policy if exists m_messages_send  on public.m_messages;
drop policy if exists m_messages_admin on public.m_messages;
create policy m_messages_send  on public.m_messages for insert to anon, authenticated
  with check (is_read = false);
create policy m_messages_admin on public.m_messages for all to authenticated
  using (public.m_is_admin()) with check (public.m_is_admin());
revoke select, update, delete on public.m_messages from anon;

-- 4) داده‌ی اولیه ----------------------------------------------------------
-- مدیر: همان ایمیل مدیرِ حساب‌کتاب کپی می‌شود (جدول حساب‌کتاب تغییر نمی‌کند).
-- اگر ایمیل دیگری می‌خواهید، این خط را پایین اضافه کنید:
--   insert into public.m_admins (email) values ('YOUR_EMAIL_HERE') on conflict do nothing;
do $$
begin
  if to_regclass('public.acc_users') is not null then
    insert into public.m_admins (email)
    select email from public.acc_users where role = 'admin'
    on conflict do nothing;
  end if;
end $$;

insert into public.m_trainers (name, level) values
  ('خانم عامری', 1),
  ('خانم عباسی', 2),
  ('خانم توکلی', 3)
on conflict (name) do nothing;

-- برای هر مربی ۴ کلاس گروهی: زوج و فرد، ساعت ۸ تا ۱۰ و ۱۰ تا ۱۲
insert into public.m_classes (trainer_id, kind, day_group, slot)
select t.id, 'group', g.dg, s.slot
from public.m_trainers t
cross join (values ('even'), ('odd')) as g(dg)
cross join (values ('08-10'), ('10-12')) as s(slot)
where not exists (
  select 1 from public.m_classes c
  where c.trainer_id = t.id and c.kind = 'group' and c.day_group = g.dg and c.slot = s.slot
);

-- بررسی: باید ۱۲ کلاس و دست‌کم ۱ مدیر نشان دهد
select (select count(*) from public.m_classes) as classes,
       (select count(*) from public.m_admins)  as admins;

-- 5) کاردستی‌ها و وسایل آموزشی مربی‌ها -----------------------------------
-- مربی ثبت و (تا قبل از تأیید) حذف می‌کند؛ فقط مدیر تأیید می‌کند.
create table if not exists public.m_crafts (
  id         bigint generated always as identity primary key,
  trainer_id bigint not null references public.m_trainers(id),
  class_id   bigint references public.m_classes(id) on delete set null,
  title      text not null check (length(title) between 1 and 200),
  note       text,
  made_on    date not null,
  approved   boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists m_crafts_date_idx on public.m_crafts (made_on);
alter table public.m_crafts enable row level security;
drop policy if exists m_crafts_read   on public.m_crafts;
drop policy if exists m_crafts_add    on public.m_crafts;
drop policy if exists m_crafts_remove on public.m_crafts;
drop policy if exists m_crafts_admin  on public.m_crafts;
create policy m_crafts_read   on public.m_crafts for select to anon, authenticated using (true);
create policy m_crafts_add    on public.m_crafts for insert to anon, authenticated with check (approved = false);
create policy m_crafts_remove on public.m_crafts for delete to anon using (approved = false);
create policy m_crafts_admin  on public.m_crafts for all to authenticated
  using (public.m_is_admin()) with check (public.m_is_admin());
