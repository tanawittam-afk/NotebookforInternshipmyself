-- =====================================================================
-- Notebook for Internship — Migration 003: mentor (พี่เลี้ยง) account
-- (idempotent, additive, safe to re-run)
-- Project: https://ivbajugeynbhjnlemjgg.supabase.co
-- Prerequisite: setup.sql and 002_workspaces.sql have already been run.
-- Paste the whole file into Dashboard -> SQL Editor -> Run. Safe to re-run.
-- Design: docs/mentor-architecture.md
--
-- Adds:
--   1. public.mentorships      (intern <-> mentor link; exactly one mentor per
--                               intern, one intern per mentor)
--   2. public.entries.status / is_private / blocked / blocked_at / created_by
--      (all defaulted; status backfilled from done; created_by from user_id)
--   3. helper functions        is_mentor_of(uuid), can_access_entry(text),
--                               can_read_notebook_file(text)
--   4. mentor RLS policies on entries (Work + not private only), workspaces
--      (read-only) and storage.objects (read only files attached to entries
--      the reader may see)
--   5. entries guard trigger   (status <-> done sync, transition rules,
--                               immutable user_id / created_by, mentor guardrails)
--   6. public.entry_comments   (per-task thread)
--   7. public.notifications    (written ONLY by triggers — the single event
--                               source a LINE webhook will hook onto later)
--   8. realtime for entry_comments + notifications
--
-- Contract (client maps camelCase <-> snake_case):
--   entries:        status, isPrivate -> is_private, blocked, blockedAt -> blocked_at,
--                   createdBy -> created_by (READ-ONLY: server-set; never send it)
--                   status in ('todo','in_progress','review','done','changes')
--                   done / done_at are kept in sync by the server from status
--                   (done = status = 'done'); old clients that only send done keep working.
--   entry_comments: id, entryId -> entry_id, ownerId -> owner_id (server-set),
--                   authorId -> author_id (server-set), body,
--                   createdAt -> created_at, updatedAt -> updated_at
--   notifications:  id, recipientId -> recipient_id, actorId -> actor_id,
--                   ownerId -> owner_id, type, entryId -> entry_id,
--                   commentId -> comment_id, payload, createdAt -> created_at,
--                   readAt -> read_at (the ONLY column a client may update)
--                   type in ('task_assigned','comment_added','status_changed','task_blocked','task_edited')
--                   payload: {title, date, due, status, actor_name (null if unset),
--                             from?/to? (status_changed), excerpt? (comment_added),
--                             fields? (task_edited: array of changed column names)}
--   mentorships:    internId -> intern_id, mentorId -> mentor_id,
--                   internName -> intern_name, mentorName -> mentor_name (all read-only for clients)
--   All *_at columns are bigint ms epoch, except mentorships.created_at (timestamptz).
--
-- Mentor rules (enforced here, not just in the UI):
--   * sees only entries with tab = 'work' and is_private = false of their intern
--   * may insert Work tasks for the intern (created_by = mentor, assigned_by = 'mentor')
--   * may update those visible tasks, but never user_id / tab / is_private /
--     created_by / assigned_by; may only ADD attachments stored under '<mentor uid>/'
--   * may delete only tasks the mentor created
-- Intern rules on mentor-assigned tasks (created_by <> user_id) — Rev 1:
--   * cannot change tab, cannot make private, cannot delete (only the creating mentor can)
--   * workspaces: read-only
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Table: public.mentorships  (one row per intern)
-- ---------------------------------------------------------------------
create table if not exists public.mentorships (
  intern_id  uuid        primary key                                -- PK => one mentor per intern
                         references auth.users(id) on delete cascade,
  mentor_id  uuid        not null unique                            -- UNIQUE => one intern per mentor (MVP)
                         references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint mentorships_not_self check (intern_id <> mentor_id)
);

-- Rev 1: display names (owner sets them in the SQL Editor; clients read-only). Trimmed by
-- the trigger below; '' becomes null. Client falls back to พี่เลี้ยง / น้องฝึกงาน.
alter table public.mentorships
  add column if not exists intern_name text null
        check (intern_name is null or char_length(intern_name) between 1 and 60),
  add column if not exists mentor_name text null
        check (mentor_name is null or char_length(mentor_name) between 1 and 60);

-- A user is either a mentor or an intern, never both (keeps role detection unambiguous).
-- Also trims the display names (runs before the length checks).
create or replace function public.mentorships_one_role()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.intern_name := nullif(btrim(new.intern_name), '');
  new.mentor_name := nullif(btrim(new.mentor_name), '');
  if exists (select 1 from public.mentorships m
             where (m.intern_id = new.mentor_id or m.mentor_id = new.intern_id)
               and m.intern_id <> new.intern_id) then
    raise exception 'A user cannot be both a mentor and an intern';
  end if;
  return new;
end
$$;
drop trigger if exists mentorships_one_role on public.mentorships;
create trigger mentorships_one_role
  before insert or update on public.mentorships
  for each row execute function public.mentorships_one_role();

-- Clients may only read their own link; rows are managed by the owner in the SQL Editor.
-- (Supabase's default privileges grant ALL on new public tables — narrow them explicitly.)
revoke all on public.mentorships from anon, authenticated;
grant select on public.mentorships to authenticated;
alter table public.mentorships enable row level security;

drop policy if exists "mentorships_select_own" on public.mentorships;
create policy "mentorships_select_own" on public.mentorships
  for select to authenticated
  using (intern_id = (select auth.uid()) or mentor_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 2. New columns on public.entries (additive; defaults keep old rows working)
-- ---------------------------------------------------------------------
alter table public.entries
  add column if not exists status     text    not null default 'todo'
        check (status in ('todo','in_progress','review','done','changes')),
  add column if not exists is_private boolean not null default false,       -- 🔒 hidden from mentor
  add column if not exists blocked    boolean not null default false,       -- "need help" flag
  add column if not exists blocked_at bigint  null,                         -- ms epoch, server-set
  add column if not exists created_by uuid    null default auth.uid()
        references auth.users(id) on delete set null;                       -- who created the row (server-set)

-- Backfill (no-ops on re-run). Runs before the guard trigger exists on the first run;
-- on a re-run auth.uid() is null in the SQL Editor so the trigger takes its admin path.
update public.entries set created_by = user_id where created_by is null;
update public.entries set status = 'done' where done and status <> 'done';

-- "board by status" / "tasks I created" / storage attachment lookup
create index if not exists entries_user_id_status_idx  on public.entries (user_id, status);
create index if not exists entries_attachments_gin_idx on public.entries using gin (attachments jsonb_path_ops);


-- ---------------------------------------------------------------------
-- 3. Helper functions (SECURITY DEFINER: read mentorships/entries without
--    going through RLS, so policies never recurse)
-- ---------------------------------------------------------------------

-- true when the signed-in user is the mentor of p_owner
create or replace function public.is_mentor_of(p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.mentorships m
    where m.intern_id = p_owner and m.mentor_id = auth.uid()
  );
$$;

-- true when the signed-in user may read/write the comment thread of a Work entry:
-- the owner (any of their Work entries) or the owner's mentor (Work + not private)
create or replace function public.can_access_entry(p_entry_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.entries e
    where e.id = p_entry_id
      and e.tab = 'work'
      and ( e.user_id = auth.uid()
         or (not e.is_private and exists (
               select 1 from public.mentorships m
               where m.intern_id = e.user_id and m.mentor_id = auth.uid()))) );
$$;

-- true when the signed-in user may read storage object p_name (bucket notebook-files)
-- because it is attached to an entry they can see. Object path is '<uploader uid>/<fileId>';
-- the uploader must be the entry owner or the owner's mentor. Matches attachments[].path,
-- or attachments[].id for legacy metadata without a path (always the owner's folder).
create or replace function public.can_read_notebook_file(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.entries e
    left join public.mentorships m on m.intern_id = e.user_id
    where (storage.foldername(p_name))[1] in (e.user_id::text, m.mentor_id::text)
      and ( e.attachments @> jsonb_build_array(jsonb_build_object('path', p_name))
         or ( (storage.foldername(p_name))[1] = e.user_id::text
              and e.attachments @> jsonb_build_array(jsonb_build_object('id', storage.filename(p_name)))
              -- legacy match only for metadata that really has NO path (QA fix: otherwise a mentor
              -- could add {id:'<intern file id>', path:'<mentor uid>/<same id>'} to a visible task,
              -- pass the trigger's path check, and unlock the intern's private file by id)
              and exists (
                select 1
                from jsonb_array_elements(case when jsonb_typeof(e.attachments) = 'array'
                                               then e.attachments else '[]'::jsonb end) a
                where a->>'id' = storage.filename(p_name) and a->>'path' is null) ) )
      and ( e.user_id = auth.uid()
         or (m.mentor_id = auth.uid() and e.tab = 'work' and not e.is_private) ) );
$$;

revoke all on function public.is_mentor_of(uuid)           from public, anon;
revoke all on function public.can_access_entry(text)       from public, anon;
revoke all on function public.can_read_notebook_file(text) from public, anon;
grant execute on function public.is_mentor_of(uuid)           to authenticated;
grant execute on function public.can_access_entry(text)       to authenticated;
grant execute on function public.can_read_notebook_file(text) to authenticated;


-- ---------------------------------------------------------------------
-- 4. Mentor RLS policies on entries (the "own" policies from setup.sql stay;
--    permissive policies are OR-ed)
-- ---------------------------------------------------------------------
drop policy if exists "entries_select_mentor" on public.entries;
create policy "entries_select_mentor" on public.entries
  for select to authenticated
  using (public.is_mentor_of(user_id) and tab = 'work' and not is_private);

drop policy if exists "entries_insert_mentor" on public.entries;
create policy "entries_insert_mentor" on public.entries
  for insert to authenticated
  with check (public.is_mentor_of(user_id) and tab = 'work' and not is_private);

-- WITH CHECK blocks moving a task to study/ideas or marking it private
drop policy if exists "entries_update_mentor" on public.entries;
create policy "entries_update_mentor" on public.entries
  for update to authenticated
  using      (public.is_mentor_of(user_id) and tab = 'work' and not is_private)
  with check (public.is_mentor_of(user_id) and tab = 'work' and not is_private);

-- mentor may delete only the tasks the mentor created
drop policy if exists "entries_delete_mentor" on public.entries;
create policy "entries_delete_mentor" on public.entries
  for delete to authenticated
  using (public.is_mentor_of(user_id) and created_by = (select auth.uid())
         and tab = 'work' and not is_private);

-- Rev 1: mentor-assigned tasks (created_by <> user_id) can be deleted ONLY by their creator.
-- RESTRICTIVE = AND-ed with every permissive DELETE policy, incl. setup.sql's
-- "entries_delete_own", so it survives a re-run of setup.sql. created_by null
-- (creator account deleted) counts as not mentor-assigned.
drop policy if exists "entries_delete_lock_assigned" on public.entries;
create policy "entries_delete_lock_assigned" on public.entries
  as restrictive for delete to authenticated
  using (created_by is null or created_by = user_id or created_by = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 5. entries guard trigger (BEFORE INSERT OR UPDATE)
--    - status <-> done/done_at sync (old clients that only toggle done keep working)
--    - transition rules for the intern (see docs: mentor-assigned tasks are approved by the mentor)
--    - user_id immutable; created_by server-set and immutable
--    - mentor guardrails that policies can't express (old vs new comparisons)
-- ---------------------------------------------------------------------
create or replace function public.entries_before_write()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor  uuid   := auth.uid();                                       -- null in SQL Editor / service role
  v_now    bigint := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_mentor uuid;
  v_att    jsonb  := case when jsonb_typeof(new.attachments) = 'array' then new.attachments else '[]'::jsonb end;
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, v_actor, new.user_id);
    -- Upsert (INSERT ... ON CONFLICT DO UPDATE) fires BEFORE INSERT for rows that end up
    -- as an UPDATE. Leave those untouched: the UPDATE pass below validates them.
    if exists (select 1 from public.entries x where x.id = new.id) then
      return new;
    end if;
    new.created_by := coalesce(v_actor, new.user_id);                  -- never trust the client
  else
    if new.user_id is distinct from old.user_id then
      raise exception 'An entry cannot change owner' using errcode = '42501';
    end if;
    new.created_by := coalesce(old.created_by, new.created_by);       -- immutable once set
  end if;

  -- Mentor guardrails (RLS already guarantees a non-owner actor is the owner's mentor)
  if v_actor is not null and v_actor <> new.user_id then
    if new.tab <> 'work' or (tg_op = 'UPDATE' and new.tab is distinct from old.tab) then
      raise exception 'Mentor can only work with Work tasks' using errcode = '42501';
    end if;
    if tg_op = 'INSERT' then
      new.is_private  := false;
      new.assigned_by := 'mentor';
    else
      if new.is_private is distinct from old.is_private then
        raise exception 'Only the intern can change task privacy' using errcode = '42501';
      end if;
      new.assigned_by := old.assigned_by;                             -- attribution is not editable by mentor
    end if;
    -- New attachments added by the mentor must be the mentor's own uploads: path must be
    -- exactly '<mentor uid>/<attachment id>' (so a known id of an intern file can't be
    -- smuggled in to unlock it via can_read_notebook_file's legacy id match)
    if exists (
      select 1 from jsonb_array_elements(v_att) a
      where (tg_op = 'INSERT' or not (old.attachments @> jsonb_build_array(a)))
        and coalesce(a->>'path', '') <> v_actor::text || '/' || coalesce(a->>'id', '')
    ) then
      raise exception 'Mentor attachments must be uploaded by the mentor' using errcode = '42501';
    end if;
  end if;

  -- Rev 1: intern lock on mentor-assigned tasks (created_by <> user_id): no tab change,
  -- no making it private (un-private stays allowed). Delete is locked by policy.
  if tg_op = 'UPDATE' and v_actor = new.user_id
     and coalesce(old.created_by <> old.user_id, false) then
    if new.tab is distinct from old.tab then
      raise exception 'This task is from your mentor — it stays in Work' using errcode = '42501';
    end if;
    if new.is_private and not old.is_private then
      raise exception 'This task is from your mentor — it cannot be made private' using errcode = '42501';
    end if;
  end if;

  -- Study / Ideas: no workflow
  if new.tab <> 'work' then
    new.status := 'todo'; new.done := false; new.done_at := null;
    new.blocked := false; new.blocked_at := null;
    return new;
  end if;

  -- Legacy clients send only `done`: derive status from it
  if tg_op = 'INSERT' then
    if new.done and new.status = 'todo' then new.status := 'done'; end if;
  elsif new.status is not distinct from old.status and new.done is distinct from old.done then
    new.status := case when new.done then 'done' else 'todo' end;
  end if;

  -- Transition rules for the intern (only when a mentorship exists)
  if tg_op = 'UPDATE' and v_actor = new.user_id and new.status is distinct from old.status then
    select m.mentor_id into v_mentor from public.mentorships m where m.intern_id = new.user_id;
    if v_mentor is not null then
      if new.status = 'changes' then
        raise exception 'Only your mentor can send a task back for changes' using errcode = '42501';
      end if;
      if coalesce(old.created_by <> old.user_id, false) then           -- mentor-assigned task
        if old.status = 'done' then
          raise exception 'Your mentor approved this task — ask them to reopen it' using errcode = '42501';
        end if;
        if new.status = 'done' then new.status := 'review'; end if;    -- intern "done" = send for review
      end if;
    end if;
  end if;

  -- done / done_at always follow status
  new.done    := new.status = 'done';
  new.done_at := case when new.done then coalesce(new.done_at, v_now) else null end;

  -- blocked_at is server-set
  if not new.blocked then
    new.blocked_at := null;
  elsif tg_op = 'INSERT' or not old.blocked then
    new.blocked_at := v_now;
  else
    new.blocked_at := coalesce(old.blocked_at, v_now);
  end if;

  return new;
end
$$;
revoke all on function public.entries_before_write() from public, anon, authenticated;

drop trigger if exists entries_before_write on public.entries;
create trigger entries_before_write
  before insert or update on public.entries
  for each row execute function public.entries_before_write();


-- ---------------------------------------------------------------------
-- 6. Workspaces: mentor read-only (so workspace tags render on tasks)
-- ---------------------------------------------------------------------
drop policy if exists "workspaces_select_mentor" on public.workspaces;
create policy "workspaces_select_mentor" on public.workspaces
  for select to authenticated
  using (public.is_mentor_of(user_id));


-- ---------------------------------------------------------------------
-- 7. Table: public.entry_comments  (progress updates / replies per Work task)
-- ---------------------------------------------------------------------
create table if not exists public.entry_comments (
  id         text   primary key default gen_random_uuid()::text,     -- client may send its own UUID
  entry_id   text   not null references public.entries(id) on delete cascade,
  owner_id   uuid   not null references auth.users(id) on delete cascade,  -- = entries.user_id (server-set)
  author_id  uuid   not null default auth.uid()
                    references auth.users(id) on delete cascade,     -- server-set
  body       text   not null check (length(trim(body)) > 0),
  created_at bigint not null default ((extract(epoch from now()) * 1000)::bigint),
  updated_at bigint not null default ((extract(epoch from now()) * 1000)::bigint)
);

-- Main read paths: "thread of task X", "all threads of intern Y" (realtime filter)
create index if not exists entry_comments_entry_id_created_at_idx on public.entry_comments (entry_id, created_at);
create index if not exists entry_comments_owner_id_idx            on public.entry_comments (owner_id);

create or replace function public.entry_comments_before_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_owner uuid;
begin
  select e.user_id into v_owner from public.entries e where e.id = new.entry_id;
  if v_owner is null then
    raise exception 'Task not found' using errcode = '23503';
  end if;
  new.owner_id  := v_owner;
  new.author_id := coalesce(auth.uid(), new.author_id);
  return new;
end
$$;
revoke all on function public.entry_comments_before_insert() from public, anon, authenticated;

drop trigger if exists entry_comments_before_insert on public.entry_comments;
create trigger entry_comments_before_insert
  before insert on public.entry_comments
  for each row execute function public.entry_comments_before_insert();

-- Column-level: a comment's author may edit only the text
revoke all on public.entry_comments from anon, authenticated;
grant select, insert, delete on public.entry_comments to authenticated;
grant update (body, updated_at) on public.entry_comments to authenticated;

alter table public.entry_comments enable row level security;

drop policy if exists "entry_comments_select" on public.entry_comments;
create policy "entry_comments_select" on public.entry_comments
  for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_access_entry(entry_id));

drop policy if exists "entry_comments_insert" on public.entry_comments;
create policy "entry_comments_insert" on public.entry_comments
  for insert to authenticated
  with check (author_id = (select auth.uid()) and public.can_access_entry(entry_id));

drop policy if exists "entry_comments_update_author" on public.entry_comments;
create policy "entry_comments_update_author" on public.entry_comments
  for update to authenticated
  using      (author_id = (select auth.uid()) and public.can_access_entry(entry_id))
  with check (author_id = (select auth.uid()) and public.can_access_entry(entry_id));

drop policy if exists "entry_comments_delete_author" on public.entry_comments;
create policy "entry_comments_delete_author" on public.entry_comments
  for delete to authenticated
  using (author_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 8. Table: public.notifications  (inserted ONLY by triggers below)
--    Later: a Supabase Database Webhook / Edge Function on INSERT pushes
--    the same rows to a LINE group via the Messaging API.
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id           uuid   primary key default gen_random_uuid(),
  recipient_id uuid   not null references auth.users(id) on delete cascade,
  actor_id     uuid   null     references auth.users(id) on delete set null,
  owner_id     uuid   not null references auth.users(id) on delete cascade,     -- the intern (notebook owner)
  type         text   not null check (type in ('task_assigned','comment_added','status_changed','task_blocked','task_edited')),
  entry_id     text   null references public.entries(id) on delete cascade,
  comment_id   text   null references public.entry_comments(id) on delete set null,
  payload      jsonb  not null default '{}'::jsonb,                             -- {title, date, due, from, to, excerpt}
  created_at   bigint not null default ((extract(epoch from now()) * 1000)::bigint),
  read_at      bigint null                                                      -- ms epoch; null = unread
);

-- Rev 1: (re)define the type list so a table created by the first version gains 'task_edited'
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in ('task_assigned','comment_added','status_changed','task_blocked','task_edited'));

-- Main read path: "my notifications, newest first" + unread badge
create index if not exists notifications_recipient_created_idx on public.notifications (recipient_id, created_at desc);
create index if not exists notifications_recipient_unread_idx  on public.notifications (recipient_id) where read_at is null;

-- No INSERT grant: clients can't fabricate events. Recipient may mark read / delete.
revoke all on public.notifications from anon, authenticated;
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select to authenticated
  using (recipient_id = (select auth.uid()));

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update to authenticated
  using      (recipient_id = (select auth.uid()))
  with check (recipient_id = (select auth.uid()));

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications
  for delete to authenticated
  using (recipient_id = (select auth.uid()));


-- ---------------------------------------------------------------------
-- 9. Notification triggers (SECURITY DEFINER; skip when there is no
--    signed-in actor, e.g. SQL Editor edits)
--    Recipient = "the other party": mentor -> intern always;
--    intern -> mentor only while the task is Work and not private.
-- ---------------------------------------------------------------------
create or replace function public.entries_after_write_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_actor       uuid := auth.uid();
  v_mentor      uuid;
  v_mentor_name text;
  v_intern_name text;
  v_recipient   uuid;
  v_payload     jsonb;
  v_fields      text[];
begin
  if v_actor is null or new.tab <> 'work' then return null; end if;
  select m.mentor_id, m.mentor_name, m.intern_name into v_mentor, v_mentor_name, v_intern_name
  from public.mentorships m where m.intern_id = new.user_id;
  if v_mentor is null then return null; end if;

  v_recipient := case
    when v_actor = new.user_id then (case when not new.is_private then v_mentor end)
    else new.user_id end;
  if v_recipient is null or v_recipient = v_actor then return null; end if;

  v_payload := jsonb_build_object(
    'title', left(coalesce(nullif(new.title, ''), split_part(new.body, E'\n', 1)), 140),
    'date', new.date, 'due', new.due, 'status', new.status,
    'actor_name', case when v_actor = v_mentor then v_mentor_name
                       when v_actor = new.user_id then v_intern_name end);  -- null when not set

  if tg_op = 'INSERT' then
    if v_actor = v_mentor then
      insert into public.notifications (recipient_id, actor_id, owner_id, type, entry_id, payload)
      values (v_recipient, v_actor, new.user_id, 'task_assigned', new.id, v_payload);
    end if;
    return null;
  end if;

  if new.status is distinct from old.status then
    insert into public.notifications (recipient_id, actor_id, owner_id, type, entry_id, payload)
    values (v_recipient, v_actor, new.user_id, 'status_changed', new.id,
            v_payload || jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  if new.blocked and not old.blocked then
    insert into public.notifications (recipient_id, actor_id, owner_id, type, entry_id, payload)
    values (v_recipient, v_actor, new.user_id, 'task_blocked', new.id, v_payload);
  end if;
  -- Rev 1: mentor edited content of an existing task -> tell the intern which fields changed
  if v_actor = v_mentor then
    v_fields := array_remove(array[
      case when new.title         is distinct from old.title         then 'title'         end,
      case when new.body          is distinct from old.body          then 'body'          end,
      case when new.due           is distinct from old.due           then 'due'           end,
      case when new.priority      is distinct from old.priority      then 'priority'      end,
      case when new.checklist     is distinct from old.checklist     then 'checklist'     end,
      case when new.attachments   is distinct from old.attachments   then 'attachments'   end,
      case when new.workspace_ids is distinct from old.workspace_ids then 'workspace_ids' end
    ]::text[], null);
    if cardinality(v_fields) > 0 then
      insert into public.notifications (recipient_id, actor_id, owner_id, type, entry_id, payload)
      values (v_recipient, v_actor, new.user_id, 'task_edited', new.id,
              v_payload || jsonb_build_object('fields', to_jsonb(v_fields)));
    end if;
  end if;
  return null;
end
$$;
revoke all on function public.entries_after_write_notify() from public, anon, authenticated;

drop trigger if exists entries_after_insert_notify on public.entries;
create trigger entries_after_insert_notify
  after insert on public.entries
  for each row execute function public.entries_after_write_notify();

drop trigger if exists entries_after_update_notify on public.entries;
create trigger entries_after_update_notify
  after update on public.entries
  for each row
  when (old.status is distinct from new.status or (new.blocked and not old.blocked)
        or old.title is distinct from new.title or old.body is distinct from new.body
        or old.due is distinct from new.due or old.priority is distinct from new.priority
        or old.checklist is distinct from new.checklist or old.attachments is distinct from new.attachments
        or old.workspace_ids is distinct from new.workspace_ids)
  execute function public.entries_after_write_notify();

create or replace function public.entry_comments_after_insert_notify()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_entry       public.entries%rowtype;
  v_mentor      uuid;
  v_mentor_name text;
  v_intern_name text;
  v_recipient   uuid;
begin
  if auth.uid() is null then return null; end if;
  select * into v_entry from public.entries e where e.id = new.entry_id;
  select m.mentor_id, m.mentor_name, m.intern_name into v_mentor, v_mentor_name, v_intern_name
  from public.mentorships m where m.intern_id = new.owner_id;
  if v_mentor is null then return null; end if;

  v_recipient := case
    when new.author_id = new.owner_id then (case when not v_entry.is_private and v_entry.tab = 'work' then v_mentor end)
    else new.owner_id end;
  if v_recipient is null or v_recipient = new.author_id then return null; end if;

  insert into public.notifications (recipient_id, actor_id, owner_id, type, entry_id, comment_id, payload)
  values (v_recipient, new.author_id, new.owner_id, 'comment_added', new.entry_id, new.id,
          jsonb_build_object(
            'title', left(coalesce(nullif(v_entry.title, ''), split_part(v_entry.body, E'\n', 1)), 140),
            'date', v_entry.date, 'due', v_entry.due, 'status', v_entry.status,
            'excerpt', left(new.body, 200),
            'actor_name', case when new.author_id = v_mentor then v_mentor_name
                               when new.author_id = new.owner_id then v_intern_name end));
  return null;
end
$$;
revoke all on function public.entry_comments_after_insert_notify() from public, anon, authenticated;

drop trigger if exists entry_comments_after_insert_notify on public.entry_comments;
create trigger entry_comments_after_insert_notify
  after insert on public.entry_comments
  for each row execute function public.entry_comments_after_insert_notify();


-- ---------------------------------------------------------------------
-- 10. Storage: read files attached to entries the reader may see
--     (own-folder policies from setup.sql stay; the mentor uploads into
--      '<mentor uid>/' through them and can never write the intern's folder)
-- ---------------------------------------------------------------------
drop policy if exists "notebook_files_select_shared" on storage.objects;
create policy "notebook_files_select_shared" on storage.objects
  for select to authenticated
  using (bucket_id = 'notebook-files' and public.can_read_notebook_file(name));


-- ---------------------------------------------------------------------
-- 11. Realtime: stream comments + notifications
-- ---------------------------------------------------------------------
alter table public.entry_comments replica identity full;
alter table public.notifications  replica identity full;

do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['entry_comments', 'notifications'] loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
      ) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end
$$;


-- ---------------------------------------------------------------------
-- 12. OWNER STEP (manual, once): link the mentor
--     a) Authentication -> Users -> Add user (mentor's email, tick Auto Confirm User)
--     b) copy both UIDs from the Users list, then un-comment and run ONLY this:
-- ---------------------------------------------------------------------
--     Names are optional display names (≤ 60 chars, trimmed; null -> UI shows พี่เลี้ยง / น้องฝึกงาน).
-- insert into public.mentorships (intern_id, mentor_id, intern_name, mentor_name)
-- values ('<INTERN_UID>', '<MENTOR_UID>', '<intern display name>', '<mentor display name>')
-- on conflict (intern_id) do update set mentor_id   = excluded.mentor_id,
--                                       intern_name = excluded.intern_name,
--                                       mentor_name = excluded.mentor_name;
--
-- Or by email:
-- insert into public.mentorships (intern_id, mentor_id, intern_name, mentor_name)
-- select i.id, m.id, '<intern display name>', '<mentor display name>'
-- from auth.users i, auth.users m
-- where i.email = '<intern email>' and m.email = '<mentor email>'
-- on conflict (intern_id) do update set mentor_id   = excluded.mentor_id,
--                                       intern_name = excluded.intern_name,
--                                       mentor_name = excluded.mentor_name;
--
-- Rename later: update public.mentorships set mentor_name = '<name>' where intern_id = '<INTERN_UID>';

-- Done. Verify: Table Editor -> mentorships (with intern_name / mentor_name) / entry_comments /
--               notifications (RLS on); entries has 8 permissive policies + 1 restrictive delete lock;
--               entries has status / is_private / blocked / blocked_at / created_by;
--               Database -> Triggers: entries_before_write, entries_after_*_notify,
--               entry_comments_*; Storage -> notebook-files has 5 policies.
