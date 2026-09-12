import "package:flutter/material.dart";
import "core/network/api_client.dart";
import "core/services/session_service.dart";
import "core/theme/app_theme.dart";
import "core/theme/theme_controller.dart";
import "features/auth/screens/login_screen.dart";
import "features/courses/screens/dashboard_screen.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionService = await SessionService.init();
  final themeController = ThemeController.init(sessionService);
  final apiClient = ApiClient(sessionService);

  runApp(StudyAppMobile(
    sessionService: sessionService,
    apiClient: apiClient,
    themeController: themeController,
  ));
}

class StudyAppMobile extends StatelessWidget {
  final SessionService sessionService;
  final ApiClient apiClient;
  final ThemeController themeController;

  const StudyAppMobile({
    super.key,
    required this.sessionService,
    required this.apiClient,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: "StudyApp",
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeController.themeMode,
          home: sessionService.isAuthenticated
              ? DashboardScreen(apiClient: apiClient, sessionService: sessionService)
              : LoginScreen(apiClient: apiClient, sessionService: sessionService),
        );
      },
    );
  }
}
