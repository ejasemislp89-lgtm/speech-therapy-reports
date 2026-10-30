create table if not exists public.case_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  patient_name text not null check (char_length(patient_name) between 1 and 200),
  author_name text not null check (char_length(author_name) between 1 and 100),
  author_role text not null check (author_role in ('slp','ot')),
  body text not null check (char_length(body) between 1 and 4000)
);
create index if not exists case_messages_created_at_idx on public.case_messages (created_at desc);
alter table public.case_messages enable row level security;
drop policy if exists case_messages_read on public.case_messages;
drop policy if exists case_messages_send on public.case_messages;
create policy case_messages_read on public.case_messages for select to anon, authenticated using (true);
create policy case_messages_send on public.case_messages for insert to anon, authenticated with check (true);
