# Small group deployment

## Render API and database

1. Push this repository to a Git provider and create a Render Blueprint from it, selecting the root `render.yaml`.
2. Render creates the `studyapp-api` web service and `studyapp-db` PostgreSQL database. The blueprint generates a persistent JWT signing secret and injects the database connection string.
3. Once the service is live, check `https://study-app-b0xq.onrender.com/health` and `/health/live`. The first route checks the database; the second is the Render liveness probe.
4. If Render assigns a different service URL, use that exact HTTPS origin in the mobile and web build commands below. Add any custom web origin to `CORS_ALLOWED_ORIGINS` on Render, separated by commas.

The blueprint uses Render's free plans for an initial pilot. Free web services can sleep while idle and free databases are temporary; before relying on the app for ongoing student records, select a persistent paid database plan and confirm backups/retention in Render.

## Firebase Hosting

The Hosting project is `studyapp-51772` and the Flutter web build is published from `mobile/build/web`.

1. Install the Flutter SDK and Firebase CLI, then authenticate with `firebase login` using an account that can deploy to this Firebase project.
2. From PowerShell at the repository root, run:

   ```powershell
   .\mobile\deploy_firebase.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com"
   ```

The script builds the production web app with the API URL embedded, then deploys Firebase Hosting. The Firebase project must already exist and be accessible to the signed-in account.

Google Sign-In requires a real OAuth client; the current `google-services.json` has no OAuth clients configured. In Firebase Authentication, enable the Google provider, add the Hosting domains, and configure OAuth credentials in the linked Google Cloud project. Register the Android package `com.studyapp.study_app_mobile` with the SHA-1 certificate fingerprints for the signing keys you use. Download the refreshed `google-services.json` and keep it local or commit it only if the project policy allows. The Render Blueprint prompts for the same Web client ID as `GOOGLE_CLIENT_ID`.

Set the OAuth Web client ID in the Render API environment as `GOOGLE_CLIENT_ID`, then redeploy the API. Build clients with the same ID so Google issues ID tokens for the audience the API validates:

```powershell
.\mobile\deploy_firebase.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com" -GoogleClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
.\mobile\build_release_apk.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com" -GoogleClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
```

The Google button now opens Google's real account authorization flow. StudyApp receives only Google's signed ID token; Google decides when to request a password, passkey, or second factor based on its session and security checks. Google can reuse a trusted device session, so the app cannot force a password or OTP prompt on every sign-in. Google password recovery is handled by Google, not by the StudyApp password reset form. For regular StudyApp password accounts, the current API has no production email sender, so the app now reports recovery as unavailable instead of claiming it sent a reset token. Configure an email provider before relying on that recovery path.

New StudyApp passwords require at least 12 characters, are blocked if they match a short common-password denylist, and are capped at 72 UTF-8 bytes to match BCrypt's effective input limit. Existing users can still sign in with passwords created under the earlier policy.

## Android APK for testers

Debug APKs are for development only. For a release APK, create a private upload keystore and a local `mobile/android/key.properties` (never commit either file). From the repository root, generate a keystore with:

```powershell
keytool -genkeypair -v -keystore mobile/android/app/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `mobile/android/key.properties.example` to `mobile/android/key.properties` and enter the keystore passwords. Its `storeFile=app/upload-keystore.jks` path is relative to `mobile/android`. Keep a backup of the keystore and credentials; losing them prevents testers from installing signed updates over this APK.

Build the signed APK from the repository root:

```powershell
   .\mobile\build_release_apk.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com"
```

Share `mobile/build/app/outputs/flutter-apk/app-release.apk` privately with the pilot group. Android may ask each tester to allow installs from the app used to open the APK. Use the same signing key for every future update installed over this build.

## Pilot checks

- Register a new account, sign in, and confirm data remains after an API restart.
- Try one study session and one file import from both Android and the hosted web app.
- Confirm the deployed `/health` endpoint reports the database as available before inviting testers.
- Keep the pilot small while free Render services may sleep and the free database has limited lifetime/backup guarantees.
