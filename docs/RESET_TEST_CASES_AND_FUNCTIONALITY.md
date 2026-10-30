# StudyApp Reset Test Cases & Functionality Verification Guide

**Release Version:** 1.0.0-beta.2  
**Updated:** October 30, 2026  
**Status:** Verified & Deployed  
**Target Environments:**
- **Live Web App:** [https://studyapp-51772.web.app](https://studyapp-51772.web.app) (Firebase Hosting)
- **Live Production API:** [https://study-app-b0xq.onrender.com](https://study-app-b0xq.onrender.com)
- **Android Release APK:** `StudyApp-release.apk` (Root directory & GitHub Releases)
- **Active Keep-Alive Monitoring:** `.github/workflows/keep-backend-awake.yml`

---

## 1. Release Architecture & UI Updates (UnionBank Standard)

The user experience has been redesigned following global edtech and clean banking standards (inspired by UnionBank's intuitive, minimal, and high-impact design):

1. **Direct Exam Redirection (Eliminating Workflow Friction):**
   - When a student pastes lecture notes, uploads a PDF, or scans textbook photos in the Ingestion Studio, StudyApp synthesizes the study set and immediately redirects the user into the **Exam Simulation (`QuizPlayerScreen`)**.
   - Students no longer get stranded back on the home dashboard wondering where their quiz went.

2. **Elimination of Obsolete "Socratic AI Tutor Check-in":**
   - Removed the obsolete "4. Socratic AI Tutor Check-in" from featured study plans, backend API responses (`PracticeController.cs`), adaptive models (`adaptive_models.dart`), and UI learning sequences (`today_study_plan_widget.dart`).
   - Learning sequences are renumbered sequentially and display total active review time without dead steps.

3. **Topic Mastery Deduplication & Anti-Clipping:**
   - Topic Mastery Priorities deduplicate identical topic names (e.g., `USER MANUAL - INTERNAL` displays once with its highest priority mastery score).
   - "Start Session" buttons are formatted as `"Start Session • XX min"` with text ellipsis wrapping, ensuring zero button collision on narrow mobile viewports.

4. **Clutter-Free Dashboard (No Struck-Through Checklists or Excessive Banners):**
   - Removed the `First-Run Setup Checklist` from the home screen.
   - Streamlined the Quick Actions hub into 4 primary actions: `[Add Notes]`, `[Take Exam]`, `[Flashcards]`, and `[Courses]`, with horizontal utility pills for `[Grade Tracker]`, `[Study Plan]`, and `[Quick Guide]`.
   - Child Safety & 20-20-20 Eye Rest banner is concealed for standard College Mode students to preserve clean study space, remaining accessible anytime via the Profile / Account menu and Settings.

---

## 2. Reset Test Cases (RTC)

These test cases allow QA testers, developers, and pilot students to reset the app state to an absolute clean baseline and verify end-to-end functionality.

### RTC-1: Web Browser State & Service Worker Cache Reset
*Goal:* Ensure the web client downloads the latest JavaScript bundle from Firebase Hosting without cached artifacts.
1. Open Google Chrome, Edge, or Safari and navigate to `https://studyapp-51772.web.app`.
2. Open Developer Tools (`F12` or `Ctrl+Shift+I`).
3. Go to the **Application** tab (or **Storage** tab in Firefox/Safari).
4. Select **Clear storage** on the left menu.
5. Check all boxes:
   - *Unregister service workers*
   - *Storage (Local storage, Session storage, IndexedDB, Web SQL)*
   - *Cache storage*
6. Click **Clear site data**.
7. Hard reload the page (`Ctrl+F5` or `Cmd+Shift+R`).
*Expected Result:*
- The app loads fresh without stale code.
- No cached login tokens or old checklist items appear.
- Redirects cleanly to the modern login screen.

---

### RTC-2: Android App Storage & Local Cache Reset
*Goal:* Test the Android release APK from a factory-fresh installation state.
1. On your Android device, go to **Settings > Apps > StudyApp**.
2. Tap **Storage & cache**.
3. Tap **Clear Cache**, then tap **Clear Storage** (or **Clear Data**).
4. Alternatively, uninstall any existing build and install `StudyApp-release.apk`.
5. Launch StudyApp.
*Expected Result:*
- Splash screen displays smoothly with the green-themed leaf logo.
- User is prompted to sign in with Google or Email.
- No cached study sets or offline questions remain.

---

### RTC-3: Fresh User Onboarding & School Stage Initialization
*Goal:* Verify that a newly registered user completes onboarding without text collisions.
1. Sign in with a new Google Account or create an email account (e.g., `tester_student@example.com`).
2. The 4-step walkthrough modal appears.
3. Verify that Slide 1 shows `"STEP 1 OF 4"` and the `"Skip →"` button on the right edge without overlapping.
4. Advance through Slides 1 to 3:
   - Slide 1: *Add or Scan Study Material*
   - Slide 2: *Preview Actual PDF Layout*
   - Slide 3: *Create Accurate Exams Instantly*
5. On Slide 4, select **College / University** and choose the **USJ-R (1.00 - 5.00)** grading scale.
6. Tap **Start Studying**.
*Expected Result:*
- Modal closes smoothly and persists the preference to local preferences.
- Dashboard renders directly with zero checklist clutter.
- If no study sets exist, a clean empty state card displays: *"No Study Sets Yet • Create First Study Set"*.

---

### RTC-4: Backend Keep-Alive & Cold-Start Resilience
*Goal:* Ensure the Render backend stays awake or recovers cleanly from cold start without throwing unhandled exceptions.
1. Execute the health probe in PowerShell or terminal:
   ```bash
   curl -i https://study-app-b0xq.onrender.com/health
   ```
2. Verify HTTP response is `200 OK` with JSON body:
   ```json
   {"status":"healthy","database":"Healthy","timestamp":"..."}
   ```
3. Check the GitHub Actions keep-alive workflow at `.github/workflows/keep-backend-awake.yml`.
*Expected Result:*
- The cron ping executes every 10 minutes, keeping the Render service active and eliminating cold-start latency for students.

---

### RTC-5: Ingestion Studio to Instant Exam Simulation (Core Flow)
*Goal:* Verify that creating a study set automatically opens the exam without returning to the dashboard.
1. On the Home tab, tap **+ Add Notes** (or the empty state's **Create First Study Set**).
2. The **Ingestion Studio** opens.
3. Select course `GEN-101 (General Studies)`.
4. Set Title: `"Data Structures & Algorithms Overview"`.
5. In the Notes Editor, paste:
   ```text
   A stack is a Last-In, First-Out (LIFO) abstract data type where elements are added and removed from the same end, called the top. Common operations are push, pop, and peek.
   A queue is a First-In, First-Out (FIFO) data structure where elements are inserted at the rear (enqueue) and removed from the front (dequeue).
   A binary search tree (BST) maintains the invariant that left subtree keys are less than the root, and right subtree keys are greater than the root.
   ```
6. Tap **Generate Study Set & Exam**.
7. Observe the synthesis progress bar (Synthesis complete).
*Expected Result:*
- The Ingestion Studio closes and **automatically redirects straight into the Exam Simulator (`QuizPlayerScreen`)**.
- Questions are synthesized immediately from the pasted text.
- Multiple-choice questions, True/False, and Identification questions are ready to answer.

---

### RTC-6: Exam Scoring, Mistake Bank & Adaptive Plan Update
*Goal:* Verify that answering questions records metrics and updates the Mistake Bank.
1. In the active exam session:
   - Intentionally answer 1 question incorrectly.
   - Answer the remaining questions correctly.
2. Tap **Submit Exam**.
3. Verify the Summary Screen:
   - Displays percentage score, accuracy breakdown, and time spent.
   - Shows the incorrect question with an immediate option: **"Review in Mistake Bank"**.
4. Return to the Home tab.
*Expected Result:*
- The new study set `"Data Structures & Algorithms Overview"` appears under **Your Study Sets** with 1-tap buttons: `[Take Exam]` and `[Flashcards]`.
- The **Today's Study Plan** card updates:
  - Step 1: Review Flashcards
  - Step 2: Retrieval Practice / Weak-Spot Drill
  - Obsolete "Socratic AI Tutor Check-in" does **NOT** appear.
  - Mistake Bank badge shows `Mistakes (1)`.

---

### RTC-7: Offline Mode & Cache Rehydration
*Goal:* Verify that exam practice works seamlessly without an internet connection.
1. On either the Web app (offline mode in DevTools Network tab) or Android (Airplane Mode):
2. Tap **Take Exam** on any study set listed under **Your Study Sets**.
3. Answer all questions and submit.
*Expected Result:*
- Local questions load from the on-device cache without spinning or blank screens.
- Score is calculated client-side with offline rubric grading.
- Answers are queued in `SyncService` and synced automatically when connectivity returns.

---

## 3. Functionality Verification Matrix

| Feature | Component | Verification Criteria | Status |
| :--- | :--- | :--- | :--- |
| **Direct Exam Flow** | `dashboard_screen.dart` / `ingestion_screen.dart` | Set creation routes directly to `QuizPlayerScreen` | **PASSED** |
| **Socratic Removal** | `PracticeController.cs` & `adaptive_models.dart` | Step 4 tutor removed from backend and mobile models | **PASSED** |
| **Topic Deduplication** | `today_study_plan_widget.dart` | Duplicate topics filtered using normalized seen set | **PASSED** |
| **Anti-Clipping** | `today_study_plan_widget.dart` | Session button uses shortened label and ellipsis | **PASSED** |
| **Checklist Removal** | `dashboard_screen.dart` | Confusing struck-through checklist removed from Home | **PASSED** |
| **Child Safety Placement** | `dashboard_screen.dart` | Banner hidden on College Mode; moved to Account Menu | **PASSED** |
| **Account Menu Safety** | `_showAccountMenu` | Settings tile added for Study Mode & 20-20-20 Eye Care | **PASSED** |
| **Overflow Prevention** | `_showAccountMenu` | Modal wrapped in `SingleChildScrollView` to prevent flex errors | **PASSED** |
| **Automated Tests** | `uat_mobile_flow_test.dart` | All 16 unit and widget integration tests pass (100%) | **PASSED** |
| **Web Build** | `mobile/build/web` | Built with `--dart-define=API_BASE_URL` | **PASSED** |
| **Firebase Deploy** | `studyapp-51772.web.app` | Released live with no-cache service worker headers | **PASSED** |
| **Release APK** | `StudyApp-release.apk` | 30.5 MB release binary compiled with Gradle assembleRelease | **PASSED** |

---

## 4. Download & Access Links

- **Hosted Web App:** [https://studyapp-51772.web.app](https://studyapp-51772.web.app)
- **Production Backend:** [https://study-app-b0xq.onrender.com](https://study-app-b0xq.onrender.com)
- **Android APK File:** Located in repository root as `StudyApp-release.apk` (and `mobile/build/app/outputs/flutter-apk/app-release.apk`).
- **Release Verification Script:**
  ```powershell
  # Verify local release APK integrity
  Get-Item .\StudyApp-release.apk | Select-Object Name, Length, LastWriteTime
  ```
