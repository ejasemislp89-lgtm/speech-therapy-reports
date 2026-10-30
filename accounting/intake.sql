-- =====================================================================
-- مراجعین جدید (تماس‌ها، پیگیری، بیعانه، نوبت ارزیابی، شروع درمان)
-- بخشی از سیستم حساب‌کتاب؛ همان ورود مدیر و منشی (acc_users / acc_my_role)
-- به جدول‌های گزارش‌ها، حساب‌کتاب و بخش صبح دست نمی‌زند.
-- =====================================================================

create table if not exists public.intake_leads (
  id                bigint generated always as identity primary key,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        text default (auth.jwt() ->> 'email'),
  call_date         date not null default ((now() at time zone 'Asia/Tehran')::date),

  -- اطلاعات تماس
  child_name        text not null,
  parent_name       text,
  phone             text not null,
  child_age         text,
  service           text,            -- گفتاردرمانی / کاردرمانی / روانشناسی / ...
  concern           text,            -- علت مراجعه
  referral          text,            -- از کجا آشنا شدند

  -- وضعیت
  status            text not null default 'followup'
                    check (status in ('followup', 'booked', 'active', 'lost')),
  next_followup     date,
  followup_count    int not null default 0,

  -- بیعانه و نوبت ارزیابی
  deposit_amount    bigint check (deposit_amount is null or deposit_amount >= 0),
  deposit_method    text,
  deposit_date      date,
  appt_date         date,
  appt_time         text,
  assessor_id       bigint references public.acc_therapists(id),

  -- بعد از ارزیابی
  therapist_id      bigint references public.acc_therapists(id),
  sessions_per_week int check (sessions_per_week is null or sessions_per_week between 1 and 7),
  start_date        date,

  lost_reason       text,
  note              text,
  log               jsonb not null default '[]'::jsonb
);

create index if not exists intake_status_idx   on public.intake_leads (status, next_followup);
create index if not exists intake_appt_idx     on public.intake_leads (appt_date);
create index if not exists intake_calldate_idx on public.intake_leads (call_date);

create or replace function public.intake_touch() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists intake_touch on public.intake_leads;
create trigger intake_touch before update on public.intake_leads
  for each row execute function public.intake_touch();

alter table public.intake_leads enable row level security;

-- مدیر و منشی: دیدن، ثبت و ویرایش همه‌ی مراجعین جدید (برای پیگیری روزهای بعد لازم است)
drop policy if exists intake_read   on public.intake_leads;
drop policy if exists intake_insert on public.intake_leads;
drop policy if exists intake_update on public.intake_leads;
drop policy if exists intake_delete on public.intake_leads;
create policy intake_read   on public.intake_leads for select to authenticated
  using (public.acc_my_role() in ('admin', 'secretary'));
create policy intake_insert on public.intake_leads for insert to authenticated
  with check (public.acc_my_role() in ('admin', 'secretary'));
create policy intake_update on public.intake_leads for update to authenticated
  using (public.acc_my_role() in ('admin', 'secretary'))
  with check (public.acc_my_role() in ('admin', 'secretary'));
-- حذف فقط با مدیر
create policy intake_delete on public.intake_leads for delete to authenticated
  using (public.acc_my_role() = 'admin');

revoke all on public.intake_leads from anon;
grant select, insert, update, delete on public.intake_leads to authenticated;
