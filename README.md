# FunTarget Platform (Monorepo)

This repository contains both the **legacy Salesforce implementation** and the **new platform** (clients, backend APIs, database, migration, docs).

## Folders

- `salesforce/` — legacy Salesforce DX project (Apex, LWC, metadata). Do not modify unless explicitly requested.
- `project/` — new platform workspace:
  - `project/game-desktop/` — Flutter Windows `.exe` (primary client going forward)
  - `project/backend-api/` — Spring Boot (deploy on Render)
  - `project/database/` — DB docs/notes (source-of-truth migrations live in `supabase/`)
  - `project/migration/` — Salesforce → Postgres mapping + tools
  - `project/docs/` — setup + runbooks

## Common commands

Salesforce:

- `cd salesforce && npm install`
- `cd salesforce && npm test`

Git hooks (one-time per clone):

- `npm install`
