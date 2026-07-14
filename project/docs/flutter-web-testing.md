# Flutter Web Testing (FunTarget)

Use Flutter Web for development/testing when you cannot run the Windows `.exe` locally.

## Prerequisites

- Flutter SDK (stable)
- Chrome

Verify:

- `flutter doctor`
- `flutter config --enable-web`

## Run

From repo root:

```bash
cd project/game-desktop
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project_ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon_key> \
  --dart-define=API_BASE_URL=http://80.225.236.170
```

## Notes

- The app authenticates with Supabase (email/password) and calls the backend using `Authorization: Bearer <access_token>`.
- Backend endpoints used:
  - `GET /api/funtarget/state`
  - (later) `POST /api/funtarget/intent`
- To keep behavior identical to Salesforce, the round timer is anchored to `last_round_at` (see `project/docs/funtarget-data-contract.md`).
- If the web app is hosted on HTTPS, browsers can block calls to the HTTP Oracle IP as mixed content. Desktop and Android are not affected by browser mixed-content rules.
