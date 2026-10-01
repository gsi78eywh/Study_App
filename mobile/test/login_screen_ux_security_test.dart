import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/theme/theme_controller.dart";
import "package:study_app_mobile/features/auth/screens/login_screen.dart";

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets("LoginScreen: Security and UX verification", (WidgetTester tester) async {
    final sessionService = await SessionService.init();
    final apiClient = ApiClient(sessionService);
    ThemeController.init(sessionService);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          apiClient: apiClient,
          sessionService: sessionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify gear icon is completely removed from public UI
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.text("Backend Host Settings"), findsNothing);

    // 2. Verify Theme Toggle is present in top controls
    expect(find.byType(IconButton), findsWidgets);
    expect(find.byTooltip("Switch to Light Mode"), findsOneWidget);

    // 3. Verify App Branding & Tagline
    expect(find.text("StudyApp"), findsOneWidget);
    expect(find.text("Student Learning, Spaced Recall & Exam Mastery"), findsOneWidget);

    // 4. Verify "Forgot Password?" button exists and opens recovery modal
    final forgotBtn = find.text("Forgot Password?");
    expect(forgotBtn, findsOneWidget);
    await tester.tap(forgotBtn);
    await tester.pumpAndSettle();

    expect(find.text("Reset Password"), findsOneWidget);
    expect(find.text("Send Instructions"), findsOneWidget);

    // Close recovery dialog
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();

    // 5. Verify primary "Sign In" button exists
    expect(find.text("Sign In"), findsOneWidget);

    // 6. Verify "or continue with" divider and Social Auth buttons exist
    expect(find.text("or continue with"), findsOneWidget);
    expect(find.text("Continue with Google"), findsOneWidget);
    expect(find.text("Apple"), findsNothing);

    // 7. Verify Demo button is rebranded and does NOT expose internal dev email
    expect(find.text("Try Demo Student Account"), findsOneWidget);
    expect(find.textContaining("dev@studyapp.local"), findsNothing);

    // 8. Test tapping "Try Demo Student Account" populates demo credentials
    final demoBtn = find.text("Try Demo Student Account");
    await tester.ensureVisible(demoBtn);
    await tester.tap(demoBtn);
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, "Email Address"));
    expect(emailField.controller?.text, "dev@studyapp.local");

    // Wait for demo credentials snackbar to dismiss so it doesn't obscure the footer
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 9. Test long-press on the version footer opens Developer Endpoint dialog in debug builds
    final footerFinder = find.text("StudyApp v1.0.0");
    expect(footerFinder, findsOneWidget);
    await tester.ensureVisible(footerFinder);
    await tester.longPress(footerFinder);
    await tester.pumpAndSettle();

    expect(find.text("Developer Endpoint"), findsOneWidget);
    expect(find.text("Base URL"), findsOneWidget);

    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();
  });

  testWidgets("LoginScreen: Narrow viewport renders without overflow", (WidgetTester tester) async {
    // Simulate narrow mobile screen (320px width, e.g. iPhone SE / compact Android)
    tester.view.physicalSize = const Size(320 * 2, 568 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sessionService = await SessionService.init();
    final apiClient = ApiClient(sessionService);
    ThemeController.init(sessionService);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          apiClient: apiClient,
          sessionService: sessionService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify all key elements render without any RenderFlex overflow exceptions
    expect(tester.takeException(), isNull);
    expect(find.text("StudyApp"), findsOneWidget);
    expect(find.text("Continue with Google"), findsOneWidget);
    expect(find.text("Apple"), findsNothing);
    expect(find.text("Sign In"), findsOneWidget);
  });
}
