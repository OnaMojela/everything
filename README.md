# Everything

A premium, offline-first Android and web app that unifies **personal productivity** and **personal finance** — two first-class experiences inside one calm, consistent ecosystem. All data lives on-device in SQLite and the app is fully usable with no account at all. Signing in with Google is optional, and adds cross-device sync through Supabase — see [Sync](#sync).

## Product principles

- **Two apps, one home.** Productivity (habits, tasks, planner, focus) and Finance (accounts, transactions, budgets, bills, goals) are fully independent modules that share only navigation, search, themes and settings. Neither influences the other's data.
- **Customization is the feature.** The home dashboard is built entirely from widgets the user can add, remove and reorder. Either module can be hidden completely — navigation and analytics adapt.
- **Calm, premium design.** 4/8pt spacing grid, 20px rounded cards, one accent color, restrained type scale, subtle implicit animations, Light / Dark / OLED-black themes.
- **Fast and offline forever.** Reactive SQLite streams; every screen updates live. The local database is the source of truth even when sync is on, so nothing waits on the network.

## Tech stack

| Concern | Choice | Why |
| --- | --- | --- |
| State | Riverpod | Reactive, testable, minimal boilerplate |
| Database | Drift (SQLite) | Offline-first, relational, type-safe, live query streams |
| Navigation | go_router (`StatefulShellRoute`) | Persistent bottom-nav branches + pushed detail routes |
| Preferences | shared_preferences | Theme, accent, module visibility, dashboard layout |
| Charts | fl_chart | Line/bar charts in analytics |

## Architecture

```
lib/
├── main.dart                # bootstrap + task rollover on launch
├── app.dart                 # MaterialApp.router, themes, routes
├── core/
│   ├── theme/app_theme.dart      # design tokens, accent palette, 3 themes
│   ├── settings/app_settings.dart# persisted user settings + dashboard registry
│   ├── utils/utils.dart          # ids, day keys, date/money formatting
│   └── widgets/widgets.dart      # AppCard, ProgressRing, Heatmap, pickers, sheets…
├── data/
│   ├── db/database.dart          # Drift schema (13 tables) + seeded categories
│   ├── logic/domain_logic.dart   # habit scheduling, streaks, balances, budget windows
│   ├── models/enums.dart         # HabitType, ScheduleType, TxType, AccountType…
│   └── providers.dart            # stream providers + Repo mutations
└── features/
    ├── shell/          # bottom navigation (module-aware)
    ├── dashboard/      # widget-based customizable home
    ├── productivity/   # habits, tasks, planner, focus
    ├── finance/        # accounts, transactions, budgets, bills, goals
    ├── analytics/      # productivity + finance insights
    ├── search/         # app-wide instant search
    └── settings/       # appearance, modules, preferences
```

### Key behaviors

- **Habits** support 5 completion types (checkbox, counter, numeric, duration, percentage) and 7 schedule types (daily, weekdays, weekends, specific weekdays, every X days, days of month, yearly). Streaks, best streak, 30-day rate and a GitHub-style heatmap are computed in `domain_logic.dart`.
- **Tasks** that are unfinished automatically roll forward to today on app launch (`Repo.rolloverTasks`), so nothing is ever forgotten.
- **Planner** is a manual timeline (day / week / agenda) — tap an empty slot to plan a block.
- **Focus** records every session ≥1 minute; analytics show totals, averages, longest session and per-subject breakdowns.
- **Account balances** are always derived: `initialBalance + Σ(transaction effects)` — transfers debit one account and credit another.
- **Budgets** compute their active window (weekly / monthly / yearly / custom) on the fly and track expense + investment spend within scope (category and/or account).
- **Bills**: "Mark paid" optionally records the expense transaction and advances the next due date by its recurrence.

## v2 additions

- **Notifications**: habit reminders (next 7 scheduled occurrences), bill alerts at 09:00 on the due day and the day before, focus/pomodoro phase alarms. Rescheduled automatically whenever habits or bills change.
- **App lock**: biometric unlock with device-PIN fallback (`local_auth`), covering launch and every return from background.
- **Money as integer cents** (schema v2 migration preserves existing data). All arithmetic is exact; formatting happens only at the edge (`formatMoney`/`parseMoneyToCents`).
- **Recurring transactions**: standing orders that auto-post on launch with catch-up (Transactions tab → Recurring).
- **Weekly-quota habits** ("3× per week, any days") with week-based streaks, plus **skip days** that preserve streaks (long-press a habit row).
- **Focus v2**: sessions survive app kill (timestamp-based, persisted), pomodoro work/break cycles with auto-advance, ongoing notification chip.
- **Planner v2**: long-press-drag to move blocks, drag the bottom handle to resize (15-min snap), copy-previous-day, daily/weekly recurring blocks, read-only overlays for timed tasks and habit reminders.
- **Analytics v2**: date-range selector, 12-month net-worth chart, per-budget period history, per-habit weekly trend.
- **Home-screen widgets**: "Today's habits" (tap a row to toggle via background isolate — no app launch) and "Quick add" (expense/income deep links).
- **Category manager**: Settings → Finance → Categories.

## Backup, export and restore

Settings → *Your data*. The app is offline-only, so a backup file is the only recovery path — and the only way to move data between the phone and the web app.

- **Back up everything** writes a single readable JSON file: a version header, your settings, and every table in dependency order.
- **Export transactions as CSV** produces a spreadsheet-friendly ledger with signed amounts, resolved account and category names, and RFC-correct quoting.
- **Restore from backup** replaces all current data. It runs inside a transaction, so a malformed file leaves your existing data untouched, and unknown columns from other versions are ignored rather than failing. Backups from a newer app version are refused with a clear message.

Round-trip fidelity (including cents, quotes in text, and settings) is covered by `test/backup_test.dart`.

## Auto-categorisation

Confirming a transaction remembers which category that merchant belongs to, so the next one categorises itself — in the capture inbox and when typing a merchant manually. `lib/data/logic/merchant_rules.dart` normalises merchant names (dropping store numbers, `PTY LTD`-style noise and punctuation) and falls back to a first-word match, so "WOOLWORTHS SANDTON" inherits the category learned from "WOOLWORTHS ROSEBANK". Repeated confirmations strengthen a rule; choosing a different category replaces it.

## Automatic transaction capture (Android)

Everything can read bank notifications and turn them into transactions. Settings → *Automatic transaction capture*.

**How it works.** A `NotificationListenerService` (`TransactionNotificationListener.kt`) receives posted notifications and immediately discards anything that doesn't mention a currency amount — non-money notifications are never stored. Survivors are queued in app-private storage; on launch and on demand, Flutter drains the queue, runs each through `lib/data/logic/bank_parser.dart`, and files the transaction-shaped ones in a review inbox.

The parser extracts the **amount** (handling `R1 234,56`, `R1,234.56`, `$25.50`), the **direction** (debit vs credit vs refund, from keyword position), the **merchant**, the **account's last four digits**, and the **bank**. It rejects balance notices, OTPs, marketing and declined payments. Every field is covered by tests in `test/bank_parser_test.dart`.

**Matching to accounts.** Each account has `notificationHints` — card last-four digits and/or a bank name. Digits win over bank name. Confirming a capture offers to remember the hint, so subsequent notifications from that card file themselves to the right account.

**Duplicate detection.** One purchase usually produces several notifications — the bank's own app, the messaging app showing the bank's SMS, and caller-ID apps like Truecaller reading that same SMS. `lib/data/logic/duplicate_detection.dart` folds them into a single inbox item: matching amount and direction within a 10-minute window, with card digits acting as a veto when both sides know them. The kept item shows "Also reported by Truecaller, Messages" and inherits any details the repeats knew but it didn't. Confirming also checks the ledger (6-hour window, or same day when a transaction has no time) and warns before saving the same purchase twice; auto-save is suppressed entirely when a ledger match exists.

**Balance sync.** Bank messages usually end with the balance ("Avail R3 100,00", "Available balance R4 300,00"). The parser reads it — excluding that span when looking for the transaction amount, so the two are never confused — and, on confirming, corrects the account so its displayed balance equals the bank's figure. Because balances here are derived (`initialBalance + transaction deltas`), the correction adjusts the *starting* balance: recorded transactions and analytics are never rewritten, and later transactions carry on from the synced figure. Skipped for credit cards, loans, investments and crypto, where "available balance" means available credit or market value rather than the account balance. Covered by `test/balance_sync_test.dart`.

**Privacy and control.** Notification access must be granted by the user in Android settings; it cannot be requested programmatically. Nothing is added to the ledger until confirmed in the inbox (opt-in auto-save exists for high-confidence, account-matched captures). The original notification text is always shown next to what was parsed. Apps can be muted individually. No data leaves the device.

## Web

The same codebase runs as a real web app — habits, tasks, planner, focus, accounts, budgets and analytics all work in the browser.

```bash
flutter build web --release
```

```bash
python serve_web.py
```

Then open <http://localhost:8099>.

**Storage.** Data lives in the browser via SQLite compiled to WebAssembly (`web/sqlite3.wasm` + `web/drift_worker.js`), persisted in OPFS when the page is cross-origin isolated, otherwise IndexedDB. Signed out, nothing is uploaded anywhere and clearing site data clears the app; signed in, the same local database is mirrored to your account (see [Sync](#sync)).

**Hosting.** `build/web` is a static bundle — drop it on Netlify, Cloudflare Pages, GitHub Pages, Vercel or any static host. Vercel is configured out of the box via `vercel.json` (see [Deploying the web app to Vercel](#deploying-the-web-app-to-vercel)). `web/_headers` carries the equivalent cache and cross-origin-isolation rules for Netlify/Cloudflare; Flutter skips underscore-prefixed files when copying, so copy it after building:

```bash
cp web/_headers build/web/_headers
```

Serving from a subpath needs `flutter build web --base-href /subpath/`.

**Platform differences.** Local notifications, biometric app lock and Android home-screen widgets are phone-only capabilities. Rather than showing controls that do nothing, the web build hides them (see `lib/core/platform/platform_support.dart`); everything else is identical. A release web build also registers a service worker, so the app keeps working offline after the first visit and can be installed as a PWA.

**Layout.** Below 700px the app uses the bottom navigation bar; above it switches to a side rail (labelled past 1100px), the dashboard becomes two columns, and content is capped at 1080px so it stays readable on wide monitors.

## Sync

Optional cross-device sync, backed by Supabase, with email/password or Google sign-in. Signing in is never required: without an account the app behaves exactly as it always has, and a build with no Supabase credentials hides the sync UI entirely rather than showing a button that cannot work.

> A missing Sync section in a deployed build almost always means `SUPABASE_URL` or `SUPABASE_ANON_KEY` was absent at build time — **both** are required. Environment variables are compiled in, so adding them to Vercel needs a redeploy, not just a save.

### How it works

The local Drift database stays the source of truth on every platform. The UI only ever reads SQLite, so screens render at local-disk speed, the app works with no connection, and a sync failure cannot take a feature down. Supabase is a mirror, not the primary store.

- **Change tracking.** SQLite triggers on all 16 tables record every insert, update and delete into a `sync_changes` log (`lib/data/sync/sync_schema.dart`). Triggers rather than repository code, so no existing query or screen needed changing. The database also runs with `PRAGMA recursive_triggers = ON`, which is what makes rows removed by `ON DELETE CASCADE` fire their triggers — those never pass through application code, so repository-level tracking would miss them. (Today no cascade actually fires; see [Known issue](#known-issue-foreign-keys-are-not-enforced).)
- **A cycle is push, then pull.** That ordering is what makes conflict handling honest: by the time the pull runs, this device's pending edits are already on the server, so an incoming row cannot overwrite a local change that had not been sent yet. Rows with a still-pending local edit are skipped by the pull regardless.
- **Conflicts resolve last-write-wins**, judged by the server clock. Devices disagree about the time — often by minutes — so `sync_updated_at` is stamped by a Postgres trigger and never by a client.
- **Deletes are tombstones** (`sync_deleted = true`). Hard-deleting would make a deletion invisible to any device that had not yet pulled.
- **Isolation.** Every table has a composite `(user_id, id)` primary key and an RLS policy of `auth.uid() = user_id`, so a row is only ever readable and writable by the account that owns it.

Row ids are client-generated UUIDs, so devices can create records offline without coordinating and never collide.

### Schema

`supabase/migrations/0001_mirror_schema.sql` is **generated** from the Drift schema — do not edit it by hand:

```bash
flutter test test/supabase_schema_test.dart --dart-define=WRITE=1
```

The same test fails on a normal run whenever the checked-in SQL no longer matches the app's tables, so a column added locally cannot silently go missing on the server. Apply the file in the Supabase SQL editor, or with `supabase db push`.

Two deliberate differences from the local schema: the mirror has **no foreign keys** (SQLite enforces integrity where the app actually reads, and omitting them lets push and pull apply tables in any order), and datetimes are stored as `bigint` unix seconds exactly as Drift stores them locally, which keeps sync a pure passthrough with no date parsing.

### Sign-in methods

**Email and password** is the primary path and needs no provider setup — Supabase enables it by default.

One project setting matters: **Authentication → Sign In / Providers → Email → Confirm email**. Left on (the default), signing up sends a confirmation link and no session starts until it is opened; the app shows a "Check your inbox" step for exactly this. Turn it off for a personal project and accounts are usable immediately.

**Google** is optional and sits below the email form. Until the provider is enabled in Supabase it returns `provider is not enabled` — the button is left in place so it starts working the moment it is switched on. To check the state of a project without involving the app:

```
https://<project-ref>.supabase.co/auth/v1/authorize?provider=google
```

A redirect to Google's account picker means enabled; a 400 with `provider is not enabled` means it is not.

### Supabase setup

1. Create a project, then run the generated migration above.
2. **Authentication → Sign In / Providers → Google** *(optional)*: enable it, and paste in the client id and secret from a Google Cloud OAuth **Web application** credential. The panel has its own Save button — toggling the switch alone does not persist.
3. In Google Cloud, add Supabase's callback to that credential's *Authorized redirect URIs*: `https://<project-ref>.supabase.co/auth/v1/callback`.
4. **Authentication → URL Configuration**: add every origin the app is served from to *Redirect URLs*, including Vercel preview domains — `https://your-app.vercel.app`, `https://*-your-team.vercel.app`, and `http://localhost:8099` for local testing.
5. For an Android build, also create an **Android** OAuth client with your signing SHA-1, and pass the *web* client id as `GOOGLE_WEB_CLIENT_ID` — Supabase verifies the ID token against its own client id, which is the web one even on Android.

### Credentials

Passed at build time as `--dart-define`s, read in `lib/core/auth/supabase_config.dart`:

| Define | Needed for |
| --- | --- |
| `SUPABASE_URL` | any sync at all |
| `SUPABASE_ANON_KEY` | any sync at all |
| `GOOGLE_WEB_CLIENT_ID` | Android/iOS native Google sign-in |
| `GOOGLE_IOS_CLIENT_ID` | iOS only |

The first two are both required — with only one set, `SupabaseConfig.isConfigured` is false and the app builds as offline-only.

All four are public values — the anon/publishable key grants only what RLS allows, and OAuth client ids are public by design. **Never** put the Supabase service-role key in a client build.

### Signing in and out

First sign-in on a device that has never synced **uploads** the data already there, so offline work is not lost. Signing in as a *different* account wipes the local database first — a shared laptop must never blend two people's finances. Signing out uploads anything pending, then clears the device; the data stays in the account and returns on the next sign-in.

### Not synced

Preferences in `shared_preferences` — theme, accent, currency symbol, dashboard layout, your name, app-lock and capture settings — stay per-device. Only the SQLite tables sync.

### Known issue: foreign keys are not enforced

The schema declares `onDelete: KeyAction.cascade` on several tables, but `drift_dev` cannot resolve those `references()` calls — it emits a *"This parameter should be a simple class name"* warning for each and then drops the constraint. `PRAGMA foreign_key_list` is empty for every table, so **no** foreign key exists in the database.

This predates sync. Its effect is orphaned rows: deleting a habit leaves its entries behind, deleting an account leaves its transactions behind. The rows are invisible in the UI (queries filter by parent id) but they accumulate, and sync now uploads them.

Sync is consistent either way — the orphans simply exist identically on every device — and the change-log triggers already handle real cascades, so fixing the schema will not require touching the sync engine. The test `deleting a habit does not currently remove its entries` in `test/sync_change_log_test.dart` pins the current behaviour and is expected to fail when this is fixed.

## Deploying the web app to Vercel

`vercel.json` builds the app with `tool/vercel_build.sh`, which downloads the Flutter SDK (the Vercel build image has none) into the build cache, so only the first build after a version bump pays the download.

1. Push the project to a Git repository and import it in Vercel.
2. Add `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `GOOGLE_WEB_CLIENT_ID` under **Settings → Environment Variables**.
3. Deploy. Leave the framework preset as *Other* — `vercel.json` supplies the build command and `build/web` output directory.

If the Supabase variables are missing the build still succeeds and ships an offline-only app, with a warning in the build log.

**Cross-origin isolation.** `vercel.json` sends `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` so the database can use OPFS instead of falling back to IndexedDB. Two consequences worth knowing:

- Google sign-in on web uses a **full-page redirect**, not a popup — `COOP: same-origin` severs `window.opener`, so a popup flow would hang. This is why the web and native paths differ in `lib/core/auth/auth_service.dart`.
- `require-corp` blocks cross-origin subresources that do not opt in, which is why the signed-in avatar renders as an initial rather than loading Google's profile image.

To check the headers locally, serve the build with one of the bundled servers rather than a plain static server — both send the same headers Vercel does:

```bash
node tool/serve_web.mjs
```

```bash
python serve_web.py
```

## Android release builds

Two things bite only in release, never in debug, and both crash the app at launch with no Dart stack trace to explain why.

**The `INTERNET` permission.** Flutter injects it into debug and profile manifests so the tooling can attach a debugger, so `flutter run` works whether or not the app declares it. A release APK gets only what `android/app/src/main/AndroidManifest.xml` asks for. `test/android_manifest_test.dart` fails if it goes missing again.

**R8 shrinking.** Release builds are shrunk and renamed, which breaks anything resolved by name at runtime. WorkManager — pulled in by `home_widget` — keeps its queue in a Room database that Room instantiates reflectively; R8 removed its no-arg constructor and the app died before Flutter started:

```
java.lang.RuntimeException: Unable to get provider androidx.startup.InitializationProvider:
  Failed to create an instance of androidx.work.impl.WorkDatabase
```

`android/app/proguard-rules.pro` keeps those constructors, along with the notification receivers, widget providers and the notification-listener service, all of which are named in the manifest rather than called from code.

When a release build crashes on launch and debug is fine, suspect one of these two. The Dart console shows nothing useful — read the Java trace instead:

```bash
adb logcat -d -b crash
```

## Building

```
flutter pub get
dart run build_runner build   # regenerate Drift code after schema changes
flutter run                   # or: flutter build apk
```

With sync enabled:

```
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGci... --dart-define=GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
```
