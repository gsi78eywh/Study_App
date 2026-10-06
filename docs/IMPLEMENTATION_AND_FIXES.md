# Technical Implementation, Architectural Workflows & Security Defenses

This document provides a comprehensive, bit-by-bit technical record of all bug fixes, architecture workflows, accessibility enhancements, security hardening, and test suites implemented in the **Study App** platform.

---

## 1. Executive Summary of Implementations & Fixes

### A. Unfinished Commit & Regression Fixes
* **Resolved Incomplete Commit `5b187ce` ("later to continue")**:
  - `mobile/lib/features/auth/widgets/google_sign_in_dialog.dart`: Resolved broken imports (`app_colors.dart`, `theme_extensions.dart`), added email format validation via RFC 5322 regex, autofill hints, accessible semantics, and debug-only execution guards.
  - `mobile/lib/features/auth/screens/login_screen.dart`: Eliminated navigation deduplication race conditions on Google Sign-In; restored top-right Theme Toggle button with accessible tooltips; wired the local dialog strictly when `GoogleSignInDialog.isAvailable`.
  - `mobile/lib/features/courses/screens/dashboard_screen.dart`: Removed redundant double-fetch in `_openGoogleSignInModal()`, cleaned up unused variables, and updated badge display to support all student stages.

### B. Theme & Visual Accessibility Restoration
* **Restored Full Dark / Light Mode Support**:
  - `mobile/lib/core/services/session_service.dart`: Restored persistent `themeMode` key saving and loading.
  - `mobile/lib/core/theme/theme_controller.dart`: Restored dynamic theme toggling with notification dispatch.
  - `mobile/lib/core/theme/app_theme.dart`: Restored complete `AppTheme.darkTheme` palette, high-contrast typography, and dynamic `ThemeHelper.isDarkMode`.
  - `mobile/lib/main.dart`: Wired `darkTheme` and `themeMode: widget.themeController.themeMode` into `MaterialApp`.

### C. Multi-Year Student Accessibility Engine (Grades 1–12 & College)
* **4 Distinct Educational Stages**:
  - **Elementary (Grades 1–6)**: Junior Mode guardrails, gentle growth-mindset feedback, 1.2x font scale default, audio read-aloud affordances, and DSWD 20-20-20 pediatric eye break reminders.
  - **Junior High School (Grades 7–10)**: Foundational logic, step-by-step math/science explanations, and progressive disclosure cards.
  - **Senior High School (Grades 11–12)**: Track specialization (STEM, ABM, HUMSS, TVL), college entrance exam drills, and formula syntax rendering.
  - **College & University**: Collegiate taxonomy, unconstrained academic rigor, distraction-free study sprint layouts.
* **Pedagogical AI Prompt Enrichment**: In `child_safety_service.dart`, the tutor automatically adapts question complexity and explanations based on the student's active developmental level.
* **Dyslexia & Low-Vision Support**: OpenDyslexic-styled typography switch and smooth 3-stage text scaling ($1.0\times$, $1.2\times$, $1.35\times$).

### D. Critical Security Hardening
* **Eliminated Dev-Token Account Takeover**: In `AuthController.cs`, unverified `dev-google:` / `google-direct:` bypass tokens are strictly forbidden outside `IsDevelopment()`. In production, any unverified token returns `401 Unauthorized`.
* **OAuth Identity Decoupling**: Fabricated dev tokens set `Subject = null`, preventing test tokens from overriding or hijacking genuine Google accounts.
* **Boundary Validation**: Added strict email format validation and name truncation guards.
* **Dedicated Security Tests**: Added 18 unit tests in `GoogleAuthBypassSecurityTests.cs` verifying production token rejection, parameter boundaries, and error response consistency.

---

## 2. Architectural Design & Component Map

```
Study_App/
├── backend/
│   ├── src/
│   │   ├── StudyApp.Domain/              # Enterprise Domain Entities (User, Course, Flashcard, Quiz, Question)
│   │   ├── StudyApp.Application/         # CQRS / Service Layer, DTOs & Interfaces
│   │   ├── StudyApp.Infrastructure/      # Database (EF Core / SQLite), JwtTokenGenerator, AiServices
│   │   └── StudyApp.Api/                 # REST Controllers (Auth, Courses, Ingestion), Middleware, Program.cs
│   └── tests/
│       └── StudyApp.UnitTests/           # 215 Unit & Security Tests
└── mobile/
    ├── lib/
    │   ├── core/
    │   │   ├── network/                  # ApiClient, Interceptors, Base URLs
    │   │   ├── services/                 # ChildSafetyService, SessionService, SyncService
    │   │   └── theme/                    # AppTheme, ThemeController
    │   ├── features/
    │   │   ├── ai_tutor/                 # AI Tutor Screen & Stage Prompt Chips
    │   │   ├── auth/                     # Login, Registration, Google Sign-In Dialog
    │   │   ├── courses/                  # Course Catalog, Dashboard with 4-Tier Mode Selector
    │   │   ├── exam_studio/              # Progressive Exam Studio, Timed Quizzes
    │   │   ├── flashcards/               # Spaced Repetition (SM-2) Flashcards
    │   │   └── settings/                 # Accessibility Settings (Font Scaling, Dyslexia Font)
    │   └── main.dart                     # App Bootstrap & Theme Wiring
    └── test/                             # 18 Test Suites (80 Tests Total)
```

---

## 3. Bit-by-Bit Operational Workflows

### 3.1 Authentication & Session Lifecycle
1. **Student Login**: Student inputs credentials or selects Google Sign-In.
2. **Token Verification**:
   - In production, Google ID Tokens are verified against Google's OAuth2 certs.
   - In local development, `dev-google:email` bypass is permitted strictly when `ASPNETCORE_ENVIRONMENT=Development`.
3. **Session Establishment**: Server issues a signed JWT Bearer Token (containing User ID, Email, Role claims) and Refresh Token.
4. **Client Persistence**: Mobile client stores JWT securely and initializes `SessionService`.

### 3.2 Multi-Year Learner Adaptation Workflow
1. **Stage Configuration**: Student or parent sets learning stage from the dashboard chip or Settings screen:
   - Elementary (Grades 1–6)
   - Junior High (Grades 7–10)
   - Senior High (Grades 11–12)
   - College / University
2. **AI Tutor Query**: When a student asks a question in the AI Tutor:
   - `ChildSafetyService.enrichPromptForGradeLevel()` inspects the active stage.
   - Elementary prepends pediatric guardrails and 4th-grade vocabulary instructions.
   - Junior High injects step-by-step foundational scaffolding instructions.
   - Senior High injects collegiate exam preparation and synthesis instructions.
   - College sends the prompt unconstrained for maximum depth.
3. **Screen Wellness**: Elementary mode enforces the DSWD 20-20-20 rule, notifying the learner every 20 minutes to rest their eyes.

### 3.3 Study Material Ingestion Pipeline
1. **Capture**: Student uploads a PDF/DOCX lecture document, captures handwritten notes via Camera OCR, or submits a YouTube URL.
2. **Text Parsing & Sanitization**: The backend extracts clean text, strips advertising/sponsorship markers, and partitions into semantic chunks.
3. **Synthesis**: The AI engine converts content into summary notes, flashcard decks, and practice quiz questions.

### 3.4 Spaced Repetition (SuperMemo SM-2) Engine
Flashcard mastery intervals are calculated dynamically:
$$\text{Ease Factor}' = \text{Ease Factor} + (0.1 - (5 - q) \times (0.08 + (5 - q) \times 0.02))$$
- **Again (1)**: Card lapses; interval reset to 1 day.
- **Hard (2)**: Interval scaled by $1.2\times$.
- **Good (3)**: Normal interval progression based on current Ease Factor.
- **Easy (4)**: Bonus interval progression ($1.3\times$).

---

## 4. Verification & Testing Metrics

### Backend Test Results (.NET 10 xUnit)
```
Test run for StudyApp.UnitTests.dll (.NETCoreApp,Version=v10.0)
Total tests: 215
Passed: 215
Failed: 0
Skipped: 0
Duration: ~30s
Status: 100% PASSED
```

### Mobile Test Results (Flutter Test Runner)
```
Total test suites: 18
Total tests: 80
Passed: 80
Failed: 0
Duration: ~28s
Status: 100% PASSED
```

### Static Analysis (`flutter analyze`)
```
Analyzing mobile...
No issues found! (ran in 3.3s)
Status: 0 ERRORS, 0 WARNINGS
```
