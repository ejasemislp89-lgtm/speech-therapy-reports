-- =====================================================================
-- پیشنهاد کلاس خصوصی عصر به خانواده‌های شیفت صبح (یک‌بار اجرا شود)
-- Supabase -> SQL Editor -> New query -> Paste -> Run
-- =====================================================================

create table if not exists public.m_referrals (
  id           bigint generated always as identity primary key,
  trainer_id   bigint not null references public.m_trainers(id) on delete cascade,
  child_id     bigint not null references public.m_children(id) on delete cascade,
  suggested_on date not null default ((now() at time zone 'Asia/Tehran')::date),

  -- دلیل درمانی: چرا این کودک از جلسهٔ خصوصی سود می‌برد (الزامی)
  need         text not null,
  -- برآورد مربی از امکان مالی خانواده، فقط برای اولویت‌بندی
  afford       text check (afford in ('yes','maybe','no','unknown')) default 'unknown',

  -- suggested: پیشنهاد داده شد · interested: علاقه نشان داد
  -- booked: نوبت گرفت · started: شروع کرد · declined: نخواست
  status       text not null default 'suggested'
               check (status in ('suggested','interested','booked','started','declined')),
  decline_reason text,
  note         text,
  log          jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (child_id, trainer_id)
);

create index if not exists m_ref_trainer_idx on public.m_referrals (trainer_id, suggested_on);
create index if not exists m_ref_status_idx  on public.m_referrals (status);

create or replace function public.m_ref_touch() returns trigger
language plpgsql set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists m_ref_touch on public.m_referrals;
create trigger m_ref_touch before update on public.m_referrals
  for each row execute function public.m_ref_touch();

alter table public.m_referrals enable row level security;

-- مربی‌ها (بدون ورود، با رمز مشترک) و مدیریت: دیدن، ثبت و ویرایش
drop policy if exists m_ref_rw     on public.m_referrals;
drop policy if exists m_ref_admin  on public.m_referrals;
create policy m_ref_rw on public.m_referrals for all to anon, authenticated
  using (true) with check (true);

grant select, insert, update, delete on public.m_referrals to anon, authenticated;
