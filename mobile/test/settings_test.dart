import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/theme/theme_controller.dart";
import "package:study_app_mobile/features/settings/models/study_settings_model.dart";
import "package:study_app_mobile/features/settings/screens/settings_screen.dart";
import "package:study_app_mobile/features/settings/services/settings_service.dart";

void main() {
  group("StudySettingsModel Unit Tests", () {
    test("StudySettingsModel defaults match academic evidence-based standards", () {
      final settings = StudySettingsModel.defaultSettings();

      expect(settings.defaultQuestionCount, 15);
      expect(settings.preferredStudyMode, 8); // SimulatedExam
      expect(settings.instantFeedback, true);
      expect(settings.shuffleOptions, true);
      expect(settings.dailyStudyGoalMinutes, 30);
      expect(settings.dailyQuestionTarget, 25);
      expect(settings.blitzSecondsPerQuestion, 10);
      expect(settings.pomodoroFocusMinutes, 25);
      expect(settings.pomodoroShortBreakMinutes, 5);
      expect(settings.pomodoroLongBreakMinutes, 15);
      expect(settings.defaultAiDifficulty, 2);
      expect(settings.themePreference, "system");
      expect(settings.soundEffectsEnabled, true);
      expect(settings.hapticFeedbackEnabled, true);
    });

    test("StudySettingsModel serialization and deserialization roundtrip", () {
      const original = StudySettingsModel(
        defaultQuestionCount: 20,
        preferredStudyMode: 2,
        instantFeedback: false,
        shuffleOptions: false,
        dailyStudyGoalMinutes: 45,
        dailyQuestionTarget: 30,
        blitzSecondsPerQuestion: 15,
        pomodoroFocusMinutes: 50,
        pomodoroShortBreakMinutes: 10,
        pomodoroLongBreakMinutes: 20,
        defaultAiDifficulty: 3,
        preferredQuestionTypes: "multiple_choice,cloze",
        soundEffectsEnabled: false,
        hapticFeedbackEnabled: false,
        themePreference: "dark",
      );

      final json = original.toJson();
      final restored = StudySettingsModel.fromJson(json);

      expect(restored.defaultQuestionCount, 20);
      expect(restored.preferredStudyMode, 2);
      expect(restored.instantFeedback, false);
      expect(restored.shuffleOptions, false);
      expect(restored.dailyStudyGoalMinutes, 45);
      expect(restored.blitzSecondsPerQuestion, 15);
      expect(restored.pomodoroFocusMinutes, 50);
      expect(restored.defaultAiDifficulty, 3);
      expect(restored.preferredQuestionTypes, "multiple_choice,cloze");
      expect(restored.themePreference, "dark");
    });

    test("StudySettingsModel copyWith preserves unmodified properties", () {
      final original = StudySettingsModel.defaultSettings();
      final modified = original.copyWith(
        defaultQuestionCount: 30,
        instantFeedback: false,
      );

      expect(modified.defaultQuestionCount, 30);
      expect(modified.instantFeedback, false);
      expect(modified.preferredStudyMode, 8); // Unmodified
      expect(modified.blitzSecondsPerQuestion, 10); // Unmodified
      expect(modified.dailyStudyGoalMinutes, 30); // Unmodified
    });
  });

  group("SettingsService Offline Caching Tests", () {
    test("SettingsService loads default settings when cache is empty", () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.settings.defaultQuestionCount, 15);
      expect(service.settings.preferredStudyMode, 8);
    });

    test("SettingsService saves settings locally and notifies listeners", () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      bool wasNotified = false;
      service.addListener(() {
        wasNotified = true;
      });

      final updated = service.settings.copyWith(
        defaultQuestionCount: 25,
        dailyStudyGoalMinutes: 60,
      );

      await service.saveSettings(updated);

      expect(wasNotified, true);
      expect(service.settings.defaultQuestionCount, 25);
      expect(service.settings.dailyStudyGoalMinutes, 60);

      // Verify second instance loads the cached values from SharedPreferences
      final secondInstance = SettingsService(prefs);
      expect(secondInstance.settings.defaultQuestionCount, 25);
      expect(secondInstance.settings.dailyStudyGoalMinutes, 60);
    });
  });

  group("SettingsScreen Developer Connection Widget Tests", () {
    testWidgets("SettingsScreen renders Developer API Connection card and presets", (tester) async {
      SharedPreferences.setMockInitialValues({
        "jwt_token": "mock-token",
        "user_id": "test-user-id",
        "user_email": "student@studyapp.test",
        "user_full_name": "Student Tester",
      });
      final prefs = await SharedPreferences.getInstance();
      final sessionService = SessionService(prefs);
      ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);
      final settingsService = SettingsService(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsScreen(
              apiClient: apiClient,
              sessionService: sessionService,
              settingsService: settingsService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to Developer Card
      await tester.scrollUntilVisible(
        find.text("🛠️ Developer & Cloud API Connection"),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Verify developer card is rendered
      expect(find.text("🛠️ Developer & Cloud API Connection"), findsOneWidget);
      expect(find.text("Backend API Base URL"), findsOneWidget);
      expect(find.byKey(const Key("server_url_input")), findsOneWidget);
      expect(find.text("Localhost:5000"), findsOneWidget);
      expect(find.text("Android (10.0.2.2)"), findsOneWidget);
      expect(find.byKey(const Key("test_connection_btn")), findsOneWidget);

      // Tap Android (10.0.2.2) preset chip
      await tester.ensureVisible(find.text("Android (10.0.2.2)"));
      await tester.tap(find.text("Android (10.0.2.2)"));
      await tester.pumpAndSettle();

      // Verify URL updated in text field
      final textFieldAndroid = tester.widget<TextField>(find.byKey(const Key("server_url_input")));
      expect(textFieldAndroid.controller?.text, "http://10.0.2.2:5000");

      // Tap Localhost:5000 preset chip
      await tester.tap(find.text("Localhost:5000"));
      await tester.pumpAndSettle();

      // Verify URL updated back to localhost
      final textFieldLocal = tester.widget<TextField>(find.byKey(const Key("server_url_input")));
      expect(textFieldLocal.controller?.text, "http://localhost:5000");
    });
  });
}
