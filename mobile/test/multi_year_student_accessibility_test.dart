import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_app_mobile/core/services/child_safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Year Student Accessibility & Stage Adaptation Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      await ChildSafetyService.init(prefs);
    });

    test('1. Elementary Learner Stage (Grades 1-6) triggers Junior Mode with pediatric safety', () async {
      final cs = ChildSafetyService.instance;

      await cs.setJuniorMode(true);
      await cs.setGradeLevel(4);

      expect(cs.isJuniorMode, isTrue);
      expect(cs.gradeLevel, equals(4));
      expect(cs.studentStage, equals('Elementary'));
      expect(cs.stageBadgeText, equals('🐣 Junior Mode (Grade 4)'));

      final enrichedPrompt = cs.enrichPromptForGradeLevel('What causes thunder?');
      expect(enrichedPrompt.contains('Grade 4'), isTrue);
      expect(enrichedPrompt.contains('child-friendly'), isTrue);
      expect(enrichedPrompt.contains('positive encouragement'), isTrue);

      // Verify friendly tab names adapt in Junior Mode
      expect(cs.getFriendlyTabName(0, 'Courses'), equals('My Subjects 📚'));
      expect(cs.getFriendlyTabName(4, 'Gemini Tutor'), equals('Buddy AI 🤖'));
    });

    test('2. Junior High School Stage (Grades 7-10) configures foundational curriculum', () async {
      final cs = ChildSafetyService.instance;

      await cs.setJuniorMode(false);
      await cs.setGradeLevel(9);

      expect(cs.isJuniorMode, isFalse);
      expect(cs.gradeLevel, equals(9));
      expect(cs.studentStage, equals('Junior High'));
      expect(cs.stageBadgeText, equals('🎒 Junior High (Grade 9)'));

      final enrichedPrompt = cs.enrichPromptForGradeLevel('Explain Newton second law');
      expect(enrichedPrompt.contains('Junior High School'), isTrue);
      expect(enrichedPrompt.contains('Grade 9'), isTrue);
      expect(enrichedPrompt.contains('step-by-step clarity'), isTrue);
      expect(enrichedPrompt.contains('active recall'), isTrue);

      // Standard tab names preserved for high schoolers
      expect(cs.getFriendlyTabName(0, 'Courses'), equals('Courses'));
      expect(cs.getFriendlyTabName(4, 'Gemini Tutor'), equals('Gemini Tutor'));
    });

    test('3. Senior High School Stage (Grades 11-12) configures academic track and college prep', () async {
      final cs = ChildSafetyService.instance;

      await cs.setJuniorMode(false);
      await cs.setGradeLevel(12);

      expect(cs.isJuniorMode, isFalse);
      expect(cs.gradeLevel, equals(12));
      expect(cs.studentStage, equals('Senior High'));
      expect(cs.stageBadgeText, equals('🔬 Senior High (Grade 12)'));

      final enrichedPrompt = cs.enrichPromptForGradeLevel('Derive chemical equilibrium constant Kc');
      expect(enrichedPrompt.contains('Senior High School'), isTrue);
      expect(enrichedPrompt.contains('Grade 12'), isTrue);
      expect(enrichedPrompt.contains('academic depth'), isTrue);
      expect(enrichedPrompt.contains('college exams'), isTrue);
    });

    test('4. College / University Mode enables full collegiate taxonomy', () async {
      final cs = ChildSafetyService.instance;

      await cs.setJuniorMode(false);
      // Neutral college grade level (< 7 or > 12)
      await cs.setGradeLevel(1);

      expect(cs.isJuniorMode, isFalse);
      expect(cs.studentStage, equals('College'));
      expect(cs.stageBadgeText, equals('🎓 College Mode'));

      final rawQuery = 'Analyze macroeconomic monetary policy impacts on exchange rates';
      final enrichedPrompt = cs.enrichPromptForGradeLevel(rawQuery);
      // College leaves prompt untouched for unconstrained academic depth
      expect(enrichedPrompt, equals(rawQuery));
    });

    test('5. Accessibility Typography Scale transitions smoothly across all year levels', () async {
      final cs = ChildSafetyService.instance;

      // Normal text scaling (1.0x)
      await cs.setTextScale(AccessibilityTextScale.normal);
      expect(cs.textScaleFactor, equals(1.0));

      // Large text scaling (1.2x)
      await cs.setTextScale(AccessibilityTextScale.large);
      expect(cs.textScaleFactor, equals(1.2));

      // Extra Large text scaling (1.35x)
      await cs.setTextScale(AccessibilityTextScale.extraLarge);
      expect(cs.textScaleFactor, equals(1.35));

      // Continuous float scale factor setter helper
      await cs.setTextScaleFactor(1.4);
      expect(cs.textScale, equals(AccessibilityTextScale.extraLarge));

      await cs.setTextScaleFactor(1.2);
      expect(cs.textScale, equals(AccessibilityTextScale.large));

      await cs.setTextScaleFactor(1.0);
      expect(cs.textScale, equals(AccessibilityTextScale.normal));
    });

    test('6. Dyslexia-friendly typography toggle persists correctly', () async {
      final cs = ChildSafetyService.instance;
      expect(cs.dyslexiaFriendlyFont, isFalse);

      await cs.toggleDyslexiaFont();
      expect(cs.dyslexiaFriendlyFont, isTrue);
      expect(cs.useDyslexicFont, isTrue);

      await cs.toggleDyslexiaFont();
      expect(cs.dyslexiaFriendlyFont, isFalse);
    });
  });
}
