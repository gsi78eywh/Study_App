import "package:flutter/material.dart";
import "core/network/api_client.dart";
import "core/services/session_service.dart";
import "core/theme/app_theme.dart";
import "features/auth/screens/login_screen.dart";
import "features/courses/screens/dashboard_screen.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionService = await SessionService.init();
  final apiClient = ApiClient(sessionService);

  runApp(StudyAppMobile(
    sessionService: sessionService,
    apiClient: apiClient,
  ));
}

class StudyAppMobile extends StatelessWidget {
  final SessionService sessionService;
  final ApiClient apiClient;

  const StudyAppMobile({
    super.key,
    required this.sessionService,
    required this.apiClient,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "StudyApp",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: sessionService.isAuthenticated
          ? DashboardScreen(apiClient: apiClient, sessionService: sessionService)
          : LoginScreen(apiClient: apiClient, sessionService: sessionService),
    );
  }
}
