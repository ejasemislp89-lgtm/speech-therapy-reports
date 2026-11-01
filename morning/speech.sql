-- =====================================================================
-- گفتاردرمانی هفتگی کودکان نوبت صبح (یک‌بار اجرا شود)
-- Supabase -> SQL Editor -> New query -> Paste -> Run
-- فقط یک جدول تازه (m_speech) می‌سازد؛ به بقیهٔ جدول‌ها دست نمی‌زند.
-- اجرای دوباره‌ی آن ضرری ندارد.
-- =====================================================================

-- برای هر کودک و هر هفته (شنبه تا جمعه) یک ردیف: ۰، ۱ یا ۲ جلسه گفتاردرمانی
-- week_start = تاریخ میلادیِ روز شنبهٔ آن هفته
create table if not exists public.m_speech (
  id         bigint generated always as identity primary key,
  child_id   bigint not null references public.m_children(id) on delete cascade,
  week_start date   not null,
  sessions   int    not null check (sessions between 0 and 2),
  trainer_id bigint references public.m_trainers(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (child_id, week_start)
);
create index if not exists m_speech_week_idx on public.m_speech (week_start);

alter table public.m_speech enable row level security;

-- مربی‌ها (ورود با رمز مشترک) و مدیریت: دیدن، ثبت و ویرایش
drop policy if exists m_speech_rw on public.m_speech;
create policy m_speech_rw on public.m_speech for all to anon, authenticated
  using (true) with check (true);

grant select, insert, update, delete on public.m_speech to anon, authenticated;
