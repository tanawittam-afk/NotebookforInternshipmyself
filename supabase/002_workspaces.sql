-- =====================================================================
-- Notebook for Internship — Migration 002: workspaces (idempotent, additive)
-- Project: https://ivbajugeynbhjnlemjgg.supabase.co
-- Prerequisite: setup.sql has already been run.
-- Paste the whole file into Dashboard -> SQL Editor -> Run. Safe to re-run.
--
-- Adds:
--   1. public.workspaces  (company / department / position tree)
--   2. public.entries.workspace_ids / assigned_by / checklist (all defaulted;
--      existing rows are untouched and keep working)
--
-- Contract (client maps camelCase <-> snake_case):
--   parentId -> parent_id, archivedAt -> archived_at, openedOn -> opened_on,
--   createdAt -> created_at, updatedAt -> updated_at,
--   workspaceIds -> workspace_ids, assignedBy -> assigned_by
--
-- Hierarchy rules (company has no parent; department -> company;
-- position -> company or department) are enforced client-side only.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Table: public.workspaces  (one row per company / department / position)
-- ---------------------------------------------------------------------
create table if not exists public.workspaces (
  id          text    primary key,                                   -- client-generated UUID string
  user_id     uuid    not null default auth.uid()
                      references auth.users(id) on delete cascade,  -- owner
  -- null = company. NO ACTION (not RESTRICT): still blocks deleting a parent
  -- that has children, but is checked at end of statement so the
  -- auth.users cascade can delete a whole tree in one go.
  parent_id   text    null
                      references public.workspaces(id) on delete no action,
  kind        text    not null check (kind in ('company','department','position')),
  name        text    not null check (length(trim(name)) > 0),
  color       text    null,                                          -- e.g. '#6b8f5e'
  sort        integer not null default 0,
  archived_at bigint  null,                                          -- ms epoch
  headcount   integer null check (headcount >= 0),                   -- position card
  status      text    null check (status in ('open','hold','closed')), -- position card
  channels    jsonb   not null default '[]'::jsonb,                  -- [{name, url}] where the job is posted
  opened_on   text    null,                                          -- YYYY-MM-DD
  note        text    not null default '',
  created_at  bigint  not null,                                      -- ms epoch
  updated_at  bigint  not null                                       -- ms epoch
);

-- Main read path: "my workspaces, children of X"
create index if not exists workspaces_user_id_parent_id_idx
  on public.workspaces (user_id, parent_id);

-- Data API access for signed-in users only (RLS below restricts rows)
grant select, insert, update, delete on public.workspaces to authenticated;


-- ---------------------------------------------------------------------
-- 2. Row Level Security: each user sees/changes only their own rows
-- ---------------------------------------------------------------------
alter table public.workspaces enable row level security;

drop policy if exists "workspaces_select_own" on public.workspaces;
create policy "workspaces_select_own" on public.workspaces
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "workspaces_insert_own" on public.workspaces;
create policy "workspaces_insert_own" on public.workspaces
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "workspaces_update_own" on public.workspaces;
create policy "workspaces_update_own" on public.workspaces
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "workspaces_delete_own" on public.workspaces;
create policy "workspaces_delete_own" on public.workspaces
  for delete to authenticated
  using (user_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 3. Realtime: stream changes on workspaces (cross-device sync)
-- ---------------------------------------------------------------------
-- Full replica identity so DELETE events carry the old row's id
alter table public.workspaces replica identity full;

-- Add to the realtime publication only if not already there
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'workspaces'
     ) then
    alter publication supabase_realtime add table public.workspaces;
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- 4. New columns on public.entries (additive; defaults backfill old rows)
-- ---------------------------------------------------------------------
alter table public.entries
  add column if not exists workspace_ids text[] not null default '{}',          -- workspaces.id values; no FK
  add column if not exists assigned_by   text   null,                           -- 'mentor' | 'self' | free-text name
  add column if not exists checklist     jsonb  not null default '[]'::jsonb;   -- [{id, text, done}]

-- "entries tagged with workspace X":  workspace_ids @> array['<id>']
create index if not exists entries_workspace_ids_gin_idx
  on public.entries using gin (workspace_ids);

-- Done. Verify: Table Editor -> workspaces (RLS on, 4 policies);
--               entries has workspace_ids / assigned_by / checklist columns.
