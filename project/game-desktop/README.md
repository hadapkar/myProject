# FunTarget Game (Flutter Desktop)

Goal: build the FunTarget game as a **Flutter app** that can run as:

- **Flutter Web** (for day-to-day testing in a browser)
- **Windows desktop `.exe`** (final target client)

This module will replace `project/game-web/` over time, but we keep the web version as a reference until the Flutter UI matches 1:1.

## Prerequisites (Dev)

- Install Flutter SDK (stable).
- For Windows `.exe` builds: Visual Studio 2022 with “Desktop development with C++”.

Verify:

- `flutter doctor`
- `flutter config --enable-web`
- `flutter config --enable-windows-desktop` (optional, for `.exe` builds)

## Configuration

The desktop app will need these values:

- `SUPABASE_URL` (ex: `https://ydljofhkpeusxoegnvfs.supabase.co`)
- `SUPABASE_ANON_KEY` (Supabase “anon” key)
- `API_BASE_URL` (Render backend base URL, ex: `https://backend-api-ia1r.onrender.com`)

**Desktop runtime config (recommended):**

- **Release zips** have these values embedded (no setup required for end users).
- Optional (dev/advanced): override via Windows environment variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_BASE_URL` or a local `config.json` next to the `.exe`.

**Dev config (`flutter run`):**

- `flutter run -d windows --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=...`
- `flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=...`

## Run (Flutter Web)

From repo root:

- `cd project/game-desktop`
- `flutter pub get`
- `flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=...`

## Assets

We will reuse the existing assets already extracted for the web build:

- `project/game-web/public/funTargrtAsset/media/...`
- `project/game-web/public/funTargrtAsset/Sounds/...`

In Flutter, these will be copied into this module under `assets/` and referenced via `pubspec.yaml`.

## Next steps (Phase 1 → Phase 3)

1. Confirm the Supabase schema in `supabase/migrations/` is the single source of truth for game state.
2. Scaffold the Flutter project in this folder and build a first screen:
   - login (email/password via Supabase)
   - FunTarget screen (UI + assets + audio + timer) matching Salesforce behavior

## Non-negotiable requirement

The Flutter implementation must match the **Salesforce LWC game logic** (round timing, spin/result seconds, payout rules, state transitions). We will treat the Salesforce behavior as the reference and port it exactly.

## Windows builds (no local Flutter needed)

Two options:

- **CI Artifact (every push):** GitHub Actions → `Flutter Windows Desktop (Artifact)` → download `King Maker.zip`.
- **GitHub Release (versioned):** push a git tag like `v0.1.0` and GitHub will attach `King Maker.zip` to the release.
  - Recommended: use GitHub Actions workflow `Manual Release - Windows Desktop`.

## Auto-update (Option 1)

The Windows desktop app includes an in-app updater:

- It checks the latest GitHub Release for `King Maker.zip` (and falls back to `funtarget-windows.zip` for older releases).
- If a newer version is available, you can install it from inside the app (no manual download needed).

Notes:

- This requires the GitHub Release asset to be reachable by end users (public repo or otherwise publicly accessible release artifacts).
- Web builds don’t self-update; GitHub Pages/Vercel deployments update automatically.
