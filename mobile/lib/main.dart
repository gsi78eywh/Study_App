import "package:flutter/material.dart";
import "core/network/api_client.dart";
import "core/services/child_safety_service.dart";
import "core/services/notification_service.dart";
import "core/services/session_service.dart";
import "core/theme/app_theme.dart";
import "core/theme/theme_controller.dart";
import "features/auth/screens/login_screen.dart";
import "features/courses/screens/dashboard_screen.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionService = await SessionService.init();
  await sessionService.expireIfInactive();
  await ChildSafetyService.init(sessionService.prefs);
  await NotificationService.instance.init();
  final themeController = ThemeController.init(sessionService);
  final apiClient = ApiClient(sessionService);

  runApp(StudyAppMobile(
    sessionService: sessionService,
    apiClient: apiClient,
    themeController: themeController,
  ));
}

class StudyAppMobile extends StatefulWidget {
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
  State<StudyAppMobile> createState() => _StudyAppMobileState();
}

class _StudyAppMobileState extends State<StudyAppMobile> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sessionService.recordActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.themeController, ChildSafetyService.instance]),
      builder: (context, _) {
        final childSafety = ChildSafetyService.instance;
        return MaterialApp(
          title: "StudyApp",
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: widget.themeController.themeMode,
          builder: (context, child) {
            final system = MediaQuery.textScalerOf(context).scale(1.0);
            final factor = (system * childSafety.textScaleFactor).clamp(0.85, 1.6);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(factor),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: widget.sessionService.isAuthenticated
              ? DashboardScreen(apiClient: widget.apiClient, sessionService: widget.sessionService)
              : LoginScreen(apiClient: widget.apiClient, sessionService: widget.sessionService),
        );
      },
    );
  }
}

