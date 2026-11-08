# Mentor (พี่เลี้ยง) account — Architecture Package

_ArchitectTam · 2026-11-08 · migration: `supabase/003_mentor.sql` (DataTam)_

## 1. Summary

The app stays a single `index.html` on Supabase. The mentor is a second Supabase Auth user, linked to the intern by one row in `public.mentorships`. **All authorization lives in Postgres:** RLS, `SECURITY DEFINER` helpers, and one guard trigger. The client only hides UI. Notifications are written **only by DB triggers** into `public.notifications`. That table is the single event source: the app's realtime feed reads it today, and a LINE Messaging API webhook will read the same rows later.

No new services, no Edge Functions, no build step for the MVP.

## 2. Data ownership

| Data | Owner (`user_id` / `owner_id`) | Who writes |
|---|---|---|
| `mentorships` (intern_id PK, mentor_id UNIQUE) | owner, via the SQL Editor | nobody from the client (SELECT only) |
| `entries` | **always the intern**, even for tasks the mentor creates | intern; mentor (Work only, see the matrix in §3) |
| `entries.created_by` | server-set = `auth.uid()` on insert, immutable | trigger |
| `workspaces` | intern | intern only |
| `entry_comments` | `owner_id` = the entry's intern (server-set), `author_id` = writer (server-set) | intern + mentor |
| `notifications` | `recipient_id` | **triggers only** |
| Storage `notebook-files/<uploader uid>/<fileId>` | uploader | each user only writes their own folder |

- **One mentor per intern** is enforced by `intern_id` being the PK. **One intern per mentor** is enforced by `UNIQUE(mentor_id)` (MVP; drop the constraint if a mentor ever gets several interns). A trigger stops one user from being both a mentor and an intern.
- **Helpers** (all `SECURITY DEFINER` with `search_path=''`, so they read without RLS and can't cause policy recursion):
  - `is_mentor_of(owner uuid)`
  - `can_access_entry(entry_id text)` — the owner on Work, or the mentor on Work + not private
  - `can_read_notebook_file(name text)`

## 3. Authorization matrix

S = select, I = insert, U = update, D = delete. "Visible" means `tab='work' AND is_private=false`.

| Resource | Intern | Mentor |
|---|---|---|
| `entries` | S/I/U/D own rows, **except on mentor-assigned rows (`created_by <> user_id`): no D, no tab change, no `is_private → true`** (Rev 1: trigger + restrictive delete policy) | **S** visible rows of their intern · **I** visible rows with `user_id = intern` · **U** visible rows (WITH CHECK keeps them visible) · **D** only rows with `created_by = mentor` |
| `workspaces` | S/I/U/D own | **S only** (so workspace tags and the sidebar render) |
| `entry_comments` | S all comments on own entries · I on own Work entries · U(body) / D own comments | S/I on visible entries · U(body) / D own comments |
| `notifications` | S / U(`read_at` only) / D where `recipient_id = me` · **no I** | same |
| `mentorships` (incl. `intern_name`, `mentor_name`) | S own row (no U) | S own row (no U) |
| storage `notebook-files` | everything in `<me>/` (unchanged) + **S** files attached to own entries (this includes files the mentor uploaded) | everything in `<mentor>/` (used for the mentor's uploads) + **S** files attached to visible entries |

**File access design:** the upload path is `<uploader uid>/<fileId>` and does **not** contain the entry id. So read access isn't based on the path. A file is readable only if `can_read_notebook_file(name)` finds an entry the reader can see, under these conditions:

- The entry's `attachments` contains `{path: name}`, or `{id: filename}` for legacy metadata without a path, which must be in the owner's folder.
- The folder is either the entry owner's or the owner's mentor's.

The effect: an attachment on a private, Study or Ideas entry never resolves for the mentor. If the intern makes a task private, the mentor loses access to its files immediately, and signed URLs already issued expire within 1 h.

## 4. Guardrails — trigger `entries_before_write` (BEFORE INSERT OR UPDATE)

- `user_id` is immutable for everyone, and an attempt raises `42501`. `created_by` is set by the server on insert and is immutable after that, so the client can't forge or rewrite it.
- When the mentor is the actor:
  - The tab must be `work`, and the tab can't change.
  - `is_private` can't change. On insert it is forced to `false`.
  - `assigned_by` is forced to `'mentor'` on insert and kept at its old value on update.
  - Every **newly added** attachment must have `path = '<mentor uid>/<id>'`. This stops the mentor from pointing an attachment at one of the intern's files to unlock it.
- **Upsert-safe:** PostgREST upsert also fires BEFORE INSERT for rows that will conflict. The trigger detects an existing id and defers all checks to the UPDATE pass.
- Study/Ideas rows are forced to `status='todo'`, `done=false`, `blocked=false`.
- `done` / `done_at` are always derived from `status`. A legacy client that only toggles `done` still works: `done=true` becomes `status='done'` (or `review`, see §5), and `done=false` becomes `todo`.
- `blocked_at` is set by the server when `blocked` turns true, and cleared when it turns false.

## 5. Status workflow

Statuses: `todo → in_progress → review (รอพี่ตรวจ) → done | changes (ให้แก้) → in_progress → …`

- **Mentor:** may set any status on visible tasks. `done` means approve and `changes` means send back. The client posts the comment first, then sets the status.
- **Intern:** may set `todo`, `in_progress`, `review` and `done`, with these limits:
  - `ASSUMPTION:` the intern may **never** set `changes`. That is the mentor's verb.
  - `ASSUMPTION:` on a **mentor-assigned** task (`created_by ≠ user_id`), the intern's "done" is **coerced to `review`** instead of raising an error, so the old checkbox still behaves sensibly. Once the mentor has approved it (`done`), the intern can't reopen it; the server raises "ask them to reopen".
  - `ASSUMPTION:` on a **self-created** task, the intern may set `done` directly, or optionally send it to `review`.
- These rules apply only while a mentorship row exists. With no mentor, the app behaves as it does today.
- **Rev 1 (owner decision, replaces the old assumption): mentor-assigned tasks are locked for the intern.** On rows where `created_by <> user_id` the intern can't change `tab`, can't set `is_private = true` (un-private stays allowed), and can't delete. Only the creating mentor can delete them; this is enforced by the restrictive policy `entries_delete_lock_assigned`, which survives a re-run of setup.sql. `created_by` null (creator account deleted) counts as not mentor-assigned.

The client should mirror these rules in one pure function, `canSetStatus(role, entry, to)`, so it can disable buttons and run them in demo mode. The server stays the authority. When the server coerces a value, the client's optimistic row is corrected by the realtime echo (same `updated_at` is applied).

## 6. Realtime

| Client | Channel / filter |
|---|---|
| intern | `entries` with `user_id=eq.<me>` (unchanged) · `workspaces` (unchanged) · `entry_comments` with `owner_id=eq.<me>` · `notifications` with `recipient_id=eq.<me>` |
| mentor | `entries` with `user_id=eq.<internId>` · `workspaces` with `user_id=eq.<internId>` · `entry_comments` with `owner_id=eq.<internId>` · `notifications` with `recipient_id=eq.<me>` |

RLS still filters each event per subscriber.

**Known gap:** when the intern turns a task private (or moves it out of Work), the mentor gets **no** UPDATE event, because the row is no longer visible to them. The mentor client therefore refetches entries (and comments) on `visibilitychange`/focus and on reconnect. The stale card disappears then. DELETE events carry only ids; ignore unknown ids, as the client does today.

## 7. Client role detection and mentor UI

After sign-in, before `createSupabaseStore`, run `sb.from('mentorships').select('intern_id,mentor_id,intern_name,mentor_name').maybeSingle()`:

- If `mentor_id === me`, then `role='mentor'` and `ownerId = intern_id`.
- Otherwise `role='intern'` and `ownerId = me`. `hasMentor` = a row exists.
- If the query errors with `isSchemaMissing` (003 not run yet), treat the user as `role='intern'` with no mentor features, which is today's app.

Pass `{ role, ownerId, internName, mentorName }` into the store and into `AppCtx`. Names may be null; fall back to the labels พี่เลี้ยง / น้องฝึกงาน.

Intern UI on mentor-assigned tasks (`createdBy !== ownerId`, ignoring a null `createdBy`): hide delete, the 🔒 toggle (unless the task is already private) and the tab move.

**Mentor UI** has a Work-only calendar/daily panel, the Pending list, the mentor board and notifications. **It hides:**

- the Study and Ideas tabs
- the 🔒 privacy toggle
- export/import backup and sample data (section 13 menu)
- workspace create/edit/archive (sidebar is read-only)
- delete on intern-created tasks
- the "Assigned by" picker (server-set)

The Building view can stay.

## 8. Notifications (ready for LINE)

| type | Fired by | Recipient |
|---|---|---|
| `task_assigned` | AFTER INSERT on `entries` when the actor is the mentor | intern |
| `status_changed` | AFTER UPDATE when `status` changes | the other party |
| `task_blocked` | AFTER UPDATE when `blocked` changes false→true | the other party |
| `comment_added` | AFTER INSERT on `entry_comments` | the other party |
| `task_edited` (Rev 1) | AFTER UPDATE when the **mentor** changes any of `title, body, due, priority, checklist, attachments, workspace_ids`. Not sent when only status/blocked changed. | intern |

- "The other party" is always the intern when the mentor acts, and the mentor only when the task is Work and not private.
- Nothing fires without a signed-in actor (SQL Editor edits) or without a mentorship.
- `payload` is self-contained, so a webhook needs no extra reads: `{title, date, due, status, actor_name, from?, to?, excerpt?, fields?}`.
  - `actor_name` comes from `mentorships.mentor_name` / `intern_name`, and is `null` when unset (the client falls back to the label).
  - `fields` appears only on `task_edited`: a JSON array of the changed column names (snake_case, e.g. `["due","checklist"]`).
  - One mentor save can produce both `status_changed` and `task_edited`.

**LINE next step (not now):** add a Supabase Database Webhook (or `pg_net`) on `INSERT public.notifications` that calls an Edge Function or n8n. That service formats the payload and calls the LINE Messaging API push endpoint with a channel access token and group id, both kept as Edge Function secrets and never in the client. The webhook step adds a `line_sent_at` column in migration 004 for retries and idempotency. LINE Notify is discontinued, so don't use it.

## 9. Demo / IndexedDB mode

- `normalizeEntry` carries `status`, `isPrivate`, `blocked` and `blockedAt`, so demo entries get the workflow. The demo applies the same `canSetStatus` and done-sync logic client-side, with no server.
- Comments go in a new IDB store `comments`. Bump `indexedDB.open(…, 3)` and **add an `onblocked` handler**, which also fixes known issue #1.
- There are no notifications in demo mode, because they come from server triggers. Hide the bell.
- **Mentor preview (demo only):** a URL flag `?as=mentor`, ignored when `CLOUD_ENABLED`. It renders the mentor UI over the local data (Work + not private, mentor-only controls), so Noey/Meejai can check the layout without a second account. It tests **UI only**. RLS is verified separately (§11).

## 10. Client changes required (for DevBAmooTam) — by `index.html` section

- **§2 Constants:**
  - `STATUSES = ['todo','in_progress','review','done','changes']` with TH labels
  - `canSetStatus(role, entry, to)`
  - a schema message for 003
- **§3 `normalizeEntry`:** add `status` (default from `done`), `isPrivate`, `blocked`, `blockedAt`, `createdBy` (read-only). Set `done = status==='done'`. For non-work tabs use `status:'todo'`.
- **§4a Local store:**
  - IDB v3 `comments` store plus `onblocked`
  - `subscribeComments` / `saveComment` / `removeComment`
  - no-op `subscribeNotifications`
- **§4c Supabase store** — `createSupabaseStore(client, user, { role, ownerId })`:
  - `toRow.user_id = ownerId` (not `user.id`). Send `status`, `is_private`, `blocked`. **Never send** `created_by` or `blocked_at`. The mentor sends `assigned_by:'mentor'` only on create and existing values unchanged on edit.
  - `fromRow` maps the new columns.
  - Add `status`, `is_private` and `blocked` to `NEW_ENTRY_COLS`, so the legacy fallback still works before 003 runs. Keep the 002 columns separate, or detect per column.
  - Realtime filters use `ownerId` (§6). The mentor refetches on focus.
  - The initial `select("*")` page loads for `entries` and `workspaces` (index.html ~L1045, ~L1088) must add `.eq('user_id', ownerId)`. RLS alone would also return the mentor's own rows, if the mentor account ever writes any. _(QA fix)_
  - `fileName(meta) = meta.path || \`${ownerId}/${meta.id}\``.
  - `removeFile`: skip, or ignore errors for, objects outside your own folder. Mentor-removed intern files stay orphaned; that's acceptable.
  - The mentor must keep existing attachment objects **byte-identical**: don't add keys such as `url` to stored metas. Otherwise the trigger reads them as new and rejects them.
  - New: `subscribeComments(cb)`, `saveComment({id, entryId, body})`, `removeComment(id)`, `subscribeNotifications(cb)`, `markRead(ids)` (PATCH `read_at`), `clearNotifications`.
  - Rev 1: there are 5 notification types (`task_assigned`, `comment_added`, `status_changed`, `task_blocked`, `task_edited`). Render `payload.actor_name ?? role label` and `payload.fields` for `task_edited`. The trigger raises `42501` if the intern deletes, re-tabs or privatizes a mentor-assigned task; show it as a toast and roll back the optimistic change. `mentorships` names are read-only, so never write them.
  - `saveComment`: a new comment is `.insert({id, entry_id, body})`, and an edit is `.update({body, updated_at}).eq('id', id)`. **Never `.upsert()` comments**, because authenticated only has column-level UPDATE on `body` / `updated_at`, so an upsert that SETs `entry_id` is denied. Don't send `owner_id` or `author_id`. _(QA fix)_
- **§7 Editor:**
  - status select limited by `canSetStatus`
  - 🔒 toggle (intern only)
  - Blocked toggle
  - "Assigned by" shows พี่เลี้ยง automatically when `createdBy ≠ ownerId`
- **§8 Card / §9 Daily panel / §11 Pending:**
  - a status pill replaces the plain check (the check maps to the next allowed status)
  - red Blocked badge
  - 🔒 badge
  - comment thread on the card (list + composer)
- **§12b Workspaces:** read-only mode for the mentor.
- **§13 Menu:** hide export/import and sample data for the mentor. Add a notifications bell with unread count.
- **§15 Notebook:**
  - `actions.toggleDone` → `actions.setStatus`
  - a new **Mentor board** view: columns by status, plus Overdue (`due < today` and not done), Waiting review and Blocked
  - hide the Study/Ideas tabs for the mentor
  - `?as=mentor` demo preview
- **§17 App root:** detect the role (§7) before building the store, and key the store on `userKey + role`.

## 11. Owner manual steps

1. Run `supabase/003_mentor.sql` in the SQL Editor. It is safe to re-run.
2. In Authentication → Users → Add user, enter the mentor's email, set a password and tick **Auto Confirm User**.
3. Copy the intern UID and the mentor UID from the Users list. Un-comment and run the `insert into public.mentorships (intern_id, mentor_id, intern_name, mentor_name) …` statement at the bottom of 003. The by-email variant also works. The names are optional (≤ 60 chars, trimmed); rename later with the `update` line given there. **Needed from the owner: the mentor's email and both display names.**
4. Verify RLS before handing over the password. Log in as the mentor in a private window and check:
   - Study/Ideas and 🔒 tasks are absent.
   - Opening a private task's file URL fails.
   - Creating a task shows up for the intern with a notification.
5. Give the mentor the URL and password, and ask them to change the password through the reset flow.

## 12. Gate verdict — **READY (conditional)**

API boundaries are explicit: PostgREST tables only, with no new endpoints. Data ownership, authentication (unchanged invite-only email/password) and authorization (RLS + trigger) are all defined. Build may start once Meejai has QA'd this package.

Conditions:

- **003 has not been executed anywhere.** There is no local Postgres here. The owner runs it on the live project, and any SQL error goes back to DataTam before the client is merged.
- Run the §11 step 4 check before the mentor gets access.

**Open questions (none block the build):**

1. Should the mentor see **all** workspaces, including position-card notes and channels? `ASSUMPTION: yes, work context`. If not, restrict reads to workspaces referenced by visible entries.
2. Should comments be included in the JSON backup? `ASSUMPTION: not in MVP`.
3. ~~Notify on mentor edits?~~ Resolved in Rev 1: `task_edited`.
4. ~~Display names?~~ Resolved in Rev 1: `mentorships.intern_name` / `mentor_name`.
5. Firebase mode doesn't support the mentor features (Supabase only).

## 13. QA log — Meejai · 2026-11-08

**Verdict: PASS WITH FIXES.** This was a static review only. 003 still has not been executed, so the §12 conditions stand.

### Fixes applied

| # | File | Fix |
|---|---|---|
| F1 | `supabase/003_mentor.sql` · `can_read_notebook_file` | **RLS hole closed.** The legacy `{id}` match also matched elements that have a path. A mentor who knew an intern file id `F` could add `{id:'F', path:'<mentor uid>/F'}` to a visible task. That element passes the trigger's path check and still `@>`-contains `{id:'F'}`, so the mentor could read `<intern>/F` even when it was attached to a private, Study or Ideas entry. The legacy branch now also requires an element whose `id` = filename **and** whose `path` is null. A mentor can never add a path-less element, because the trigger rejects it. |
| F2 | this doc §10 | Added a rule: the initial `entries` and `workspaces` fetch filters `user_id = ownerId`. |
| F3 | this doc §10 | Added a rule: comments are created with insert and edited with update, never upsert (column-level grant). |
| F4 | `docs/planb-theme.md` R3 | The disclaimer cross-reference pointed to §3.5; corrected it to §4.5. |

### Checked and OK

- Every DDL statement is guarded (`if not exists`, `drop … if exists`, `create or replace`, guarded publication add).
- Objects are created before they are referenced (`sql` function bodies only reference existing tables).
- Every `SECURITY DEFINER` function sets `search_path=''` and uses qualified names.
- No policy recursion: the mentorships policy uses only `auth.uid()`, and the helpers bypass RLS as owner.
- The backfill runs before the trigger exists. On a re-run there's no actor, so it takes the admin path.
- Upsert handling (BEFORE INSERT defers, BEFORE UPDATE validates) is safe.
- Clients have no INSERT on notifications or mentorships.
- `author_id` and `owner_id` are forced server-side, so an intern can't forge a comment author.
- Mentors can't delete intern-created rows. Backfilled rows get `created_by = user_id`.
- The current live client is unaffected:
  - It already forces `done=false` on Study/Ideas (`normalizeEntry`), matching the trigger.
  - Coerced values return through the realtime echo with the same `updated_at`, so they are applied.
  - With no mentorship row the transition rules are skipped.
- Doc matches code:
  - The upload path is `${user.id}/${meta.id}`, and `path` is stored in the meta.
  - `NEW_ENTRY_COLS` / `legacyEntries` fallback is at ~L986.
  - The realtime publication and `user_id=eq.` filters match.
  - `indexedDB.open(…, 2)` is at L789.
  - The signed URL TTL is 3600.

### Residual risks (not fixed; design-level, non-blocking)

- R1: if the mentor ever stores files in their **own** notebook, the intern could read one by attaching `{path:'<mentor uid>/<id>'}` to their own entry. That requires knowing the random id. MVP: the mentor account has no notebook of its own.
- R2: notification `payload.title` stays readable by the mentor after the intern later makes that task private.
- R3: the `/rpc/is_mentor_of`, `/rpc/can_access_entry` and `/rpc/can_read_notebook_file` functions are exposed via PostgREST and act as boolean oracles. They reveal existence only, behind random ids.
- R4: Noey §5.5 "system lines" (a status change shown inside the thread) has no shared data source. Notifications are per-recipient and the actor never holds one. Either drop them for MVP or add an event table in 004.

### Cross-spec reconciliation (this doc wins on data and authorization; Noey wins on presentation)

- **Private flag:** Noey's `private` is `isPrivate` / `is_private`.
- **Mentor-assigned flag:** Noey's `assigned_by_mentor` is **derived**, as `createdBy !== ownerId`. Don't use the `assignedBy` text. Legacy rows the intern tagged `assignedBy:'mentor'` keep the old AssignedBadge but get no "จากพี่เลี้ยง" pill and no approval rule.
- **Private threads:** the DB allows owner-only comments on private Work tasks. The UI follows Noey: hide the composer and show the private notice, but still render any existing thread read-only for the intern.
- **Role:** one account is never both roles (trigger), so `.role-chip` is never a toggle.
- **Names:** superseded by Rev 1. Use `mentorships.intern_name` / `mentor_name`, and fall back to the role labels พี่เลี้ยง / น้องฝึกงาน when null.
- **Notification copy:** "ขอให้ตรวจ" = `status_changed` with `payload.to === 'review'`. The other four copies map 1:1 to the four types.
- **Mentor board:** use Noey's 5 status columns. Overdue and Blocked are card treatments plus the filter toggle, not extra columns. "Waiting review" is the รอพี่ตรวจ column with `.focus`.
- **Missing tasks:** a notification may point to an entry that is now invisible to the mentor (private, moved or deleted). Opening it must fail gracefully: toast plus mark read.

### Revision 1 — DataTam · 2026-11-08 (owner decisions)

Meejai's F1 fix to `can_read_notebook_file` (legacy id match only for path-less metadata) is kept unchanged.

| # | Change | Where |
|---|---|---|
| R1-1 | **Mentor-assigned tasks are locked.** On rows with `created_by <> user_id` the intern can't change `tab`, can't set `is_private = true`, and can't delete. The old ASSUMPTION that allowed it is removed. The transition rule's mentor-assigned test now uses the same null-safe definition, `coalesce(created_by <> user_id, false)`. | `entries_before_write`; new restrictive policy `entries_delete_lock_assigned` (AND-ed with `entries_delete_own`) |
| R1-2 | **`task_edited` notification** to the intern when the mentor changes any of `title, body, due, priority, checklist, attachments, workspace_ids`. `payload.fields` lists the changed columns. Not sent for status/blocked-only changes. The type CHECK is dropped and re-added as `notifications_type_check` so a table from the first version gains the new value. The update trigger's WHEN clause covers the new columns. | `entries_after_write_notify`, `entries_after_update_notify`, `notifications` |
| R1-3 | **Display names**: `mentorships.intern_name` / `mentor_name` (nullable text, 1–60 chars, trimmed by `mentorships_one_role`; `''` becomes null). Clients can still only SELECT. Every trigger-created payload gains `actor_name` (null when unset). The owner placeholder insert/upsert now includes the names. | `mentorships`, both notify functions, §12 owner step |

Still not executed. The §12 conditions stand. Re-review focus for Meejai: the restrictive delete policy, and the WHEN-clause/`fields` logic.

### Code QA — Meejai · 2026-11-08 (`index.html`, mentor MVP + Plan B theme, uncommitted)

**Verdict: PASS WITH FIXES.** Static review + Babel parse (OK). 003 still not executed.

| # | Fix | Where |
|---|---|---|
| C1 | `errText`: the Rev 1 tab-lock refusal ("…it stays in Work") and "Mentor can only work with Work tasks" now map to a Thai toast instead of the generic "ไม่มีสิทธิ์". | §6 `errText` |
| C2 | Pending list: don't show the AssignedBadge "จากพี่เลี้ยง" next to the MentorPill on mentor-created rows (same guard the card already had). | §11 `PendingTasks` |
| C3 | `markRead`: roll the optimistic `readAt` back if the PATCH fails (it re-threw but kept the rows marked read). | §4d `createSbSocial` |

Checked OK: pre-003 path (`detectRole` → PGRST205/42P01 → intern, caps off; `legacy003` strips status/is_private/blocked before the first write; no comment/notification queries or channels), 003-with-old-client, snake/camel map, `created_by`/`blocked_at` never sent, `user_id = ownerId`, `.eq('user_id', ownerId)` on both initial loads, comments insert/update only, notifications update `read_at` only, realtime filters, 42501 → toast + rollback, mentor attachments untouched (no `url` added), `fileName` fallback, `canSetStatus` vs trigger (no UI-allowed transition the DB rejects), null `createdBy`, mentor focus/reconnect refetch.

Open (non-blocking): importing an old backup over live mentor-workflow rows can hit a 42501 (e.g. backup `status:'changes'`, approved mentor task reopened, or `isPrivate:true` on a mentor task) and the whole 500-row batch rolls back; `window.prompt` for the send-back note (accepted for MVP); after the owner inserts the mentorship row the intern must reload once to get the bell.
