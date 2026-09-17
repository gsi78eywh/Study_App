import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_app_mobile/core/services/child_safety_service.dart';
import 'package:study_app_mobile/core/services/audio_speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChildSafetyService - DSWD Child Protection & Accessibility Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      await ChildSafetyService.init(prefs);
    });

    test('Initializes with safe defaults', () {
      final service = ChildSafetyService.instance;
      expect(service.isJuniorMode, isFalse);
      expect(service.gradeLevel, equals(3));
      expect(service.gradeLevelText, equals('Grade 3'));
      expect(service.textScale, equals(AccessibilityTextScale.normal));
      expect(service.textScaleFactor, equals(1.0));
      expect(service.readAloudEnabled, isTrue);
      expect(service.eyeBreakMinutes, equals(20)); // DSWD PES recommended
    });

    test('Toggling Junior Learner Mode persists to SharedPreferences', () async {
      final service = ChildSafetyService.instance;
      await service.setJuniorMode(true);

      expect(service.isJuniorMode, isTrue);
      expect(prefs.getBool(ChildSafetyService.keyJuniorMode), isTrue);

      await service.setGradeLevel(2);
      expect(service.gradeLevel, equals(2));
      expect(service.gradeLevelText, equals('Grade 2'));
      expect(prefs.getInt(ChildSafetyService.keyGradeLevel), equals(2));
    });

    test('WCAG 2.1 AA Dynamic Text Scaling factors apply correctly', () async {
      final service = ChildSafetyService.instance;

      await service.setTextScale(AccessibilityTextScale.large);
      expect(service.textScaleFactor, equals(1.2));
      expect(prefs.getString(ChildSafetyService.keyTextScale), equals('large'));

      await service.setTextScale(AccessibilityTextScale.extraLarge);
      expect(service.textScaleFactor, equals(1.35));
      expect(prefs.getString(ChildSafetyService.keyTextScale), equals('extraLarge'));

      await service.setTextScale(AccessibilityTextScale.normal);
      expect(service.textScaleFactor, equals(1.0));
    });

    test('Child-friendly tab names adapt to Junior Learner Mode', () async {
      final service = ChildSafetyService.instance;

      // In standard mode:
      await service.setJuniorMode(false);
      expect(service.getFriendlyTabName(0, 'Courses'), equals('Courses'));
      expect(service.getFriendlyTabName(1, 'Flashcards'), equals('Flashcards'));
      expect(service.getFriendlyTabName(2, 'Notebook'), equals('Notebook'));
      expect(service.getFriendlyTabName(3, 'AI Studio'), equals('AI Studio'));
      expect(service.getFriendlyTabName(4, 'Gemini Tutor'), equals('Gemini Tutor'));

      // In junior mode:
      await service.setJuniorMode(true);
      expect(service.getFriendlyTabName(0, 'Courses'), equals('My Subjects 📚'));
      expect(service.getFriendlyTabName(1, 'Flashcards'), equals('Cards 🃏'));
      expect(service.getFriendlyTabName(2, 'Notebook'), equals('Notes 📝'));
      expect(service.getFriendlyTabName(3, 'AI Studio'), equals('Studio 🎨'));
      expect(service.getFriendlyTabName(4, 'Gemini Tutor'), equals('Buddy AI 🤖'));
    });

    test('Growth mindset feedback produces encouraging messages without shaming', () async {
      final service = ChildSafetyService.instance;

      await service.setJuniorMode(true);
      final correctFeedback = service.getEncouragingFeedback(isCorrect: true);
      expect(correctFeedback, isNotEmpty);
      expect(correctFeedback.contains('Awesome') ||
             correctFeedback.contains('Fantastic') ||
             correctFeedback.contains('Super') ||
             correctFeedback.contains('Great') ||
             correctFeedback.contains('Hooray'), isTrue);

      final incorrectFeedback = service.getEncouragingFeedback(isCorrect: false);
      expect(incorrectFeedback, isNotEmpty);
      expect(incorrectFeedback.contains('Good try') ||
             incorrectFeedback.contains('Keep going') ||
             incorrectFeedback.contains('Making mistakes') ||
             incorrectFeedback.contains('Great effort') ||
             incorrectFeedback.contains('doing well'), isTrue);
    });

    test('DSWD PES 20-20-20 eye break timer tracks session correctly', () {
      final service = ChildSafetyService.instance;
      service.resetEyeBreakTimer();

      // Right after reset, should not prompt
      expect(service.shouldPromptEyeBreak, isFalse);
      expect(service.minutesSinceLastBreak, equals(0));

      // With eye break disabled (0 minutes), should never prompt
      service.setEyeBreakMinutes(0);
      expect(service.shouldPromptEyeBreak, isFalse);
    });

    test('Enrich prompt for child safety embeds Grade level instructions', () async {
      final service = ChildSafetyService.instance;
      await service.setJuniorMode(true);
      await service.setGradeLevel(3);

      final enriched = service.enrichPromptForChildSafety('What is photosynthesis?');
      expect(enriched.contains('Grade 3'), isTrue);
      expect(enriched.contains('child-friendly'), isTrue);
      expect(enriched.contains('What is photosynthesis?'), isTrue);
    });

    test('AudioSpeechHelper speech service is available without crash', () async {
      final helper = AudioSpeechHelper.instance;
      expect(helper.isSpeaking, isFalse);

      await helper.speak('Hello learner');
      expect(helper.isSpeaking, isTrue);

      await helper.stop();
      expect(helper.isSpeaking, isFalse);
    });
  });
}
