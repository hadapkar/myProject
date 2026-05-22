# Flutter Web Preview (No local Flutter install)

If you cannot install Flutter locally, use GitHub Actions + GitHub Pages to build and host the Flutter Web app automatically.

This repo includes a workflow:

- `.github/workflows/flutter-web-preview.yml`

## One-time GitHub setup

### 1) Add repository secrets

In GitHub: **Repo → Settings → Secrets and variables → Actions → New repository secret**

Add:

- `SUPABASE_URL` = `https://<project_ref>.supabase.co`
- `SUPABASE_ANON_KEY` = `<anon key>`
- `API_BASE_URL` = `https://<your-render-backend>`

Notes:

- Supabase anon key is publishable (safe for clients), but still keep it in secrets to avoid accidental copy/paste mistakes.

### 2) Enable GitHub Pages from Actions

In GitHub: **Repo → Settings → Pages**

- **Source**: select **GitHub Actions**

## How it works

- On every push to `main` that touches `project/game-desktop/**`, GitHub Actions builds Flutter Web and deploys to Pages.
- Your preview URL will be:
  - `https://<github-username>.github.io/<repo-name>/`

## Troubleshooting

- If you see a blank page, ensure Pages is enabled and the workflow succeeded.
- If routing breaks on refresh, we will add a “single-page app fallback” later (minimal change) once the UI is implemented.

