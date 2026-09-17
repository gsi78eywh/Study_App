import "dart:typed_data";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/theme/theme_controller.dart";
import "package:study_app_mobile/features/courses/screens/dashboard_screen.dart";
import "package:study_app_mobile/main.dart";

class MockHttpAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString("[]", 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group("Mobile UAT User Flows", () {
    testWidgets("UAT_M1: Unauthenticated boot renders LoginScreen and branding", (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final themeController = ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);

      await tester.pumpWidget(StudyAppMobile(
        sessionService: sessionService,
        apiClient: apiClient,
        themeController: themeController,
      ));
      await tester.pumpAndSettle();

      expect(find.text("StudyApp"), findsOneWidget);
      expect(find.text("Sign In"), findsOneWidget);
      expect(find.text("Create Account"), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2)); // Email & Password
    });

    testWidgets("UAT_M2: Form validation stops submission on empty inputs", (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final themeController = ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);

      await tester.pumpWidget(StudyAppMobile(
        sessionService: sessionService,
        apiClient: apiClient,
        themeController: themeController,
      ));
      await tester.pumpAndSettle();

      // Tap Sign In button with empty fields
      final signInButton = find.widgetWithText(ElevatedButton, "Sign In");
      expect(signInButton, findsOneWidget);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      expect(find.text("Email is required"), findsOneWidget);
      expect(find.text("Password is required"), findsOneWidget);
    });

    testWidgets("UAT_M3: Theme toggle dynamically switches between light and dark modes", (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final themeController = ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);

      await tester.pumpWidget(StudyAppMobile(
        sessionService: sessionService,
        apiClient: apiClient,
        themeController: themeController,
      ));
      await tester.pumpAndSettle();

      final initialMode = themeController.isDarkMode;
      final themeToggleBtn = find.byType(IconButton).first;
      await tester.tap(themeToggleBtn);
      await tester.pumpAndSettle();

      expect(themeController.isDarkMode, !initialMode);
    });

    testWidgets("UAT_M4: Navigation to Create Account screen and field verification", (WidgetTester tester) async {
      final sessionService = await SessionService.init();
      final themeController = ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);

      await tester.pumpWidget(StudyAppMobile(
        sessionService: sessionService,
        apiClient: apiClient,
        themeController: themeController,
      ));
      await tester.pumpAndSettle();

      final createAccountBtn = find.widgetWithText(TextButton, "Create Account");
      await tester.ensureVisible(createAccountBtn);
      await tester.tap(createAccountBtn);
      await tester.pumpAndSettle();

      // Should now be on register screen
      expect(find.text("Join StudyApp"), findsOneWidget);
      expect(find.text("Create Student Account"), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4)); // Full Name, Email, Password, Confirm Password
    });

    testWidgets("UAT_M5: Authenticated session boots directly into DashboardScreen", (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        "jwt_token": "mock.jwt.bearer_token_for_tests",
        "user_id": "test-user-guid-1234",
        "user_full_name": "Dr. Marie Curie",
        "user_email": "curie@sorbonne.fr",
      });

      final sessionService = await SessionService.init();
      final themeController = ThemeController.init(sessionService);
      final apiClient = ApiClient(sessionService);
      apiClient.dio.httpClientAdapter = MockHttpAdapter();

      expect(sessionService.isAuthenticated, true);

      await tester.pumpWidget(StudyAppMobile(
        sessionService: sessionService,
        apiClient: apiClient,
        themeController: themeController,
      ));
      await tester.pumpAndSettle();

      // Verify dashboard presence and student greeting
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(sessionService.fullName, "Dr. Marie Curie");
      expect(find.text("Welcome back, Dr. Marie Curie 👋"), findsOneWidget);
    });
  });
}
