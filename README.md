# FunTarget Platform (Monorepo)

This repository contains both the **legacy Salesforce implementation** and the **new platform** (web game, backend APIs, admin app, database).

## Folders

- `salesforce/` — legacy Salesforce DX project (Apex, LWC, metadata)
- `project/` — new platform workspace (web game, backend APIs, admin app, database, migration, docs)

## Common commands

Salesforce:

- `cd salesforce && npm install`
- `cd salesforce && npm test`

Git hooks (one-time per clone):

- `npm install`

## Notes

- Salesforce is kept for reference and incremental migration.
- New platform development will live under `project/game-web/`, `project/backend-api/`, and `project/admin-app/`.
