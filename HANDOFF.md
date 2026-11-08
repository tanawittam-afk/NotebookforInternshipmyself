# Handoff — Second Brain · Internship Notebook

_Last updated: 2026-11-08_

Personal notebook for the owner's HR internship at Plan B (6 Nov 2026 – 5 Mar 2027).
Single user. Single-file app: `index.html` (React 18 UMD + Babel standalone, no build step).

## Where things live

| What | Where |
|---|---|
| Live site | https://notebookforinternshipmyself.vercel.app (always use this URL — per-deployment URLs are separate sites) |
| GitHub | `tanawittam-afk/NotebookforInternshipmyself`, branch `main` — a push to `main` auto-deploys on Vercel |
| Vercel project | `tanawittam-afks-projects/notebookforinternshipmyself` (the Vercel MCP connector can't see this project — use the browser or GitHub commit status) |
| Supabase | https://ivbajugeynbhjnlemjgg.supabase.co — client uses the publishable key `sb_publishable_…` (public by design; never put a secret/service_role key in the client) |
| SQL | `supabase/setup.sql` (run) · `supabase/002_workspaces.sql` (run) · `supabase/003_mentor.sql` (run 2026-11-08) |
| Building image | `assets/plan-b-tower.jpg` |

## 2026-11-08 — Mentor role MVP + Plan B theme (commit `e2eda91`, deployed)

- Client is live and backward-compatible; mentor features stay off until `supabase/003_mentor.sql` is run.
- Specs: `docs/mentor-architecture.md` (contract, §11 owner steps, §13 QA log), `docs/planb-theme.md`.
- Owner decisions: one mentor; mentor sees non-private Work only; can create/edit/comment; mentor-assigned tasks locked for the intern; `task_edited` alerts; display names in `mentorships`.
- Done 2026-11-08: owner ran 003, added the mentor account (email kept out of this public repo), linked as พี่ตี๋ / แทม. Intern-side live test passed (link + names, new tables readable, intern blocked from `changes`); `[TEST]` data and file deleted.
- **Still open:** the mentor-side live test (§11 step 4) was NOT run — run it before handing พี่ตี๋ the password.
- Next after MVP: LINE group alerts (Messaging API via DB webhook/Edge Function or n8n, notifications table is the event source), end-of-internship summary, inline composer to replace `window.prompt`, `.btn` 44px.
- Known non-blocking: importing an old backup over mentor-touched rows can fail the whole batch (42501); the intern reloads once after the mentorship insert to get the bell.

## Previous state (commit `89fc8ff`)

- **Backend:** Supabase first, then Firebase (config empty), then local IndexedDB demo mode.
- **Auth:** email + password, invite-only. Supabase sign-up is disabled; we verified it rejects a signup attempt.
  - To add a user: Supabase → Authentication → Users → Add user → tick Auto Confirm User.
- **Data:**
  - `entries` table: `workspace_ids text[]`, `assigned_by`, `checklist jsonb`.
  - `workspaces` table: a company → department (optional) → position tree, plus position-card fields.
  - Both tables use RLS (own rows only) and realtime.
  - Files go to the private bucket `notebook-files` under `<uid>/`.
- **Features:**
  - Calendar with Work/Study/Ideas tabs (unchanged).
  - Workspace sidebar that filters the calendar, Pending and search; Summary view per company/position.
  - Assigned by (mentor/self/other) and a checklist on Work tasks.
  - Learning template with `## ` headings.
  - Position card: headcount, status, channels, opened_on, note.
  - Building view: Plan B Tower image plus a searchable floor list in `PLANB_FLOORS`, transcribed as printed. Fl. 25 appears twice on the image — kept both.
- The owner's Nov 6 task was imported into Supabase. A local backup is at `C:\Users\User\Desktop\second-brain-backup-2026-11-07.json`.

## Verified vs not yet verified

- ✅ Syntax parses. The demo-mode run-through passed (by DevBAmooTam). Meejai QA passed. Live page loads signed in with no console errors.
- ⏳ **Not yet used with the real account:** adding companies/positions, the checklist, assigned-by, the position card, the Summary view, and realtime sync between two devices. **First thing next session: ask the owner if everything saved correctly.**

## Known non-blocking issues (from Meejai)

1. In local demo mode only, if another tab is still running the old code, the IndexedDB v1→v2 upgrade can hang. There's no `onblocked` handler. Supabase users aren't affected.
2. Importing a backup whose workspace points to a missing parent fails the workspace upsert (error 23503). Entries still import and a toast shows.
3. In a narrow sidebar, a long position name gets truncated next to its status badge. The full path shows on hover.
4. The Firestore rules would need `users/{uid}/workspaces` — only matters if Firebase is ever turned on.

## Ideas parked for later (from Idea)

- Pin / ⭐ favourites
- Weekly Review
- HR glossary
- Daily stand-up export
- Spaced re-read
- Note links with `[[...]]` and backlinks
- End-of-internship summary (hand off to SmakTam)

Applicant-level data was deliberately left out because of PDPA.

## Team flow used

DataTam (SQL) ∥ DevBAmooTam (index.html) → Meejai QA → owner runs SQL in the Supabase dashboard → push to `main` → check the Vercel commit status plus the live page.
