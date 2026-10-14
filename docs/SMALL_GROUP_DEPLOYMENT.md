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

## Google Sign-In credentials

The API validates Google ID tokens against the OAuth **Web application** client ID. Keep that Web client ID as `GOOGLE_CLIENT_ID` on the API and pass it to Flutter builds as `GOOGLE_CLIENT_ID`. Do not put a Web client secret in Flutter or in this repository.

1. In Google Cloud Console, select project `studyapp-51772` (the project behind this Firebase app), then open **Google Auth Platform**. On **Branding**, set the app name, user support email, and developer contact email. On **Audience**, choose External for public Google accounts; while the app is in Testing, add each tester's Google account. Publish the app when ready for general access and complete any verification Google requires for the requested scopes.
2. Open **Clients → Create client → Web application**. Name it `StudyApp Web and API`. Add the exact deployed web origins under **Authorized JavaScript origins**, including `https://studyapp-51772.web.app` and `https://studyapp-51772.firebaseapp.com` (plus any custom domain). This app posts the ID token to its API; it does not use a Google redirect URI. Copy the client ID, which ends with `.apps.googleusercontent.com`.
3. Under **Clients**, create an **Android** client for package `com.studyapp.study_app_mobile`. Add the SHA-1 signing fingerprints for every build you will use. For local debug builds, run `cd mobile\android` then `.\gradlew.bat signingReport` in PowerShell and copy the debug SHA-1. If Java is not on `PATH`, set `JAVA_HOME` to the JDK directory first. For a release APK, use the upload keystore SHA-1; if distributing through Play, also register the Play App Signing SHA-1 from Play Console. Android clients are bound to package name plus certificate fingerprint.
4. If using the iOS app, create an **iOS** client for bundle ID `com.studyapp.studyAppMobile` and provide its client ID at build time as `GOOGLE_IOS_CLIENT_ID`. Add the iOS client's `REVERSED_CLIENT_ID` as a URL scheme in `mobile/ios/Runner/Info.plist` (Google's generated `GoogleService-Info.plist` contains this value). The web client ID remains `GOOGLE_CLIENT_ID` so the returned ID token has the audience the API validates.
5. In Firebase Console for `studyapp-51772`, if using Firebase's Google provider/config generation, enable **Authentication → Sign-in method → Google**, use the same project and web client ID, and save. Add the Hosting domains under Authentication authorized domains if that provider is used. Download the refreshed `google-services.json` and replace `mobile/android/app/google-services.json`; it should list the Android OAuth client and Web client. Keep the file local or commit it only if project policy allows. The current file contains no OAuth clients.
6. In the Render API environment, set `GOOGLE_CLIENT_ID` to the Web client ID and redeploy. Build the web app and Android APK with that same Web client ID:

```powershell
.\mobile\deploy_firebase.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com" -GoogleClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
.\mobile\build_release_apk.ps1 -ApiBaseUrl "https://study-app-b0xq.onrender.com" -GoogleClientId "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com"
```

For local Flutter runs, pass the same audience explicitly, for example `flutter run --dart-define=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com`. Android uses the Web ID as its server client ID; its Android OAuth client is discovered through the Android package/SHA-1 registration and generated Firebase config. For iOS, also pass `--dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID.apps.googleusercontent.com`.

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
