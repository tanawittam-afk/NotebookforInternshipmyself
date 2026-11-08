# Plan B Theme + Mentor MVP UI: Implementation Spec

**Owner:** Noey (UI/UX) · **Implementer:** DevBAmooTam · **QA:** Meejai
**Target:** `index.html` (single file, React 18 UMD + Babel, no build step)
**Standard:** WCAG 2.2 AA. Project floor for touch targets is **44 × 44 px** on `pointer: coarse`.
**Status:** Ready to implement. This doc changes no business rules. Where the mentor feature's behavior isn't defined yet, the doc marks it `ASSUMPTION:`.

---

## 0. Scope and ground rules

| # | Rule | Why |
|---|------|-----|
| R1 | **Drop-in token swap.** Every existing `:root` name is kept and only its value changes. New tokens are added alongside. | Zero selector churn, so the theme switch is a one-block diff plus the hard-coded fixes in §6. |
| R2 | **No dark mode.** I checked: the file has no `prefers-color-scheme` query and no `data-theme` attribute. The only media-feature hook is `prefers-reduced-motion` (line 521). Do not add a dark mode. | Out of scope. A half-built dark mode costs more than none. |
| R3 | **Colors and motif only, not identity.** Do not reuse the Plan B logo or wordmark, and do not write "Plan·B" as our product name. Our app stays "Second Brain". Add the disclaimer note (§4.5). | The app must not look like an official Plan B system. It is a personal notebook. |
| R4 | **Bright sky blue `#0AA9F0` is decorative only.** It is 2.64:1 on white, so it fails both text (4.5) and UI (3.0). Use it only for the header strip, the brand dot and gradient ends, and never where it is the only carrier of meaning. | WCAG 1.4.3 / 1.4.11 |
| R5 | Never color alone. Every status, flag and role carries **text + icon**. | WCAG 1.4.1 |

---

## 1. Palette sampled from `assets/plan-b-tower.jpg`

I sampled pixels with System.Drawing (dominant cluster per region, 3-px grid):

| Source region in the image | Sampled | Token it informs |
|---|---|---|
| "Plan" wordmark, navy floor cards (Fl. 11–12, 24-25, 28) | `#011D5E`, `#011E58`, `#021D54`, `#001858` cluster | `--navy` **#001A5C** |
| Floor-card header gradient, mid-point (Fl. 29–18) | `#0253AF`, `#0050A8` cluster | `--accent` / `--royal` **#0050AA** |
| Fl. 27 card gradient, right side | `#0070D0` → `#0088E0` | `--sage` (mid blue) **#2B7FD0**, darkened to reach ≥3:1 |
| "B" letter + the "·" dot | `#0BA9F0`, `#06A8F9`, `#00A8F0` cluster | `--sky` **#0AA9F0** (decorative) |
| Light floor cards (Fl. 1–6, 15, 17) | `#D4E9FE`, `#DDEEFF`, `#BFDCFA` | `--sky-soft` **#D3E9FD**, `--accent-soft` |
| Sky background, top of the image | `#F5F8FF`, `#EEF5FF` | `--bg` **#F3F7FD**, `--accent-softer` |

---

## 2. Token set (complete `:root` replacement)

### 2.1 Existing tokens: same names, new values

| Token | Old (olive/cream) | **New (Plan B)** | Role |
|---|---|---|---|
| `--bg` | #F6F3EA | **#F3F7FD** | Page background (light sky) |
| `--surface` | #FFFDF7 | **#FFFFFF** | Cards, popovers |
| `--surface-2` | #F0ECE0 | **#EAF1FB** | Hover rows, segment track, tab track |
| `--surface-3` | #E9E4D6 | **#DCE7F6** | Count pills, pressed |
| `--border` | #E3DDCC | **#D5E0EF** | Dividers, card borders (decorative, exempt from 3:1) |
| `--border-strong` | #CFC8B3 | **#7388A9** | Checkbox and input boundaries. **3.61:1 on white**, which fixes an old 1.4.11 failure (#CFC8B3 was about 1.6:1) |
| `--text` | #2E3229 | **#0B1B3F** | Body text (navy-black) |
| `--muted` | #6B6F60 | **#46587A** | Secondary text |
| `--faint` | #A3A596 | **#596B8B** | Tertiary text and placeholders. Now passes AA (old #A3A596 was about 2.5:1) |
| `--accent` | #5E7043 | **#0050AA** | Primary buttons, active tab, links, focus ring |
| `--accent-hover` | #4E5E37 | **#00337F** | Hover/pressed, text on soft-blue fills |
| `--sage` | #8FA06F | **#2B7FD0** | Mid blue: focus-within borders, calendar dots, active-row rails. ≥3:1 UI only, **never body text** |
| `--accent-soft` | #E3E9D3 | **#DDEAFB** | Selected/today fills, Work tab badge |
| `--accent-softer` | #EFF2E5 | **#EEF4FD** | Hover tints, focus halos |
| `--danger` | #A34A35 | **#B42318** | Errors, overdue, blocked |
| `--danger-soft` | #F5E2DB | **#FDE8E5** | |
| `--warn` | #8F6516 | **#8A5300** | Due today, medium priority, "รอพี่ตรวจ" |
| `--warn-soft` | #F4E9CF | **#FCEFD6** | |
| `--study` | #7A6420 | **#5B3CB8** | Study tab: violet (hue about 255°) |
| `--study-soft` | #F1EBD3 | **#ECE6FA** | |
| `--ideas` | #3E6656 | **#0A6B63** | Ideas tab: teal (hue about 175°) |
| `--ideas-soft` | #DDE9E2 | **#DCF1EC** | |
| `--radius` / `--radius-sm` | 14px / 9px | **unchanged** | |
| `--shadow` | olive-tinted | **`0 1px 2px rgba(0,26,92,.05), 0 6px 20px rgba(0,26,92,.07)`** | Navy-tinted |
| `--shadow-lg` | olive-tinted | **`0 10px 40px rgba(0,26,92,.18)`** | |
| `--font` | Inter + Plex Thai | **unchanged** | Body |

**Tab hue logic:** Work = royal blue (213°), Study = violet (255°), Ideas = teal (175°). All three sit in the cool family, so they harmonize with navy, but they are separated by ≥40° of hue and labeled with text, so they stay distinct for color-vision-deficient users.

### 2.2 New tokens

| Token | Value | Use |
|---|---|---|
| `--navy` | **#001A5C** | Brand navy: brand mark, card bands, role chip, mentor accents |
| `--royal` | **#0050AA** | Gradient end (same as `--accent`; a separate name so brand use and action use can diverge later) |
| `--sky` | **#0AA9F0** | **Decorative only** (R4): header strip end, brand dot |
| `--sky-soft` | **#D3E9FD** | Decorative washes |
| `--on-navy` | **#FFFFFF** | Text on navy, royal and gradient bands |
| `--on-navy-muted` | **#BFD6F5** | Secondary text on navy (10.87:1) |
| `--on-accent` | **#FFFFFF** | Replaces the hard-coded `#fff` on accent fills (optional cleanup, §6) |
| `--grad-band` | `linear-gradient(100deg, #001A5C 0%, #0050AA 100%)` | Card header band. White text ≥7.7:1 at every point |
| `--grad-strip` | `linear-gradient(90deg, #001A5C 0%, #0050AA 55%, #0AA9F0 100%)` | 3px decorative strip on the top bar. Carries no text |
| `--topbar-bg` | `rgba(243,247,253,.92)` | Replaces the hard-coded `rgba(246,243,234,.92)` |
| `--scrim` | `rgba(0,16,51,.40)` | Drawer backdrops |
| `--scrim-strong` | `rgba(0,16,51,.85)` | Lightbox |
| `--mark` | **#FFE58A** | Search hit highlight. Warm on purpose, so it can't be confused with the blue hover rows |
| `--success` / `--success-soft` | **#17663A** / **#DEF3E5** | Status "เสร็จ" |
| `--changes` / `--changes-soft` | **#A13A00** / **#FDEADB** | Status "ให้แก้" |
| `--blocked-tint` | **#FFF5F3** | Blocked card wash |
| `--navy-soft` | **#E3EAF7** | "จากพี่เลี้ยง" pill, mentor bubble |
| `--tap` | **44px** | Touch-target floor |
| `--font-head` | `"Prompt", "IBM Plex Sans Thai", system-ui, sans-serif` | Headings (§3) |

### 2.3 Contrast results

I computed these with the WCAG relative-luminance formula. Required: 4.5 (normal text) / 3.0 (large text, UI boundaries, focus).

| Foreground | Background | Ratio | Use | Result |
|---|---|---|---|---|
| `--text` #0B1B3F | `--bg` #F3F7FD | **15.72** | Body | ✅ AAA |
| `--text` | `--surface` #FFF | **16.90** | Card text | ✅ AAA |
| `--text` | `--surface-2` #EAF1FB | **14.86** | Hover rows | ✅ AAA |
| `--muted` #46587A | `--surface` | **7.15** | Secondary | ✅ AAA |
| `--muted` | `--bg` | **6.65** | | ✅ |
| `--muted` | `--surface-3` #DCE7F6 | **5.72** | Count pills | ✅ |
| `--faint` #596B8B | `--surface` / `--bg` | **5.38 / 5.01** | Tertiary | ✅ |
| `--faint` | `--surface-2` | **4.74** | | ✅ |
| `--faint` | `--surface-3` | 4.31 | | ❌ **Don't place faint on surface-3.** Use `--muted` there |
| `--accent` #0050AA | `--surface` | **7.70** | Links, outline buttons | ✅ AAA |
| `--accent` | `--bg` | **7.16** | Focus ring vs page | ✅ |
| `--accent` | `--accent-soft` #DDEAFB | **6.32** | | ✅ |
| `--accent-hover` #00337F | `--accent-soft` | **9.68** | Work badge, today | ✅ AAA |
| `--on-accent` #FFF | `--accent` | **7.70** | Primary button | ✅ AAA |
| `--on-navy` #FFF | `--navy` #001A5C | **16.13** | Role chip, band start | ✅ AAA |
| `--on-navy-muted` #BFD6F5 | `--navy` | **10.87** | | ✅ |
| `--on-navy-muted` | `--royal` | **5.19** | Band subtitle at gradient end | ✅ |
| `--sage` #2B7FD0 | `--surface` / `--bg` | **4.16 / 3.87** | Dots, focus-within borders (UI) | ✅ UI 3:1 · ❌ text, so never use for text |
| `--border-strong` #7388A9 | `--surface` / `--bg` | **3.61 / 3.35** | Checkbox and input edges | ✅ UI |
| `--sky` #0AA9F0 | `--surface` | **2.64** | — | ❌ **Decorative only** |
| `--sky` | `--navy` | 6.10 | Brand dot on the navy mark | ✅ (decorative anyway) |
| `--danger` #B42318 | `--danger-soft` | **5.59** | Overdue badge | ✅ |
| #FFF | `--danger` | **6.57** | Blocked flag, unread count | ✅ |
| `--warn` #8A5300 | `--warn-soft` | **5.56** | Due today, รอพี่ตรวจ | ✅ |
| `--study` #5B3CB8 | `--study-soft` | **6.20** | Study badge | ✅ |
| `--ideas` #0A6B63 | `--ideas-soft` | **5.41** | Ideas badge | ✅ |
| `--success` #17663A | `--success-soft` | **6.02** | เสร็จ | ✅ |
| `--changes` #A13A00 | `--changes-soft` | **5.76** | ให้แก้ | ✅ |
| `--text` | `--mark` #FFE58A | **13.54** | Search highlight | ✅ |

For comparison, the old accent #5E7043 on white was 5.42, so the new accent is a step up.

---

## 3. Typography

**Decision: add Prompt (500, 600) for headings only.** Keep Inter + IBM Plex Sans Thai for body, UI controls, tabs and buttons.

- **Why:** Plan B's wordmark is a geometric sans. Prompt (Cadson Demak) is a geometric, loopless Thai + Latin face with the same round-terminal feel, so headings pick up the brand character without copying the logo font. Body stays on Plex Sans Thai (looped), which reads better at 13–15px for long Thai notes. That keeps the expressive face at display sizes and the legible face for long text.
- **Cost:** two extra weights, about 40–60 KB woff2 with Thai + Latin subsets, loaded via the existing `display=swap`.

**Replace line 12 with:**

```html
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;500;600&family=Inter:wght@400;500;600&family=Prompt:wght@500;600&display=swap" rel="stylesheet" />
```

**Apply `--font-head` to:** `h1, h2, h3` (the global rule at line 64), `.brand-name`, `.cal-title`, `.panel-date`, `.pending-head h2`, `.auth-card h1`, `.mb-col-title`, `.card-band h2`.
**Do not apply to:** `h4`, `.tab`, `.btn`, `.badge`, `.group-title`, `.search-label`, or any `text-transform: uppercase` micro-labels. Prompt at 11–12px uppercase gets cramped.
**Metrics:** Prompt's Thai ascenders are tall, so set `line-height: 1.3` on headings and keep `letter-spacing: -0.01em` (Latin only; the effect on Thai is negligible).

---

## 4. Brand touches (restrained)

### 4.1 Header (`.topbar`)
- Keep the **light frosted bar** (`--topbar-bg`). I'm not switching to a navy bar. The search box, nav buttons and menus are all tuned for a light ground, and a navy bar would mean re-theming every control inside it, which is a bigger change for little UX gain.
- Add a **3px `--grad-strip` line at the top edge** via `.topbar::before`. It is decorative, so `aria-hidden` doesn't apply (pseudo-elements aren't read).
- `.brand-mark` changes to `--navy` fill with a white icon, plus a small `--sky` dot in its corner (the dot motif).

### 4.2 The "·" dot motif
- `.brand-dot`: a 6px `--sky` circle placed between "Second" and "Brain" in `.brand-name`, which echoes the Plan·B dot without copying the wordmark. Markup: `Second<span class="brand-dot" aria-hidden="true"></span>Brain`. Screen readers hear "SecondBrain" with no space, so wrap the name as `<span class="sr-only">Second Brain</span><span aria-hidden="true">Second<span class="brand-dot"></span>Brain</span>`.
- Optional: use the `.brand-dot` style in place of the text "·" separator in `.brand-sub`.
- **Don't** sprinkle dots elsewhere. Two placements at most (brand + footer note), so it stays a signature and doesn't turn into noise.

### 4.3 Card header band (floor-card look)
`.card-band` is an opt-in header strip: `--grad-band` background, white Prompt title, 14px 22px padding, `border-radius: 18px 18px 0 0` (matching `.card`). **Use it on three cards only:** Pending tasks, Building, and Mentor board. Do **not** band the calendar or the daily panel; they are working surfaces, and calm beats chrome there.

### 4.4 Focus rings
- Global: `:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }`. The existing rule stays as-is and now resolves to blue: 7.16:1 vs `--bg`, so it passes WCAG 2.4.7 / 2.4.11.
- On navy or gradient surfaces (`.card-band`, `.role-chip`, `.brand-mark`), use the override `outline-color: var(--on-navy)`.
- Inputs: keep the existing `border-color: var(--sage)` + `box-shadow: 0 0 0 3px var(--accent-softer)` pattern. `--sage` is now 3.87:1 vs `--bg`, so the focus border passes.

### 4.5 Disclaimer note
Text (exact): **`สมุดบันทึกส่วนตัว · ไม่ใช่ระบบทางการของ Plan B`**
- **Login:** `.disclaimer` at the bottom of `.auth-card`, 12px, `--muted`, centered.
- **App:** a new `<footer class="app-foot">` after `.layout`, with the same text, centered, 12px `--muted`, 24px vertical padding, plus `padding-bottom: env(safe-area-inset-bottom)`.
- `--muted` on `--bg` is 6.65:1 ✅.

### 4.6 Other
- `<meta name="theme-color">` becomes `#F3F7FD`.
- Favicon: navy rounded square, white ring, sky dot (data URI in §6).

---

## 5. Mentor MVP components

> `ASSUMPTION:` the data model gives each task `status ∈ {todo, in_progress, review, done, changes}`, a boolean `blocked`, `assigned_by_mentor`, `private`, and a comment list. Privacy, roles and notification rules belong to ArchitectTam/DataTam. This section specifies **presentation only**.
> `ASSUMPTION:` there is no drag-and-drop on the board. Status changes go through a status menu, because that's simpler, keyboard-accessible and touch-safe. If the owner wants DnD, raise it as a separate request.

### New icons for `ICONS` (feather-style, 24-grid, matching the existing ones)

```jsx
bell:    <><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></>,
lock:    <><rect x="3" y="11" width="18" height="11" rx="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" /></>,
message: <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />,
eye:     <><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" /><circle cx="12" cy="12" r="3" /></>,
rotate:  <><polyline points="1 4 1 10 7 10" /><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" /></>,
user:    <><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle cx="12" cy="7" r="4" /></>,
circle:  <circle cx="12" cy="12" r="9" />,
half:    <><circle cx="12" cy="12" r="9" /><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor" stroke="none" /></>,
```

### 5.1 Status pill: Atom

| status | Thai label | Icon | fg / bg | Ratio |
|---|---|---|---|---|
| `todo` | **รอทำ** | `circle` | `--muted` / `--surface-2` | 6.29 |
| `in_progress` | **กำลังทำ** | `half` | `--accent` / `--accent-soft` | 6.32 |
| `review` | **รอพี่ตรวจ** | `eye` | `--warn` / `--warn-soft` | 5.56 |
| `changes` | **ให้แก้** | `rotate` | `--changes` / `--changes-soft` | 5.76 |
| `done` | **เสร็จ** | `check` | `--success` / `--success-soft` | 6.02 |

- **Anatomy:** `[icon 12px][label]`, height 24px, padding 0 9px, radius 999px, 12px/500 font.
- **Display-only by default** (`<span class="st-pill s-review">`). When it's the **status changer** (task detail and board card), render a `<button class="st-pill s-… is-btn" aria-haspopup="menu" aria-label="สถานะ: รอพี่ตรวจ — เปลี่ยนสถานะ">` with a chevron. States: hover adds a `--border-strong` ring, focus-visible shows the global ring, disabled uses opacity .45. On coarse pointers the hit area extends to 44px via a `::after` inset; the visual height stays 24px.
- The menu reuses `.menu` / `.menu-item`, with each item showing its pill. On `pointer: coarse`, `.menu-item` must be 44px tall (§7 CSS).
- **Board column order (workflow order):** รอทำ → กำลังทำ → รอพี่ตรวจ → ให้แก้ → เสร็จ.

### 5.2 Blocked flag: Atom
- `<span class="flag-badge"><Icon name="flag" size={12}/>ติดปัญหา</span>`: **solid** `--danger` fill, white text (6.57:1), 24px tall, 12px/600.
- A solid fill sets it apart from the soft-filled status pills, so it reads as an alert and not as a state.
- Toggle (intern side): an outline `.btn sm` reading "แจ้งติดปัญหา". When active it shows the flag badge, and the button text becomes "ยกเลิกติดปัญหา".
- Screen readers: `aria-label` isn't needed because the text is real.

### 5.3 "จากพี่เลี้ยง" pill + 🔒 private indicator: Atoms
- `.mentor-pill`: `--navy-soft` bg, `--navy` text (well above AAA), `user` icon 12px, label **จากพี่เลี้ยง**, 22px tall.
- `.priv`: no fill, `--muted` text, `lock` icon 12px + label **ส่วนตัว**, `title="เห็นเฉพาะคุณ — พี่เลี้ยงมองไม่เห็น"`. Use the SVG lock, **not the 🔒 emoji**: emoji rendering varies by OS and ignores `currentColor`.
- Icon-only variant (dense board cards): keep the visible text anyway; at 12px it's short enough. Never icon-only without a label.

### 5.4 Mentor board: Organism

**Container:** `.card.mb` with a `.card-band` header: title **บอร์ดงานน้องฝึกงาน**, subtitle with counts (`--on-navy-muted`). On the right of the band: a filter toggle `.btn sm` "เฉพาะที่ติดปัญหา/เลยกำหนด" (`aria-pressed`).

**Columns (`.mb-col`):** header = status pill + count (`.n`), body = a list of `.mb-card`s.
- The **รอพี่ตรวจ** column header gets `.mb-col.focus` in mentor mode (a `--warn` 2px top border), because that column is the mentor's action queue.
- Empty column: `.mb-empty` dashed box with **ไม่มีงานในสถานะนี้**.

**Card (`.mb-card`)**, a Molecule: title (2-line clamp) · meta row [due badge · mentor-pill · priv · comment count `message` + n] · status changer pill. The whole card is a `<button>`/link that opens the task; the status pill is a separate button (stop propagation).
- **Blocked:** `.mb-card.blocked` gets a 4px left `--danger` rail, `--blocked-tint` background and the flag badge in the top line. Blocked cards **sort to the top** of their column.
- **Overdue** (due < today and status ≠ done): `.mb-card.overdue` gets a 4px left `--danger` rail (dashed style on the rail via `border-left-style: dashed`) plus the existing `.badge.overdue` reading "เลยกำหนด N วัน". Blocked wins if both apply (solid rail).
- **Due today:** the existing `.badge.due-today` "ครบกำหนดวันนี้", with no rail.
- Loading: 3 skeleton cards per column (`.mb-skel`, `--surface-2` blocks; the shimmer is disabled under reduced motion).
- Error: inline `.auth-msg.error` in the band body: **โหลดบอร์ดไม่สำเร็จ** + `.btn sm` **ลองใหม่**.

**Responsive:**

| Width | Behavior |
|---|---|
| ≥1280 | 5 equal columns, `grid-template-columns: repeat(5, minmax(0,1fr))`, each column scrolls vertically inside `max-height: 70vh` |
| 900–1279 | Horizontal scroll, columns `min-width: 260px`, `scroll-snap-type: x proximity` |
| ≤899 (tablet portrait + phones) | **Horizontal scroll with mandatory snap**, columns `width: 86%` so the next column peeks (affordance). Above the board, a sticky `.mb-jump` chip row (one `.tag-chip` per status, with counts) calls `scrollIntoView({inline:'start'})` on its column, and the chip of the column in view gets `.on` (IntersectionObserver). In mentor mode it defaults to the **รอพี่ตรวจ** column. |

**Why scroll + snap and not stacking:** stacking 5 columns pushes เสร็จ and ให้แก้ several screens down and breaks the board's mental model. Snap keeps one full column in view, the peek signals there's more, and the jump chips keep every column one tap away (Fitts's Law, Hick's Law).
- Keyboard: the board scroller is `tabindex="0"` with `aria-label="บอร์ดงาน เลื่อนซ้ายขวา"`, and the cards are tabbable in DOM order (column by column).

### 5.5 Comment / progress thread: Organism (inside task detail)

- `<ol class="thread" role="log" aria-live="polite" aria-label="ความคิดเห็นและความคืบหน้า">`
- **Message (`.msg`)**, a Molecule: avatar (28px circle, initials) · header [name · role label · `<time>`] · body (`.rich`).
  - **Mentor:** `.msg.mentor`, bubble `--navy-soft`, 3px left `--navy` rail, role label **พี่เลี้ยง** in `--navy` 600, avatar `--navy` bg with white initials.
  - **Intern:** `.msg.intern`, bubble `--surface` with a `--border` outline, role label **น้องฝึกงาน** in `--muted`, avatar `--accent-soft` bg with `--accent-hover` initials.
  - **Mine:** add `.mine` to align right (`flex-direction: row-reverse`). Role is shown by **label + rail + color**, never by color alone.
- **Timestamp:** `<time datetime="2026-11-08T14:32">`. Today shows "14:32", yesterday "เมื่อวาน 14:32", older "8 พ.ย. 14:32", plus `title` with the full date. 12px `--faint`.
- **System line (`.msg-sys`):** centered, 12px `--muted`, hairline rules on both sides (like `.divider`), e.g. `พี่มายด์ เปลี่ยนสถานะเป็น [st-pill s-changes] · 14:40`. Blocked toggles read "แจ้งติดปัญหา" / "ปลดสถานะติดปัญหา".
- **Composer (`.composer`):** textarea (min 72px, same style as `.editor textarea`), placeholder **อัปเดตความคืบหน้า หรือถามพี่เลี้ยง…**, `.btn primary` **ส่ง** (disabled when empty). Ctrl/⌘+Enter sends; Enter adds a newline (Thai IME-safe).
- States: sending puts a spinner in the button and keeps the textarea read-only. Failure shows a toast.error **ส่งไม่สำเร็จ ลองอีกครั้ง** and keeps the draft. Empty thread shows `.empty` **ยังไม่มีความคิดเห็น — เล่าความคืบหน้าให้พี่เลี้ยงฟังได้เลย**.
- Private tasks: hide the composer and show `.priv` + **งานส่วนตัว พี่เลี้ยงมองไม่เห็นและคอมเมนต์ไม่ได้**. (`ASSUMPTION:` private tasks have no mentor thread; ArchitectTam to confirm.)
- Motion: a new message fades/rises 160ms (`rise` keyframe already exists); removed under reduced motion.

### 5.6 Notification bell + dropdown: Molecule + Organism

- **Trigger:** `<button class="btn ghost icon-only bell" aria-haspopup="true" aria-expanded aria-label="การแจ้งเตือน, ยังไม่อ่าน 3 รายการ">`, placed in `.nav` before the account menu. Size 38px; on coarse pointers **44px**.
- **Count (`.bell-n`):** absolute top-right, min 18px, `--danger` bg, white 11px/600 text, a 2px `--surface` ring to separate it from the icon. Show "9+" above 9 and hide it at 0 (the aria-label then says "ไม่มีการแจ้งเตือนใหม่"). A pop animation (scale .6→1, 200ms) runs when the count increases; disabled under reduced motion.
- **Dropdown (`.notif`):** extends `.menu`, width 340px, `max-height: min(70vh, 480px)`, scrolls.
  - Header row: **การแจ้งเตือน** (600) + `.linklike` **อ่านทั้งหมด** (disabled at 0 unread).
  - Item (`.notif-item`, `<button>`, min-height 56px, at least 44px): 8px unread dot (`--sage`, plus **bold title**, so not dot-only) · line 1 = actor + action ("พี่มายด์ คอมเมนต์ใน *ทำสไลด์ onboarding*") · line 2 = `<time>` `--faint`. Clicking opens the task and marks it read. Read items: no dot, weight 400, `--muted`.
  - Event copy: assigned **มอบหมายงานใหม่**, comment **คอมเมนต์ใน**, status **เปลี่ยนสถานะ … เป็น**, review requested **ขอให้ตรวจ**, blocked **แจ้งติดปัญหาใน**.
  - Empty: **ยังไม่มีการแจ้งเตือน**. Loading: spinner + **กำลังโหลด…**. Error: **โหลดไม่สำเร็จ** + linklike **ลองใหม่**.
- Keyboard: Esc closes and returns focus to the bell; arrow keys move between items (same pattern as the existing account `.menu`); clicking outside closes.
- **≤720px:** the dropdown becomes a sheet: `position: fixed; left: 8px; right: 8px; top: 64px; width: auto`.

### 5.7 Role indicator: Atom
- `.role-chip` in the top bar, directly after `.brand`. It shows **only in mentor mode**, because intern mode is the default and needs no badge (less noise).
- Solid `--navy` bg, white text 12.5px/600, `eye` icon 14px, label **โหมดพี่เลี้ยง**, height 28px, radius 999px. Contrast 16.13:1.
- If it becomes a toggle (`ASSUMPTION:` only when one account can hold both roles), render it as a `<button>` with `aria-pressed` and a 44px coarse hit area.
- In mentor mode the top-bar strip thickens from 3px to 4px (`.topbar.mentor`). That's a decorative reinforcement; the text chip is the real signal.
- ≤720px: the label shortens to **พี่เลี้ยง** (text is still present, never icon-only).

### 5.8 Motion + touch summary
- Every new animation and transition is already neutralized by the existing global `prefers-reduced-motion` block (line 521). Additionally, set `scroll-behavior: auto` on `.mb-scroll` and drop the skeleton shimmer under reduce (included in the CSS).
- Durations: hover 150ms, pop/rise 160–200ms. No looping motion except the spinner (which the reduce rule also stops).
- Touch: every new interactive element is ≥44×44 on `pointer: coarse` (`--tap`). **Flag (outside this spec):** the existing `.btn` coarse height is 42px (line 95). I recommend bumping it to `var(--tap)` for consistency. It's a one-line change, but it's DevBAmooTam's call whether to include it in this PR.

---

## 6. Hard-coded colors found outside `:root`: must fix

I grepped the `<style>` block and JSX for `#hex` / `rgb(a)`. The JSX inline `style={{}}` props carry **no colors** (only `borderStyle`, `margin`).

| Line | Current | Replace with | Note |
|---|---|---|---|
| 8 | `<meta name="theme-color" content="#F6F3EA">` | `#F3F7FD` | |
| 9 | favicon `%235E7043` / `%23F6F3EA` | navy `%23001A5C`, white ring `%23FFFFFF`, sky dot `%230AA9F0`. Full URI: `data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%23001A5C'/%3E%3Ccircle cx='16' cy='16' r='7' fill='none' stroke='%23FFFFFF' stroke-width='2.5'/%3E%3Ccircle cx='16' cy='16' r='2.5' fill='%230AA9F0'/%3E%3C/svg%3E` | |
| 111 | `.topbar { background: rgba(246,243,234,.92) }` | `var(--topbar-bg)` | **Will look cream if missed** |
| 161 | `mark { background: #E6EDC4 }` | `var(--mark)` | **Olive-green highlight if missed** |
| 222 | `.day:disabled` stripes `rgba(227,221,204,.35)` | `rgba(213,224,239,.55)` | |
| 256 | `.tab.active` shadow `rgba(46,50,41,.15)` | `rgba(0,26,92,.18)` | |
| 305 | `.thumb .x` bg `rgba(46,50,41,.7)` | `rgba(11,27,63,.72)` | |
| 337 | `.segment button.on` shadow `rgba(46,50,41,.12)` | `rgba(0,26,92,.12)` | |
| 386 | `.lightbox` bg `rgba(32,35,28,.82)` | `var(--scrim-strong)` | |
| 483, 500 | `.backdrop` bg `rgba(32,35,28,.35)` | `var(--scrim)` | Two places (ws drawer + panel drawer) |
| 85, 103, 226, 228, 256, 259, 296, 383, 426 | `color: #fff` on accent/danger | optional `var(--on-accent)` | Fine as-is (white works on the new fills); cleanup only |
| 259, 384 | `rgba(255,255,255,.22/.14)` | keep | White overlays, theme-neutral |
| 762 (JS) | canvas `ctx.fillStyle = "#fff"` | **keep** | Image-export background, functional |
| 2715 (JSX) | Google "G" logo `#EA4335 #4285F4 #FBBC05 #34A853` | **keep** | Google brand-mandated colors |
| 9, 2523, 2658 | `.brand-mark` uses `color: var(--bg)` | change `.brand-mark` color to `var(--on-navy)` | Covered in the CSS below |

---

## 7. Paste-ready CSS

### 7.1 Replace lines 15–48 (header comment + `:root`)

```css
/* ============================================================
   Design tokens — Plan B palette (navy / royal / sky), personal use
   ============================================================ */
:root {
  --bg: #F3F7FD;
  --surface: #FFFFFF;
  --surface-2: #EAF1FB;
  --surface-3: #DCE7F6;
  --border: #D5E0EF;
  --border-strong: #7388A9;   /* UI boundaries — 3.61:1 on white */
  --text: #0B1B3F;
  --muted: #46587A;
  --faint: #596B8B;           /* ≥4.7:1 on bg/surface/surface-2; not on surface-3 */

  --accent: #0050AA;          /* Plan B royal — buttons, active tab, focus (7.7:1 on white) */
  --accent-hover: #00337F;
  --sage: #2B7FD0;            /* mid blue — dots, focus-within borders (UI only, never text) */
  --accent-soft: #DDEAFB;
  --accent-softer: #EEF4FD;

  --danger: #B42318;
  --danger-soft: #FDE8E5;
  --warn: #8A5300;
  --warn-soft: #FCEFD6;

  --study: #5B3CB8;  --study-soft: #ECE6FA;
  --ideas: #0A6B63;  --ideas-soft: #DCF1EC;

  --radius: 14px;
  --radius-sm: 9px;
  --shadow: 0 1px 2px rgba(0,26,92,.05), 0 6px 20px rgba(0,26,92,.07);
  --shadow-lg: 0 10px 40px rgba(0,26,92,.18);
  --font: "Inter", "IBM Plex Sans Thai", system-ui, -apple-system, "Segoe UI", sans-serif;

  /* ---- Plan B brand (new) ---- */
  --navy: #001A5C;
  --royal: #0050AA;
  --sky: #0AA9F0;             /* DECORATIVE ONLY — 2.64:1 on white */
  --sky-soft: #D3E9FD;
  --navy-soft: #E3EAF7;
  --on-navy: #FFFFFF;
  --on-navy-muted: #BFD6F5;
  --on-accent: #FFFFFF;
  --grad-band: linear-gradient(100deg, #001A5C 0%, #0050AA 100%);
  --grad-strip: linear-gradient(90deg, #001A5C 0%, #0050AA 55%, #0AA9F0 100%);
  --topbar-bg: rgba(243,247,253,.92);
  --scrim: rgba(0,16,51,.40);
  --scrim-strong: rgba(0,16,51,.85);
  --mark: #FFE58A;

  /* ---- Mentor statuses (new) ---- */
  --success: #17663A;  --success-soft: #DEF3E5;
  --changes: #A13A00;  --changes-soft: #FDEADB;
  --blocked-tint: #FFF5F3;

  --tap: 44px;
  --font-head: "Prompt", "IBM Plex Sans Thai", system-ui, -apple-system, "Segoe UI", sans-serif;
}
```

### 7.2 Edits to existing rules (surgical)

```css
/* line 64 */
h1, h2, h3 { font-family: var(--font-head); line-height: 1.3; }
h1, h2, h3, h4 { margin: 0; font-weight: 600; letter-spacing: -0.01em; }
.brand-name, .cal-title, .panel-date { font-family: var(--font-head); }

/* line 111 */
.topbar { background: var(--topbar-bg); }
/* line 122–125 */
.brand-mark { position: relative; background: var(--navy); color: var(--on-navy); }
/* line 161 */
mark { background: var(--mark); }
/* line 222 */
.day:disabled { background: repeating-linear-gradient(135deg, transparent 0 6px, rgba(213,224,239,.55) 6px 7px); }
/* line 256 */
.tab.active { box-shadow: 0 1px 3px rgba(0,26,92,.18); }
/* line 305 */
.thumb .x, .file-chip .x { background: rgba(11,27,63,.72); }
/* line 337 */
.segment button.on { box-shadow: 0 1px 2px rgba(0,26,92,.12); }
/* line 386 */
.lightbox { background: var(--scrim-strong); }
/* lines 483 & 500 */
.backdrop.ws, .backdrop { background: var(--scrim); }   /* keep inside their existing @media blocks */
```

### 7.3 New CSS: add before the `/* Responsive: iPad portrait & phones */` block (line 486)

```css
/* ---------- Plan B brand touches ---------- */
.topbar::before { content: ""; display: block; height: 3px; background: var(--grad-strip); }
.topbar.mentor::before { height: 4px; }
.brand-mark::after { content: ""; position: absolute; right: 5px; bottom: 5px; width: 6px; height: 6px; border-radius: 50%; background: var(--sky); }
.brand-dot { display: inline-block; width: 6px; height: 6px; margin: 0 3px 2px; border-radius: 50%; background: var(--sky); vertical-align: middle; }
.card-band {
  display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px;
  margin: -1px -1px 0; padding: 14px 22px;
  background: var(--grad-band); color: var(--on-navy);
  border-radius: 18px 18px 0 0;
}
.card-band h2 { font-family: var(--font-head); font-size: 18px; color: var(--on-navy); }
.card-band .sub { font-size: 12.5px; color: var(--on-navy-muted); }
.card-band .btn { background: rgba(255,255,255,.12); border-color: rgba(255,255,255,.28); color: var(--on-navy); }
.card-band .btn:hover:not(:disabled) { background: rgba(255,255,255,.2); }
.card-band .btn[aria-pressed="true"] { background: var(--on-navy); color: var(--navy); }
.card-band :focus-visible, .role-chip:focus-visible { outline-color: var(--on-navy); }
.app-foot { padding: 24px 16px calc(24px + env(safe-area-inset-bottom)); text-align: center; font-size: 12px; color: var(--muted); }
.disclaimer { margin-top: 18px; text-align: center; font-size: 12px; color: var(--muted); }

/* ---------- Role indicator ---------- */
.role-chip {
  display: inline-flex; align-items: center; gap: 6px; flex: none;
  height: 28px; padding: 0 11px; border: 0; border-radius: 999px;
  background: var(--navy); color: var(--on-navy);
  font-size: 12.5px; font-weight: 600; white-space: nowrap;
}
.role-chip .short { display: none; }

/* ---------- Status pill ---------- */
.st-pill {
  position: relative; display: inline-flex; align-items: center; gap: 5px;
  height: 24px; padding: 0 9px; border: 0; border-radius: 999px;
  font-size: 12px; font-weight: 500; line-height: 1; white-space: nowrap;
  transition: box-shadow .15s;
}
.st-pill.s-todo        { background: var(--surface-2);    color: var(--muted); }
.st-pill.s-in_progress { background: var(--accent-soft);  color: var(--accent); }
.st-pill.s-review      { background: var(--warn-soft);    color: var(--warn); }
.st-pill.s-changes     { background: var(--changes-soft); color: var(--changes); }
.st-pill.s-done        { background: var(--success-soft); color: var(--success); }
.st-pill.is-btn { cursor: pointer; }
.st-pill.is-btn:hover:not(:disabled) { box-shadow: 0 0 0 1px var(--border-strong); }
.st-pill.is-btn:disabled { opacity: .45; cursor: not-allowed; }

/* ---------- Blocked flag, mentor pill, private ---------- */
.flag-badge {
  display: inline-flex; align-items: center; gap: 4px;
  height: 24px; padding: 0 9px; border-radius: 999px;
  background: var(--danger); color: #fff; font-size: 12px; font-weight: 600; line-height: 1;
}
.mentor-pill {
  display: inline-flex; align-items: center; gap: 4px;
  height: 22px; padding: 0 8px; border-radius: 999px;
  background: var(--navy-soft); color: var(--navy); font-size: 11.5px; font-weight: 600; line-height: 1;
}
.priv { display: inline-flex; align-items: center; gap: 4px; font-size: 12px; color: var(--muted); }

/* ---------- Mentor board ---------- */
.mb { overflow: hidden; }
.mb-jump { display: none; }
.mb-scroll { padding: 16px; overflow-x: auto; scroll-behavior: smooth; }
.mb-cols { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; align-items: start; }
.mb-col { display: flex; flex-direction: column; gap: 8px; min-width: 0; padding: 10px; border-radius: 13px; background: var(--surface-2); border-top: 2px solid transparent; }
.mb-col.focus { border-top-color: var(--warn); }
.mb-col-head { display: flex; align-items: center; gap: 8px; min-height: 28px; }
.mb-col-title { font-family: var(--font-head); font-size: 14px; font-weight: 600; }
.mb-col-head .n { margin-left: auto; font-size: 12px; color: var(--muted); }
.mb-list { display: flex; flex-direction: column; gap: 8px; max-height: 70vh; overflow-y: auto; }
.mb-card {
  display: flex; flex-direction: column; gap: 8px; width: 100%;
  padding: 10px 12px; text-align: left;
  border: 1px solid var(--border); border-left: 4px solid transparent; border-radius: 11px;
  background: var(--surface); box-shadow: var(--shadow);
  transition: border-color .15s, box-shadow .15s;
}
.mb-card:hover { border-color: var(--border-strong); }
.mb-card.overdue { border-left: 4px dashed var(--danger); }
.mb-card.blocked { border-left: 4px solid var(--danger); background: var(--blocked-tint); }
.mb-card-title { font-weight: 500; font-size: 14px; line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.mb-card .meta { gap: 5px; }
.mb-count { display: inline-flex; align-items: center; gap: 3px; font-size: 12px; color: var(--muted); }
.mb-empty { padding: 14px 8px; border: 1.5px dashed var(--border-strong); border-radius: 11px; text-align: center; font-size: 12.5px; color: var(--muted); }
.mb-skel { height: 72px; border-radius: 11px; background: linear-gradient(90deg, var(--surface) 0%, var(--surface-3) 50%, var(--surface) 100%); background-size: 200% 100%; animation: shimmer 1.4s linear infinite; }
@keyframes shimmer { to { background-position: -200% 0; } }
@media (max-width: 1279px) {
  .mb-cols { grid-template-columns: none; grid-auto-flow: column; grid-auto-columns: minmax(260px, 1fr); }
  .mb-scroll { scroll-snap-type: x proximity; }
  .mb-col { scroll-snap-align: start; }
}
@media (max-width: 899px) {
  .mb-jump { display: flex; gap: 6px; overflow-x: auto; position: sticky; top: 0; z-index: 2; padding: 10px 16px; background: var(--surface); border-bottom: 1px solid var(--border); }
  .mb-jump .tag-chip { flex: none; min-height: var(--tap); }
  .mb-jump .tag-chip.on { background: var(--accent-soft); border-color: var(--accent); color: var(--accent-hover); }
  .mb-scroll { scroll-snap-type: x mandatory; padding: 12px 16px; }
  .mb-cols { grid-auto-columns: 86%; }
  .mb-list { max-height: none; }
}

/* ---------- Thread ---------- */
.thread { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 12px; }
.msg { display: flex; align-items: flex-start; gap: 8px; animation: rise .16s ease; }
.msg.mine { flex-direction: row-reverse; }
.msg-av { flex: none; width: 28px; height: 28px; border-radius: 50%; display: grid; place-items: center; font-size: 11.5px; font-weight: 600; }
.msg.mentor .msg-av { background: var(--navy); color: var(--on-navy); }
.msg.intern .msg-av { background: var(--accent-soft); color: var(--accent-hover); }
.msg-bubble { min-width: 0; max-width: min(85%, 520px); padding: 8px 12px; border-radius: 12px; }
.msg.mentor .msg-bubble { background: var(--navy-soft); border-left: 3px solid var(--navy); }
.msg.intern .msg-bubble { background: var(--surface); border: 1px solid var(--border); }
.msg-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px; margin-bottom: 2px; font-size: 12.5px; }
.msg-name { font-weight: 600; color: var(--text); }
.msg-role { font-size: 11.5px; font-weight: 600; color: var(--muted); }
.msg.mentor .msg-role { color: var(--navy); }
.msg time { font-size: 12px; color: var(--faint); }
.msg .rich { font-size: 14px; }
.msg-sys { display: flex; align-items: center; gap: 10px; font-size: 12px; color: var(--muted); text-align: center; }
.msg-sys::before, .msg-sys::after { content: ""; flex: 1; height: 1px; background: var(--border); }
.msg-sys .st-pill { height: 20px; padding: 0 7px; font-size: 11.5px; }
.composer { display: flex; flex-direction: column; gap: 8px; margin-top: 12px; }
.composer textarea { width: 100%; min-height: 72px; resize: vertical; border: 1px solid var(--border); border-radius: 10px; background: var(--bg); padding: 10px 12px; line-height: 1.55; font-size: 14.5px; outline: 0; }
.composer textarea:focus { border-color: var(--sage); background: var(--surface); box-shadow: 0 0 0 3px var(--accent-softer); }
.composer-row { display: flex; align-items: center; gap: 8px; }
.composer-row .hint { flex: 1; }

/* ---------- Notification bell ---------- */
.bell { position: relative; }
.bell-n {
  position: absolute; top: 2px; right: 2px;
  min-width: 18px; height: 18px; padding: 0 5px; border-radius: 999px;
  background: var(--danger); color: #fff; box-shadow: 0 0 0 2px var(--surface);
  font-size: 11px; font-weight: 600; line-height: 18px; text-align: center;
  animation: pop .2s ease;
}
@keyframes pop { from { transform: scale(.6); } }
.notif { width: 340px; max-height: min(70vh, 480px); overflow: auto; padding: 0; }
.notif-head { position: sticky; top: 0; display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 12px 14px; background: var(--surface); border-bottom: 1px solid var(--border); font-weight: 600; font-size: 14px; }
.notif-list { list-style: none; margin: 0; padding: 4px; }
.notif-item { width: 100%; display: flex; align-items: flex-start; gap: 10px; min-height: 56px; padding: 9px 10px; border: 0; border-radius: 9px; background: transparent; text-align: left; color: var(--muted); }
.notif-item:hover { background: var(--surface-2); }
.notif-item .ud { flex: none; width: 8px; height: 8px; margin-top: 7px; border-radius: 50%; background: transparent; }
.notif-item.unread { color: var(--text); }
.notif-item.unread .ud { background: var(--sage); }
.notif-item.unread .notif-text { font-weight: 600; }
.notif-text { font-size: 13.5px; line-height: 1.45; }
.notif-item time { display: block; margin-top: 2px; font-size: 12px; font-weight: 400; color: var(--faint); }
.notif-empty { padding: 24px 14px; text-align: center; font-size: 13.5px; color: var(--muted); }

/* ---------- Touch targets (≥44px) ---------- */
@media (pointer: coarse) {
  .bell { width: var(--tap); height: var(--tap); }
  .st-pill.is-btn::after { content: ""; position: absolute; inset: -10px -4px; }
  .role-chip[aria-pressed] { min-height: var(--tap); }
  .menu-item { height: var(--tap); }
  .composer .btn { height: var(--tap); }
}

/* ---------- Small screens ---------- */
@media (max-width: 720px) {
  .notif { position: fixed; left: 8px; right: 8px; top: 64px; width: auto; }
  .role-chip .long { display: none; }
  .role-chip .short { display: inline; }
  .msg-bubble { max-width: 88%; }
}

/* ---------- Reduced motion (supplements the global rule at line 521) ---------- */
@media (prefers-reduced-motion: reduce) {
  .mb-scroll { scroll-behavior: auto; }
  .mb-skel { animation: none; background: var(--surface-2); }
  .msg, .bell-n { animation: none; }
}
```

**Role chip markup:** `<span class="role-chip"><Icon name="eye" size={14}/><span class="long">โหมดพี่เลี้ยง</span><span class="short">พี่เลี้ยง</span></span>`

---

## 8. Acceptance criteria (for DevBAmooTam + Meejai)

1. After the swap, `grep -nE "F6F3EA|5E7043|E6EDC4|rgba\(46,50,41|rgba\(32,35,28|rgba\(246,243,234|rgba\(227,221,204"` returns **0 hits** in `index.html`.
2. No cream or olive remains anywhere: top bar, search highlight, favicon, theme-color, backdrops and lightbox are all blue/navy.
3. `--sky` appears only in `--grad-strip`, `.brand-dot`, `.brand-mark::after` and the favicon. It is never a text color and never a meaningful UI border.
4. Headings render in Prompt (check DevTools → Computed → rendered font); body text remains Inter / IBM Plex Sans Thai.
5. Each of the 5 status pills shows its exact Thai label and icon; blocked shows a solid red "ติดปัญหา"; none of them relies on color alone.
6. The board shows 5 columns at 1280px, horizontal snap with the next column peeking at 390px, jump chips scroll to the right column, and mentor mode opens on รอพี่ตรวจ.
7. Every new interactive element measures ≥44×44 px under touch emulation.
8. With OS "reduce motion" on: no bell pop, no message rise, no shimmer, and the board scroll jumps instantly.
9. axe or Lighthouse accessibility run: 0 contrast violations on login, main, board and thread views.
10. The disclaimer "สมุดบันทึกส่วนตัว · ไม่ใช่ระบบทางการของ Plan B" is visible on the login card and in the app footer. No Plan B logo is used as UI chrome (the existing Building-card infographic is content and is fine).

## 9. Handoffs
- **ArchitectTam / DataTam:** confirm the task fields in the §5 `ASSUMPTION`s (status enum, `blocked`, `assigned_by_mentor`, `private`), whether private tasks can have threads, how the role is determined, and the notification event list (§5.6 event copy).
- **DevBAmooTam:** apply §7.1 → §7.2 → §6 favicon/meta → §7.3, then build the components. Out-of-scope flag: the existing `.btn` coarse height is 42px; consider `var(--tap)`.
- **Meejai:** verify against §8.
