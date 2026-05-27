# Releases (Windows Desktop)

This repo publishes the Windows desktop build as a zip attached to a GitHub Release.

## Versioning rules

- Use SemVer tags: `vMAJOR.MINOR.PATCH` (example: `v0.2.1`).
- Flutter app version lives in `project/game-desktop/pubspec.yaml` (`version: x.y.z+build`).
- Backend version lives in `project/backend-api/build.gradle` (`version = ...`).

## Release checklist

1. Update versions
   - `project/game-desktop/pubspec.yaml`
   - `project/backend-api/build.gradle` (optional unless backend changed)
2. Update notes
   - Append to `CHANGELOG.md`
3. Push to `main` and ensure CI is green
   - `Flutter Windows Desktop (Artifact)` should pass
4. Create and push a tag
   - `git tag v0.1.0`
   - `git push origin v0.1.0`
5. Validate Release output
   - GitHub Actions run: `Release - Windows Desktop`
   - GitHub Release should contain: `funtarget-windows.zip`
6. Smoke test (when possible)
   - Unzip
   - Run `FunTarget.exe` (no setup required; CI embeds config into the build)
   - Login + run a full round
   - Confirm updater: open the in-app Update dialog and ensure it says “No updates available.”
