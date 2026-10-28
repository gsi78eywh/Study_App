import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "core/network/api_client.dart";
import "core/services/app_session.dart";
import "core/services/child_safety_service.dart";
import "core/services/notification_service.dart";
import "core/services/session_service.dart";
import "core/theme/app_theme.dart";
import "core/theme/theme_controller.dart";
import "features/auth/screens/login_screen.dart";
import "features/courses/screens/dashboard_screen.dart";
import "features/sync/services/sync_service.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppSession.init();
  SessionService.onClearUserData = SyncService.clearCache;

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
  bool _forceMobileWebFrame = true;

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
          theme: AppTheme.buildTheme(isDark: false, useDyslexicFont: childSafety.dyslexiaFriendlyFont),
          darkTheme: AppTheme.buildTheme(isDark: true, useDyslexicFont: childSafety.dyslexiaFriendlyFont),
          themeMode: widget.themeController.themeMode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final system = MediaQuery.textScalerOf(context).scale(1.0);
            final factor = (system * childSafety.textScaleFactor).clamp(0.85, 1.6);
            final isWideWeb = kIsWeb && mq.size.width > 520;

            if (isWideWeb && _forceMobileWebFrame) {
              const mobileWidth = 396.0;
              final mobileHeight = (mq.size.height - 32.0).clamp(560.0, 880.0);
              return Scaffold(
                backgroundColor: const Color(0xFF0B0F19),
                body: Stack(
                  children: [
                    Center(
                      child: Container(
                        width: mobileWidth,
                        height: mobileHeight,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFFF6B00).withValues(alpha: 0.55),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.65),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: MediaQuery(
                          data: mq.copyWith(
                            size: Size(mobileWidth, mobileHeight),
                            textScaler: TextScaler.linear(factor),
                          ),
                          child: child ?? const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 16,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => setState(() => _forceMobileWebFrame = false),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFFF6B00)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone_android_rounded, size: 15, color: Color(0xFFFF6B00)),
                                SizedBox(width: 6),
                                Text(
                                  "Mobile View • Tap for Full Screen",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                MediaQuery(
                  data: mq.copyWith(
                    textScaler: TextScaler.linear(factor),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
                if (isWideWeb && !_forceMobileWebFrame)
                  Positioned(
                    top: 12,
                    right: 16,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _forceMobileWebFrame = true),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFF6B00)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_android_rounded, size: 15, color: Color(0xFFFF6B00)),
                              SizedBox(width: 6),
                              Text(
                                "Switch to Mobile View",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
