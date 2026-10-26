# StudyApp: Google Cloud Run & Small-Group Deployment Guide

This guide explains how to deploy **StudyApp** on **Google Cloud Run** (`studyapp-51772` / `asia-southeast1`) with multi-endpoint failover, zero cold-start lag, and an offline-first Android APK for students.

---

## 🎯 Target User & Main Purpose

- **Target Users**: High School, Senior High School, and College/University students (especially in the Philippines / APAC using USJ-R `1.00–5.00` or standard `0–100%` grading scales).
- **Main Purpose**: An all-in-one **AI Study Guide, OCR Text Scanner, PDF Layout Visualizer, YouTube Voice/Lecture Summarizer, and Active Recall Exam Simulator** that turns raw lecture materials (camera photos, PDFs, YouTube talking videos, or raw notes) into printable study guides, flashcards, and adaptive quizzes—even when offline or on slow mobile data.

---

## 1. Why Google Cloud Run (Replacing Laggy Free-Tier Cold Starts)

Previously, hosting exclusively on Render's free tier caused 45–90 second spin-up delays after 15 minutes of inactivity, leading to mobile request timeouts and UI hangs during simulations or AI queries.

Moving the primary backend deployment to **Google Cloud Run (`asia-southeast1`)** provides:
- **Sub-100ms Regional Latency** for APAC/Philippines students.
- **CPU Startup Boost & Concurrency (80 requests/instance)** with built-in Google Front End (GFE) global load balancing and TLS termination.
- **Multi-Endpoint Failover in Mobile (`ApiClient`)**: The app automatically probes Cloud Run (`https://studyapp-api-51772-as.a.run.app`) and Render (`https://study-app-b0xq.onrender.com`) with a 1.8s health check, and falls back to instant local on-device AI/simulation engines if the student has no internet.

---

## 2. One-Command Google Cloud Run Deployment

### Option A: Automated PowerShell Script
From the repository root, run:
```powershell
.\deploy_cloudrun.ps1 -ProjectId "studyapp-51772" -Region "asia-southeast1" -BuildApk
```

### Option B: Google Cloud Build (`cloudbuild.yaml`)
```bash
gcloud builds submit --config cloudbuild.yaml --project=studyapp-51772
```

### Required Environment Variables / Secrets in Cloud Run
Configure these in **Google Cloud Console -> Cloud Run -> studyapp-api -> Edit & Deploy New Revision -> Variables & Secrets**:

| Variable | Value / Purpose |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `Jwt__Secret` | 32+ character cryptographic signing secret |
| `Gemini__ApiKey` | Server-side Gemini API key (`AIza...`) — never shipped in the mobile APK |
| `GoogleAuth__ClientId` | Web OAuth Client ID (`469952719729-hff18jdd98k92v4df57tkn107fb0f4g5.apps.googleusercontent.com`) |
| `DATABASE_URL` | Managed PostgreSQL URI (e.g., Cloud SQL / Neon / Supabase) or persistent volume SQLite |

---

## 3. Security Architecture

- **Zero Client Secrets**: The Flutter mobile app contains **no** AI API keys or database credentials.
- **Verified Google OAuth**: `AuthController` verifies Google ID tokens cryptographically via `GoogleJsonWebSignature.ValidateAsync` with Audience validation.
- **Rate Limiting & Input Sanitization**: Sliding-window rate limiters protect `/api/v1/auth/*` and `/api/v1/ai/*` endpoints from abuse.

---

## 4. Building & Distributing the Android APK

To build the release APK pointed at your Cloud Run service:
```powershell
cd mobile
flutter build apk --release --dart-define=API_BASE_URL=https://studyapp-api-51772-as.a.run.app
```
The compiled APK is saved to:
- `StudyApp-release.apk` (repository root)
- `mobile/build/app/outputs/flutter-apk/app-release.apk`
