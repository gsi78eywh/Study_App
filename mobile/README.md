# StudyApp mobile client

StudyApp is a Flutter client for the StudyApp API. It supports Android, iOS,
web, and desktop targets. The mobile app has no provider API keys compiled into
it: all AI requests go through the authenticated backend.

## Local development

Start the API first, then run the client. Android emulators use
`http://10.0.2.2:5000` automatically; iOS simulators, desktop, and web default
to `http://localhost:5000`. A physical device must use a reachable HTTPS API
URL, configured in Settings or at build time.

```powershell
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

## Release checklist

- Configure a unique Android application id and a real release signing key.
- Set the production API URL with `API_BASE_URL`; never ship `localhost`.
- Deploy the API with a persistent PostgreSQL database and production environment
  variables, including `JwtSettings__Secret` (32+ characters).
- Restrict production CORS to the hosted web client origin when building web.
- Google Sign-In needs the OAuth Web client ID passed as `GOOGLE_CLIENT_ID`;
  email/password sign-in works without it.
- Complete Android/iOS store metadata, privacy policy, and account-deletion
  requirements before publication.

## Build targets

```powershell
# Play Store bundle
flutter build appbundle --dart-define=API_BASE_URL=https://api.example.com

# Static web release in build/web
flutter build web --dart-define=API_BASE_URL=https://api.example.com
```

Flutter's Android app bundle is the appropriate Play Store artifact. The web
release can be hosted on a static host, while the API must run separately in a
container or managed .NET environment.

# Pilot deployment

See [the small group deployment guide](../docs/SMALL_GROUP_DEPLOYMENT.md) for the Render API, Firebase Hosting deploy command, and signed Android APK setup.

Google sign-in uses Google's account authorization and verified ID token flow. Release builds must provide the Firebase/Google OAuth Web client ID as `GOOGLE_CLIENT_ID`; the API must validate tokens for the same ID. New app passwords follow the 12-character and BCrypt byte-length policy documented in the deployment guide.
