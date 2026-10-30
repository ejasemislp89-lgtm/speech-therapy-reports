-- =====================================================================
-- ریزش مراجعین: کسانی که قبلاً می‌آمدند و مدتی است نمی‌آیند
-- بخشی از سیستم حساب‌کتاب؛ همان ورود مدیر و منشی (acc_users / acc_my_role)
-- =====================================================================

create table if not exists public.churn_cases (
  id           bigint generated always as identity primary key,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   text default (auth.jwt() ->> 'email'),

  client_name  text not null,
  therapist_id bigint references public.acc_therapists(id),
  phone        text,
  sessions     int,
  last_visit   date,

  -- open: هنوز پیگیری نشده · returned: برمی‌گردد · paused: موقتاً نمی‌آید
  -- discharged: درمانش تمام شده · lost: قطع کرده
  status       text not null default 'open'
               check (status in ('open','returned','paused','discharged','lost')),
  next_check   date,
  reason       text,
  note         text,
  source       text not null default 'manual' check (source in ('manual','auto')),
  log          jsonb not null default '[]'::jsonb
);

create index if not exists churn_status_idx on public.churn_cases (status, next_check);
create index if not exists churn_name_idx   on public.churn_cases (client_name);

create or replace function public.churn_touch() returns trigger
language plpgsql set search_path = public as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists churn_touch on public.churn_cases;
create trigger churn_touch before update on public.churn_cases
  for each row execute function public.churn_touch();

alter table public.churn_cases enable row level security;

drop policy if exists churn_read   on public.churn_cases;
drop policy if exists churn_insert on public.churn_cases;
drop policy if exists churn_update on public.churn_cases;
drop policy if exists churn_delete on public.churn_cases;

create policy churn_read   on public.churn_cases for select to authenticated
  using (public.acc_my_role() in ('admin','secretary'));
create policy churn_insert on public.churn_cases for insert to authenticated
  with check (public.acc_my_role() in ('admin','secretary'));
create policy churn_update on public.churn_cases for update to authenticated
  using (public.acc_my_role() in ('admin','secretary'))
  with check (public.acc_my_role() in ('admin','secretary'));
-- حذف فقط با مدیر
create policy churn_delete on public.churn_cases for delete to authenticated
  using (public.acc_my_role() = 'admin');

revoke all on public.churn_cases from anon;
grant select, insert, update, delete on public.churn_cases to authenticated;
