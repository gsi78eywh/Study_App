import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/main.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/core/network/api_client.dart";

void main() {
  testWidgets("StudyApp boots to LoginScreen when unauthenticated", (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final sessionService = await SessionService.init();
    final apiClient = ApiClient(sessionService);

    await tester.pumpWidget(StudyAppMobile(
      sessionService: sessionService,
      apiClient: apiClient,
    ));

    expect(find.text("StudyApp"), findsOneWidget);
    expect(find.text("Sign In"), findsOneWidget);
  });
}
