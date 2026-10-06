# 📚 Study App

An adaptive, intelligent study companion designed for students of all educational levels—from primary elementary (Grades 1–6) and junior/senior high school (Grades 7–12) to collegiate and university academia.

Built with **Flutter (Dart)** on the client and **ASP.NET Core (.NET 10) + Entity Framework Core (SQLite)** on the backend.

---

## 🌟 Highlights & Key Features

* **Universal Multi-Year Learner Adaptation Engine**:
  * 🐣 **Elementary Learner (Grades 1–6)**: Junior Mode pediatric safety, 4th-grade simplified vocabulary, growth-mindset feedback, larger text scaling, and DSWD 20-20-20 eye wellness breaks.
  * 🎒 **Junior High School (Grades 7–10)**: Step-by-step conceptual foundations, interactive practice, formula definitions, and progressive hints.
  * 🔬 **Senior High School (Grades 11–12)**: Academic tracks (STEM, ABM, HUMSS, TVL), college entrance test readiness, and deep drills.
  * 🎓 **College & University**: Professional collegiate taxonomy, case study synthesis, and distraction-free study sprint layouts.
* **Pedagogical AI Tutor**: Socratic tutoring that automatically enriches prompts according to the active student developmental level.
* **Multi-Source Content Ingestion**: Ingest lecture materials via PDF/DOCX upload, Camera OCR notes, or YouTube video transcripts.
* **Spaced Repetition Flashcards**: SuperMemo SM-2 algorithm calculates personalized review intervals based on student recall quality.
* **Progressive Examination Studio**: Timed mock exams with server-side grading and real-time answer explanations.
* **Inclusive Accessibility**:
  * Dynamic dark/light theme switching with eye-friendly contrast.
  * Dyslexia-friendly typography toggle.
  * 3-stage typography scaling (Normal $1.0\times$, Large $1.2\times$, Extra Large $1.35\times$).
* **Hardened Security**:
  * Zero-trust OAuth authentication with dev-token sandbox guards.
  * Prevention of OAuth account takeover.
  * Protection against SQL injection and cross-site scripting.
  * Local storage encryption for tokens.

---

## 🛠️ Technology Stack

| Layer | Technology |
|---|---|
| **Mobile / Frontend** | Flutter 3.x, Material 3, Google Fonts, Dio |
| **Backend API** | ASP.NET Core (.NET 10), C# 13, Clean Architecture |
| **Database** | SQLite, Entity Framework Core 10 |
| **Security & Auth** | ASP.NET Identity, JWT Bearer Tokens, Google OAuth2 |
| **Testing** | xUnit, Flutter Test, Flutter Analyze |

---

## 🚀 Getting Started

### 1. Prerequisites
* [.NET 10 SDK](https://dotnet.microsoft.com/)
* [Flutter SDK 3.x](https://flutter.dev/)
* Chrome, Edge, or Windows build tools

### 2. Run Backend API
```bash
cd backend/src/StudyApp.Api
dotnet run --launch-profile http
```
The API starts at `http://localhost:5000` with the health probe at `http://localhost:5000/health`.

### 3. Run Mobile / Web Client
```bash
cd mobile
flutter run -d chrome --web-port 5050
# or for Windows desktop:
flutter run -d windows
```

---

## 🧪 Testing & Quality Assurance

### Run Backend Tests (215 Tests)
```bash
dotnet test backend/StudyApp.sln
```

### Run Frontend Tests (80 Tests across 18 Suites)
```bash
cd mobile
flutter test
```

### Run Static Analysis
```bash
cd mobile
flutter analyze
```

---

## 📖 In-Depth Documentation

For detailed architectural diagrams, bit-by-bit workflows, security defense implementations, and testing matrices, see:
* [Implementation & Fixes Guide](docs/IMPLEMENTATION_AND_FIXES.md)
