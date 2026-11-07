-- =====================================================================
-- Notebook for Internship — Supabase setup (idempotent, safe to re-run)
-- Project: https://ivbajugeynbhjnlemjgg.supabase.co
-- Paste the whole file into Dashboard -> SQL Editor -> Run.
--
-- Contract (client maps camelCase <-> snake_case):
--   doneAt -> done_at, createdAt -> created_at, updatedAt -> updated_at
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Table: public.entries  (one row per notebook entry)
-- ---------------------------------------------------------------------
create table if not exists public.entries (
  id          text    primary key,                                   -- client-generated UUID string
  user_id     uuid    not null default auth.uid()
                      references auth.users(id) on delete cascade,  -- owner
  date        text    not null,                                      -- YYYY-MM-DD
  tab         text    not null check (tab in ('work','study','ideas')),
  title       text    not null default '',
  body        text    not null default '',
  done        boolean not null default false,
  done_at     bigint  null,                                          -- ms epoch
  due         text    null,                                          -- YYYY-MM-DD
  priority    text    null check (priority in ('high','medium','low')),
  attachments jsonb   not null default '[]'::jsonb,                  -- array of file metadata
  tags        text[]  not null default '{}',
  created_at  bigint  not null,                                      -- ms epoch
  updated_at  bigint  not null                                       -- ms epoch
);

-- Main read path: "my entries, by day"
create index if not exists entries_user_id_date_idx
  on public.entries (user_id, date);

-- Data API access for signed-in users only (RLS below restricts rows)
grant select, insert, update, delete on public.entries to authenticated;


-- ---------------------------------------------------------------------
-- 2. Row Level Security: each user sees/changes only their own rows
-- ---------------------------------------------------------------------
alter table public.entries enable row level security;

drop policy if exists "entries_select_own" on public.entries;
create policy "entries_select_own" on public.entries
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "entries_insert_own" on public.entries;
create policy "entries_insert_own" on public.entries
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "entries_update_own" on public.entries;
create policy "entries_update_own" on public.entries
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "entries_delete_own" on public.entries;
create policy "entries_delete_own" on public.entries
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 3. Realtime: stream changes on entries (cross-device sync)
-- ---------------------------------------------------------------------
-- Full replica identity so DELETE events carry the old row's id
alter table public.entries replica identity full;

-- Add to the realtime publication only if not already there
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'entries'
     ) then
    alter publication supabase_realtime add table public.entries;
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- 4. Storage: private bucket for attachments (max 50 MB per file)
--    Object path convention: '<auth.uid()>/<fileId>'
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('notebook-files', 'notebook-files', false, 52428800)
on conflict (id) do nothing;

-- Users may only touch objects inside their own '<uid>/' folder
drop policy if exists "notebook_files_select_own" on storage.objects;
create policy "notebook_files_select_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'notebook-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "notebook_files_insert_own" on storage.objects;
create policy "notebook_files_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'notebook-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "notebook_files_update_own" on storage.objects;
create policy "notebook_files_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'notebook-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'notebook-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "notebook_files_delete_own" on storage.objects;
create policy "notebook_files_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'notebook-files'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Done. Verify: Table Editor -> entries (RLS on, 4 policies);
--               Storage -> notebook-files (private, 4 policies).
