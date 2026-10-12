# StudyApp Product Process, Security, Deployment, and UI Roadmap

**Status:** Proposed delivery plan  
**Product target:** Android APK beta first; web remains a supported secondary target.  
**Architecture recommendation:** Keep the current ASP.NET Core API and move it to Cloud Run; use Firebase Hosting for the web client and Firebase Auth for identity. Use Cloud SQL for durable production data. This is the lower-rewrite path for the existing .NET API. A full Firestore rewrite is a separate architecture decision, not a prerequisite for beta.

This is a plan, not a claim that the controls or features below already exist. The repository currently contains a Flutter client, an ASP.NET Core API, EF Core with SQLite, and a Firebase Hosting configuration for the web build. The release process must close the gaps between that current state and the target architecture.

## 1. Product purpose and decision rules

StudyApp turns a student's own course material into a reliable study routine: capture material, review extracted text, generate grounded practice, grade answers honestly, then use results to schedule what to study next.

Apply these rules across screens and services:

1. Say what the evidence supports. Use “Matches your notes” with a source snippet, never “100% Correct” or “Verified.”
2. Render only real data. If a student has no attempts, due cards, or readiness history, show an empty state instead of a sample number.
3. Require a student review step between extraction and generation.
4. Use one learning record as the source of truth for attempts, mistakes, cards, mastery, readiness, and Home summaries.
5. Keep secrets and development-only authentication out of release artifacts.
6. Every generated answer should be traceable to the student's material and open to correction or reporting.

## 2. End-to-end student process

1. **Create an account:** Email/password or real Google OAuth through Firebase Auth. Verify email before AI actions. Present explicit consent and short privacy summaries with links to full policies. Until a valid age gate and verifiable parental-consent process exist, hide Junior Learner Mode and restrict the beta to the supported age group.
2. **Set up a course:** Ask for only the course name and optional exam date. The exam date drives a daily workload recommendation; do not show readiness or a streak before there is enough activity to calculate them.
3. **Add material:** A prominent **+ Add material** action accepts a PDF, image/paste-image, supported document, pasted transcript, or supported video source. Explain source and personal-data handling before upload. Validate file type by content, size, and limits; allow cancel and retry.
4. **Extract and review:** Detect source type and language; extract; clean while preserving structure and timestamps; calculate quality; display source and extracted text together; let the student edit, accept, or discard. Block or warn when text is under 200 characters or fails quality/suitability checks.
5. **Generate a draft set:** Generate structured questions/cards from reviewed text, verify each source snippet against that text, check answer support, deduplicate against the student's sets, and show topic coverage and session composition. Student can edit, delete, report, or approve items before saving.
6. **Practice and grade:** Every submitted answer receives an explicit right/incorrect verdict, including short answers. Show “Mark my answer correct” when grading is disputed and “Report incorrect answer” for bad generated content. Show citations/snippets with each item.
7. **Close the learning loop:** An attempt updates the shared learning record. A wrong answer creates a topic-tagged mistake entry, identifies concept vs. likely careless error where possible, marks linked cards for practice, schedules a retest, and updates readiness and Home. Do not assert an update until persistence succeeds; show a retryable error if sync fails.
8. **Review results:** Show missed questions with the student's answer, expected answer, rationale, and source; offer Retry missed; show topic breakdown and comparison with the last attempt only when one exists. Use specific, encouraging next steps.

## 3. Material ingestion and question quality

Use one pipeline for every source:

**Add source → detect type/language → extract → clean → quality gate → review/edit → generate → verify → approve/save**

### Image and OCR

- Use Gemini vision as the primary image extractor. If a fallback OCR engine is retained, preprocess with upscale, grayscale, contrast adjustment/inversion as appropriate, and thresholding.
- Support paste-image and show the original image beside editable extracted text.
- Label confidence and uncertainty plainly. “Clean” is reserved for text that passes the configured quality checks and student review.
- Benchmark dark-mode screenshots, handwriting, Filipino, Cebuano, and mixed-language images.

### YouTube and audio

- Label creator-provided captions separately from auto-generated captions; preserve timestamps and disclose likely transcription errors.
- Detect content type before assigning roles such as instructor. Remove claims such as “Verified Audio Content” and “Complete Song Lyrics.”
- Normalize transcripts by stripping configured music tags, deduplicating overlaps, and merging sentence fragments without losing timestamps.
- Do not ingest lyric sites. Provide paste-transcript and user-authorized audio upload as fallbacks when captions are unavailable. Warn that Cebuano and other low-resource-language transcripts may be less reliable.
- Treat URL fetching as an SSRF boundary: allow only HTTP(S), block private/reserved IP ranges at resolution and connection time, cap redirects and response size, and run it in an isolated worker.

### PDFs and documents

- Preserve headings, paragraph breaks, lists, and tables; represent extracted structure as Markdown. Strip repeated headers, footers, and page numbers.
- Detect pages with little/no selectable text and route those pages through vision OCR.
- Chunk by section and retain page/section references for citations and broad topic coverage.
- Flag content that appears personal or administrative rather than teachable, preview detected topics, and warn about personal data before processing.

### Quality gate and generated content

- Make the 200-character minimum visible. Score extraction using available confidence, dictionary-word ratio, and odd-symbol ratio; set thresholds from the benchmark, not intuition alone.
- Block empty or unusable text; warn and require explicit review for borderline or low-resource language results. Record the score and extractor/model version for evaluation without logging source contents.
- Generate schema-validated JSON containing question, answer, distractors where applicable, rationale, topic, concept, and exact source snippet/reference.
- Require every snippet to exist in the reviewed source. Run an independent answer-support check and drop unsupported items; deduplicate against existing items before showing drafts.
- Questions stand alone and test concepts rather than source trivia. Rationales explain the concept. Flashcards are atomic; list content becomes multiple cards or cloze prompts, and the answer side carries context.
- Keep content as untrusted input: separate it from instructions, give the model no tools, and render responses as plain text or sanitized Markdown. Add a verification pass for code answers; never call unsafe HTML rendering safe.

## 4. Shared learning data and study logic

Create a canonical API-owned learning record. Suggested core entities are `Course`, `Material`, `ExtractionJob`, `StudySet`, `Question`, `Flashcard`, `StudySession`, `AnswerAttempt`, `Mistake`, and `ReviewSchedule`. Every record belongs to an authenticated user; generated artifacts reference their source material and version.

Use server-side, idempotent writes for attempts and review events. Keep a durable event/history trail so retries do not create duplicate mistakes or inflate counts. Home, Mistake Bank, cards, readiness, and results read from these same records through consistent API responses.

- Implement SM-2 or FSRS with per-card review state and next-due time. Persist the algorithm version and rating; rating controls appear after a card is flipped. Include a New bucket in mastery.
- Define readiness and mastery in product documentation and expose the formula on tap. A first implementation can use recency-weighted accuracy by topic with decay, but do not display a score until minimum evidence exists.
- Use exam date and available study time to allocate due reviews and weak-topic practice. Recompute the plan when the date or observed performance changes.
- Make dashboard counts derive from the same query/aggregation and timestamp. For example, “Last: 40%, 3 due” must reconcile with the attempt and due-card records.
- Support conflict-safe sync before offline mode. Later offline writes should use IDs/idempotency keys and a visible pending-sync state.

## 5. Navigation and interface recommendations

Use five primary destinations: **Home · Practice · Library · Tutor · Profile**. Replace Studio as a tab with a prominent **+ Add material** action. Remove duplicate “Quick Study Hub” and duplicate Scan entry points. Keep notifications and avatar in the header.

- New users get a first-run checklist: **Add course → Add material → Generate a set → Take first quiz**. Each step deep-links to its action and becomes complete only after persisted data confirms it.
- Readiness and streak modules appear only after sufficient real records exist. Otherwise show the next checklist action or a useful empty state.
- Show question count, format, duration, and topic composition before a session starts. Resolve all count discrepancies from one server-authoritative session manifest.
- Explain rapid processing as **“Faster, fewer questions”** and show the expected trade-off before selection.
- Use one brand color, semantic success/warning/error colors, and clear primary/secondary/tertiary button styles. Use icons or emoji in a label, not both.
- Meet WCAG AA contrast, keep text at least 12 px, touch targets at least 44 px, label icon-only controls, and show keyboard focus. Support system/light/dark appearance, text scaling, and dyslexia preferences consistently.
- Fix login-card, Studio/header, and long-answer overflow. Review 360, 390, and 430 px widths, safe areas, keyboard-open layouts, and landscape. Include loading, empty, offline, and error/retry states on every async feature.
- Confirm or allow undo for destructive card actions; use inline editing for routine edits. Show keyboard shortcut hints on desktop only.
- Split settings into Study, Reminders, Accessibility, Account, and Privacy. Remove duplicate education-stage settings, use one save model (autosave or explicit unsaved state), and replace unlabeled sliders with named steppers/options.
- Remove “Academic Remix / Reverse Recall” unless the feature has a plain-language explanation and demonstrated study value.

## 6. Recommended deployment architecture

The repository already has an ASP.NET Core API and EF Core/SQLite. For a production service, do not rely on a SQLite file inside an ephemeral Cloud Run container. Keep the API and migrate persistence to Cloud SQL for PostgreSQL (or another managed durable database) before production. Firebase Auth handles sign-in; the API validates Firebase ID tokens and enforces ownership. This removes the need to issue custom JWTs while preserving the existing domain/API structure.

| Component | Development | Staging | Production |
|---|---|---|---|
| Firebase project | `studyapp-dev` | `studyapp-staging` | `studyapp-prod` |
| Auth / OAuth | Isolated test users | Tester allowlist | Public policy-controlled signup |
| API | Local .NET API | Cloud Run staging service | Cloud Run production service |
| Database | Local disposable DB | Dedicated staging Cloud SQL | Dedicated production Cloud SQL |
| AI credentials | Local secret injection | Staging Secret Manager secret/quota | Production Secret Manager secret/quota |
| Web | Local Flutter | Firebase Hosting preview/channel | Firebase Hosting production |
| Files | Local/test storage | Private staging bucket | Private production bucket |

Firebase Hosting can serve Flutter Web and route `/api/**` to Cloud Run if domain routing is useful. Android calls the HTTPS API directly. Firebase config identifiers in a Flutter client are not secrets; provider keys and Gemini credentials are. Use separate OAuth clients, quotas, data, and secrets for each environment. Never point testers at production data.

Before creating databases/buckets, choose regions based on latency, supported services, residency commitments, and the privacy notice. Set budgets and alerts at project level, then implement a server-side AI kill switch and quota enforcement; budget alerts alone do not cap usage.

## 7. Security, privacy, and operations controls

### Identity and authorization

- Firebase Auth: real Google OAuth, verified email, password reset, rate limits/abuse controls, and a documented password policy. Consider MFA and revoke-all-sessions for later hardening.
- API validates Firebase ID tokens, checks email verification for AI actions, and authorizes every resource by owner ID on every request. Never trust a client-supplied user ID.
- Remove simulated sign-in, demo student accounts, and debug bypasses from release builds. Prefer compile-time exclusion plus CI artifact scanning; a server environment check alone is insufficient.
- Store native session material only in platform secure storage. Do not put bearer tokens in browser localStorage; for web, use a same-site, Secure, HttpOnly session cookie/BFF pattern where practical.
- Use re-authentication for account deletion and other sensitive account changes.

### API, AI, and uploads

- Keep Gemini credentials in Secret Manager and call the model from the backend. Apply per-user quotas, request-size limits, timeouts, cancellation, retry policy, caching where safe, and cost monitoring.
- Apply App Check where supported and validated, but treat it as an additional abuse signal, not a replacement for authentication/authorization.
- Validate input schemas and file contents server-side. Set upload size/type limits, malware scanning, private buckets, short-lived signed access, and lifecycle deletion.
- Never log tokens, document/transcript text, answer content, or unnecessary personal data. Scrub structured logs and crash reports; disclose analytics/crash processors accurately.
- Keep AI output marked as potentially wrong, cited to student material, and reportable. No model or extractor claim should exceed measured evidence.

### Data protection and resilience

- For the Philippines launch, prepare a RA 10173-aligned privacy program: identify controller/DPO contact, processors (Google and hosting providers), purposes, retention periods, access/correction/deletion workflow, breach response, and NPC registration assessment. Have local counsel review obligations and public notices.
- Verify data-use and model-training statements against the exact Gemini service/plan terms. Do not claim “zero third-party tracking” if crash reporting or analytics is enabled.
- Warn before personal documents are uploaded; do not use student material for unrelated training without valid consent and a documented basis.
- Define retention and deletion for materials, derived questions, chat, logs, and deleted accounts. Use scheduled deletion/TTL only after confirming dependencies and legal retention requirements.
- Use versioned database migrations, automated backups, and a tested restore procedure. Define RPO/RTO targets before production. Keep an incident runbook for key revocation, AI shutoff, account/session response, restoration, and user/regulator notification.

## 8. Build and release process

### Pull request and CI

1. Format/lint Flutter and .NET; run unit/integration tests for scoring, scheduling, ownership, sync/idempotency, extraction gates, and the core learning flow.
2. Run Firebase Auth/API ownership and security-rule tests, including user A cannot read or mutate user B's data. Use Firebase Emulator Suite for Firebase rules and services that are actually deployed.
3. Run dependency, secret, and release-configuration scans. Assert that debug login/demo paths and keys are absent from release artifacts.
4. Build signed/obfuscated Android artifacts and Flutter Web with environment-specific API configuration. Keep symbol files securely for crash diagnosis.
5. Deploy API, migrations, rules, storage policies, and web to staging. Run smoke tests using tester accounts and non-production data.

### Staging acceptance flow

On a real supported phone, verify: sign up → verify email → add course → upload/paste material → extraction review/edit → quality warning/block → generate and approve a set → start a session with accurate counts → submit correct and incorrect answers → review citations → retry missed → verify Mistake Bank, cards, readiness, and Home reconcile → delete account and confirm deletion behavior.

Also verify low-quality input, cancel/retry, network loss, keyboard/safe-area layouts, accessibility basics, rate limits, quota exhaustion, AI kill switch, and that logs contain no source text or tokens.

### Beta and production promotion

- Start invite-only with 10–20 testers on staging, feedback/reporting enabled, published beta/privacy notice, documented known issues, and a support contact.
- Promote the same reviewed code and migration set through production after acceptance sign-off. Use gradual rollout (e.g. 5% → 25% → 100%) where the distribution channel supports it; monitor crashes, API errors, quota/cost, extraction quality, and user-reported content issues.
- For Android, configure package ID, release SHA-1/SHA-256 for Google sign-in, protected signing key backups, Play App Signing, minimum version handling, and Play data-safety disclosures. Set `usesCleartextTraffic=false` and disable backup for sensitive app data where compatible with the recovery design.
- For web, build with the production API origin, deploy Flutter output to Firebase Hosting, and confirm `/api/**` routing/CORS and browser session protections.
- Maintain feature flags and a kill switch for AI/generation. Roll back application versions safely; use backward-compatible migrations and explicit forward-fix plans for schema changes.

## 9. Roadmap and release gates

### Phase 0 — Trust and release baseline (beta blocker)

- Remove fake dashboard/sample numbers and demo/simulated auth/debug release paths.
- Remove overclaims (“100% Correct,” “Verified,” “Complete Lyrics”) and show honest source labels.
- Fix the core overflow/layout failures and establish loading, empty, and error states.
- Choose Firebase Auth + Cloud Run hybrid; document identity/data migration and move production persistence off container-local SQLite.

**Gate:** release build has no demo/debug auth, no fake metrics, and no unresolved critical security findings.

### Phase 1 — Trustworthy core study loop (beta blocker)

- Build one extraction/review/quality pipeline with visible 200-character threshold and citations.
- Validate and verify generated questions, source snippets, answer verdicts, count consistency, and result review.
- Persist attempts and connect mistakes, flashcards, readiness, and Home through the shared learning record.
- Make onboarding checklist and empty states data-driven.

**Gate:** a new tester can finish sign-up through a graded quiz without a dead end; wrong answers visibly update the connected learning features.

### Phase 2 — Secure staging and controlled beta

- Configure isolated dev/staging/prod projects, Firebase Auth, Cloud Run, managed DB, secrets, quotas, App Check rollout, storage validation, rules/ownership tests, backup and restore, and monitoring.
- Run extraction benchmark and AI quality evaluation; set and publish internal acceptance thresholds before expanding beta.
- Complete privacy notice, consent, age-scope decision, deletion workflow, and support/incident process.

**Gate:** staging smoke flow passes on real devices, user isolation tests pass, and costs/quotas and incident controls are observable.

### Phase 3 — Adaptive study and accessibility

- Ship measured SM-2/FSRS scheduling, topic-level readiness/mastery definitions, exam-date plan, due workload, and comparison to prior attempts.
- Complete 360/390/430 px, safe-area, keyboard-open, landscape, text scaling, contrast, touch target, keyboard focus, and screen-reader review.
- Improve PDF section structure, transcript normalization, low-resource language handling, and topic coverage using benchmark results.

**Gate:** scheduling behaves deterministically under tests, explanations are discoverable, and accessibility review has no release-blocking issue.

### Phase 4 — Public release and operations maturity

- Complete store compliance, production rollout, monitoring, restore exercise, incident drill, API versioning, staged rollout, and privacy/legal review.
- Add operational dashboards for crash-free sessions, job completion/failure, extractor benchmark drift, generation support rate, reported questions, quota/cost, and sync failures, using aggregated or scrubbed data.

### Future enhancements (after core reliability)

- **Near term:** offline study with local database and idempotent sync; Anki/CSV import-export; weak-topic drills; tap-to-highlight source passages.
- **Mid term:** Filipino and Cebuano interface/generation improvements; shared teacher/class sets with moderation; timed past-exam simulation; habit-based reminders with quiet hours; voice answers and handwriting support.
- **Longer term:** opt-in study groups; teacher/school dashboards with strict consent and roles; stronger-model routing for difficult tutoring/verification after cost and quality measurement; paid tiers only after cost per active learner is understood.
- Keep Junior Learner Mode deferred until age assurance, verifiable parental consent, safeguarding, and applicable legal review are implemented.

## 10. Measurable acceptance checklist

- [ ] A new user can go from account creation to a graded quiz without hitting a dead end.
- [ ] Every visible count, score, streak, and readiness value comes from real persisted data and has a defined calculation.
- [ ] Low-quality or unsuitable input is caught before generation; the extraction minimum and source confidence are visible.
- [ ] Every generated answer has a source snippet, a right/incorrect verdict, and a report path.
- [ ] A wrong answer updates the shared attempt record, Mistake Bank, linked cards, due schedule, readiness, and Home consistently.
- [ ] Debug, demo, simulated-auth, secrets, and localhost endpoints are absent from release artifacts.
- [ ] Cross-user ownership tests pass; backups restore; quota, kill switch, and incident response are exercised.
- [ ] Extraction benchmark covers 20–30 known-answer images/videos including dark screenshots, handwriting, Filipino/Cebuano, and music video; CER/WER and usability thresholds are set and rerun after extractor/model changes.
- [ ] Release process states the delivery target, privacy disclosures, age scope, supported platforms, and rollback owner.

