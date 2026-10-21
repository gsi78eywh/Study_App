# 20-user StudyApp pilot

## Goal

Verify that a new learner can register, complete the short guide, create or load study material, practice, and return to the app without login or data-loss problems.

## Invite message

> You are invited to test the StudyApp Android beta. Download the APK from the GitHub release, install it, create a test account, and use it for one short study session. Please do not upload confidential material. Send feedback using the questions below.

## Suggested test script (10–15 minutes)

1. Download and install `app-release.apk` from the GitHub Release.
2. Open the app, register, and complete or skip the three-step guide.
3. Create one course.
4. Paste non-confidential sample notes into AI Studio or load the starter content.
5. Open flashcards or a quiz and complete at least three answers.
6. Close and reopen the app; confirm the account and created content are still available.
7. Submit feedback.

## Feedback questions

1. Device model and Android version:
2. Could you install and sign in? If not, what happened?
3. Did the guide make the first steps clear? What was confusing?
4. Which action felt slow or failed?
5. Did any screen look crowded, dark, or difficult to read?
6. Did your course and study content remain after reopening the app?
7. Rate the experience from 1–5 and describe the main reason.
8. May we contact you for one follow-up question? (Yes/No)

## Triage rules

- Treat sign-in failures, lost work, inability to load content, and crashes as critical.
- Record the tester's device, approximate time, action, screenshot, and account email only with their consent.
- Do not request passwords, API keys, or private study files.
- Review feedback daily while the pilot is active and publish fixes as a new versioned release.
