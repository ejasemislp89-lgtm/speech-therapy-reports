-- =====================================================================
-- راه‌اندازی سیستم حساب‌کتاب کلینیک (یک‌بار اجرا شود)
-- Supabase  ->  SQL Editor  ->  New query  ->  Paste  ->  Run
-- این فایل به جدول «reports» (سیستم گزارش‌دهی) دست نمی‌زند.
-- =====================================================================

-- 1) جدول‌ها -----------------------------------------------------------
create table if not exists public.acc_users (
  email text primary key,
  role  text not null check (role in ('admin', 'secretary'))
);

create table if not exists public.acc_therapists (
  id           bigint generated always as identity primary key,
  name         text not null unique,
  kind         text,
  center_share numeric(5,2) not null default 0 check (center_share between 0 and 100),
  own_share    numeric(5,2) not null default 0 check (own_share between 0 and 100),
  active       boolean not null default true
);

create table if not exists public.acc_services (
  id            bigint generated always as identity primary key,
  name          text not null unique,
  default_price bigint not null default 0 check (default_price >= 0),
  active        boolean not null default true
);

create table if not exists public.acc_visits (
  id           bigint generated always as identity primary key,
  visit_date   date not null,
  created_at   timestamptz not null default now(),
  therapist_id bigint not null references public.acc_therapists(id),
  service_id   bigint references public.acc_services(id),
  service_name text,
  patient_name text not null,
  amount       bigint not null check (amount >= 0),
  source       text not null check (source in ('center', 'own')),
  pay_method   text not null check (pay_method in ('cash', 'card', 'card_refah', 'card_mellat', 'transfer', 'unpaid')),
  note         text,
  created_by   text default (auth.jwt() ->> 'email')
);

create index if not exists acc_visits_date_idx      on public.acc_visits (visit_date);
create index if not exists acc_visits_therapist_idx on public.acc_visits (therapist_id, visit_date);

-- 2) تابع نقش کاربر ------------------------------------------------------
create or replace function public.acc_my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.acc_users
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  limit 1
$$;

revoke all on function public.acc_my_role() from public, anon;
grant execute on function public.acc_my_role() to authenticated;

-- 3) قفل دسترسی (RLS) ----------------------------------------------------
alter table public.acc_users      enable row level security;
alter table public.acc_therapists enable row level security;
alter table public.acc_services   enable row level security;
alter table public.acc_visits     enable row level security;

-- acc_users: هیچ سیاستی ندارد، یعنی فقط از طریق تابع بالا خوانده می‌شود.

drop policy if exists acc_therapists_read  on public.acc_therapists;
drop policy if exists acc_therapists_admin on public.acc_therapists;
create policy acc_therapists_read  on public.acc_therapists for select to authenticated
  using (public.acc_my_role() in ('admin', 'secretary'));
create policy acc_therapists_admin on public.acc_therapists for all to authenticated
  using (public.acc_my_role() = 'admin') with check (public.acc_my_role() = 'admin');

drop policy if exists acc_services_read  on public.acc_services;
drop policy if exists acc_services_admin on public.acc_services;
create policy acc_services_read  on public.acc_services for select to authenticated
  using (public.acc_my_role() in ('admin', 'secretary'));
create policy acc_services_admin on public.acc_services for all to authenticated
  using (public.acc_my_role() = 'admin') with check (public.acc_my_role() = 'admin');

-- مدیر: همه‌چیز در هر تاریخ
drop policy if exists acc_visits_admin on public.acc_visits;
create policy acc_visits_admin on public.acc_visits for all to authenticated
  using (public.acc_my_role() = 'admin') with check (public.acc_my_role() = 'admin');

-- منشی: فقط مراجعه‌های «امروز» (به وقت تهران) را ببیند، ثبت، اصلاح و حذف کند
drop policy if exists acc_visits_secretary on public.acc_visits;
create policy acc_visits_secretary on public.acc_visits for all to authenticated
  using (
    public.acc_my_role() = 'secretary'
    and visit_date = (now() at time zone 'Asia/Tehran')::date
  )
  with check (
    public.acc_my_role() = 'secretary'
    and visit_date = (now() at time zone 'Asia/Tehran')::date
  );

-- کاربر بدون ورود (anon) هیچ دسترسی‌ای به این جدول‌ها ندارد.
revoke all on public.acc_users, public.acc_therapists, public.acc_services, public.acc_visits from anon;

-- 4) داده‌ی اولیه --------------------------------------------------------
-- درصد سهم‌ها عمداً صفر گذاشته شده تا خودتان در «تنظیمات» برنامه وارد کنید.
insert into public.acc_therapists (name, kind) values
  ('احسان جاسمی',   'گفتاردرمانگر'),
  ('فاطمه امامی',   'گفتاردرمانگر'),
  ('فاطمه کیانی',   'گفتاردرمانگر'),
  ('امین لب ابیان', 'گفتاردرمانگر'),
  ('کامیاب فتحعلی', 'گفتاردرمانگر'),
  ('سارا نادری',    'گفتاردرمانگر'),
  ('مهسا جوادنوری', 'گفتاردرمانگر'),
  ('پریسا حق شناس', 'روانشناس'),
  ('خانم موسوی',    'کاردرمانگر')
on conflict (name) do nothing;

-- تعرفه‌ها هم در «تنظیمات» برنامه تغییر می‌کند.
insert into public.acc_services (name, default_price) values
  ('گفتاردرمانی', 0),
  ('کاردرمانی',   0),
  ('روانشناسی',   0),
  ('ارزیابی',     0)
on conflict (name) do nothing;

-- 5) کاربران (قبل از اجرا، دو ایمیل زیر را با ایمیل‌های واقعی عوض کنید) ---
-- ابتدا در Supabase: Authentication -> Users -> Add user (با گزینه‌ی Auto Confirm) دو کاربر بسازید.
insert into public.acc_users (email, role) values
  ('ADMIN_EMAIL_HERE',     'admin'),
  ('SECRETARY_EMAIL_HERE', 'secretary')
on conflict (email) do update set role = excluded.role;
