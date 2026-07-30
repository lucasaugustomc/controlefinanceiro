-- MEU FINANCEIRO — BANCO PRIVADO PARA SINCRONIZAÇÃO
-- Execute todo este arquivo uma única vez no SQL Editor do seu projeto Supabase.
-- Os dados chegam ao banco já criptografados no navegador com AES-GCM.

create table if not exists public.finance_documents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload text not null,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  device_name text
);

create table if not exists public.finance_history (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload text not null,
  revision bigint not null,
  device_name text,
  created_at timestamptz not null default now()
);

create index if not exists finance_history_user_revision_idx
  on public.finance_history (user_id, revision desc);

alter table public.finance_documents enable row level security;
alter table public.finance_history enable row level security;

revoke all on table public.finance_documents from anon;
revoke all on table public.finance_history from anon;
grant select, insert, update on table public.finance_documents to authenticated;
grant select, insert, delete on table public.finance_history to authenticated;
grant usage, select on sequence public.finance_history_id_seq to authenticated;

drop policy if exists "Cada usuario le seus dados atuais" on public.finance_documents;
create policy "Cada usuario le seus dados atuais"
  on public.finance_documents
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Cada usuario cria seus dados atuais" on public.finance_documents;
create policy "Cada usuario cria seus dados atuais"
  on public.finance_documents
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Cada usuario atualiza seus dados atuais" on public.finance_documents;
create policy "Cada usuario atualiza seus dados atuais"
  on public.finance_documents
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Cada usuario le seu historico" on public.finance_history;
create policy "Cada usuario le seu historico"
  on public.finance_history
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Cada usuario cria seu historico" on public.finance_history;
create policy "Cada usuario cria seu historico"
  on public.finance_history
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Cada usuario limpa seu historico" on public.finance_history;
create policy "Cada usuario limpa seu historico"
  on public.finance_history
  for delete
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.finance_archive_previous_version()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  insert into public.finance_history (user_id, payload, revision, device_name, created_at)
  values (old.user_id, old.payload, old.revision, old.device_name, old.updated_at);

  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists finance_documents_archive_trigger on public.finance_documents;
create trigger finance_documents_archive_trigger
before update on public.finance_documents
for each row execute function public.finance_archive_previous_version();

-- Mantém as 50 versões mais recentes de cada usuário.
create or replace function public.finance_trim_history()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.finance_history
  where user_id = new.user_id
    and id not in (
      select id
      from public.finance_history
      where user_id = new.user_id
      order by revision desc, id desc
      limit 50
    );
  return new;
end;
$$;

drop trigger if exists finance_history_trim_trigger on public.finance_history;
create trigger finance_history_trim_trigger
after insert on public.finance_history
for each row execute function public.finance_trim_history();
