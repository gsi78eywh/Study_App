# StudyApp deployment and release guide

This guide is the release checklist for the StudyApp API, mobile APK, and web client.

## 1. Deploy the API before distributing the app

Use a managed PostgreSQL database for any multi-user or load-balanced deployment. SQLite is suitable only for one local instance because each instance otherwise has a separate database file.

Deploy the root `Dockerfile` (or `backend/Dockerfile` when the backend folder is selected as the build context). Configure these environment variables in the hosting provider:

| Variable | Required value |
| --- | --- |
| `ConnectionStrings__DefaultConnection` | Managed PostgreSQL connection string, for example `Host=...;Database=...;Username=...;Password=...;SSL Mode=Require` |
| `JwtSettings__Secret` | One random secret with at least 32 characters; use the exact same value on every API instance. |
| `JwtSettings__Issuer` | `StudyApp` unless the mobile client is changed. |
| `JwtSettings__Audience` | `StudyAppMobileClient` unless the mobile client is changed. |
| `DATA_PROTECTION_KEY_PATH` | Shared persistent storage path, normally `/app/data/data-protection-keys`. |
| `Cors__AllowedOrigins__0` | Exact HTTPS origin of the web app, if publishing the web client. |
| `AiSettings__ApiKey` | Production Gemini key, stored only in the hosting provider secret store. |

Do not commit passwords, JWT secrets, Gemini keys, or signing keys.

Mount persistent storage at `/app/data` when operating a single SQLite instance. For multiple API instances, use PostgreSQL and shared data-protection keys; never rely on container-local SQLite files. Confirm `GET /health` returns HTTP 200 before building the mobile release.

## 2. Build the tester APK

From `mobile`, replace the URL with the deployed HTTPS API URL:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
```

The APK is created at `mobile/build/app/outputs/flutter-apk/app-release.apk`. The app has an API-server setting on the sign-in screen for emergency test configuration, but the release should always be built with the public HTTPS endpoint so testers do not need to configure it.

The current Gradle project signs release builds with its debug key. That is acceptable only for a short internal pilot. Before publishing publicly, configure an upload/release keystore and change the Android release signing configuration to use it. Keep the keystore and passwords outside Git.

## 3. Publish a GitHub release

Create a versioned tag and attach the generated APK:

```powershell
git tag v1.0.0-beta.1
git push origin main --tags
gh release create v1.0.0-beta.1 mobile/build/app/outputs/flutter-apk/app-release.apk --title "StudyApp v1.0.0-beta.1" --notes-file docs/RELEASE_NOTES.md
```

Only run this after GitHub authentication succeeds (`gh auth status`) and after the APK is tested on a physical Android device. GitHub Release assets are downloadable by everyone if the repository is public.

## 4. Rollback and support

Keep the previous APK release available. If a severe issue is reported, stop inviting new testers, publish a fixed build under a new version, and ask testers to update. Do not reuse an Android version code for a replacement APK.
