# StudyApp Production Deployment & Architecture Guide

## Architecture Overview

1. **Mobile & Web Client (`mobile/`)**:
   - Flutter 3.x offline-first client (Android APK, iOS, Web).
   - Local SQLite persistence (`DatabaseHelper`) + instant on-device AI/simulation fallback (`SethAiEngine`) so simulations, flashcards, OCR, PDF layout preview, and YouTube summaries never freeze or crash the app on slow networks.
2. **Backend API (`backend/src/StudyApp.Api`)**:
   - .NET 10 Web API containerized via `Dockerfile` (includes `tesseract-ocr` for server-side OCR).
   - Deployed on **Google Cloud Run** (`cloudbuild.yaml`, `deploy_cloudrun.ps1`) with automatic HTTPS load balancing, horizontal autoscaling (`concurrency: 80`), and `/health` + `/health/live` readiness probes.

---

## Deploying to Google Cloud Run (Recommended Production)

1. Authenticate with Google Cloud:
   ```bash
   gcloud auth login
   gcloud config set project studyapp-51772
   ```
2. Deploy using `deploy_cloudrun.ps1` or `gcloud run deploy`:
   ```bash
   gcloud run deploy studyapp-api \
     --source . \
     --region asia-southeast1 \
     --platform managed \
     --allow-unauthenticated \
     --port 8080 \
     --cpu 2 \
     --memory 1Gi \
     --concurrency 80 \
     --min-instances 1 \
     --max-instances 10 \
     --cpu-boost
   ```
3. Verify the health endpoint:
   ```bash
   curl https://<YOUR-CLOUD-RUN-URL>/health
   ```

---

## Local Development & Testing

- **Run Backend Tests**:
  ```bash
  dotnet test backend/StudyApp.sln
  ```
- **Run Mobile Tests & Static Analysis**:
  ```bash
  cd mobile
  flutter analyze
  flutter test
  ```
