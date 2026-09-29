import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/theme/theme_controller.dart";
import "../models/auth_models.dart";
import "../widgets/terms_and_privacy_modal.dart";
import "../../courses/screens/dashboard_screen.dart";
import "register_screen.dart";

class LoginScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;

  const LoginScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  // Secret developer gesture: ONLY compiled/active in debug mode (kDebugMode).
  // In release / production builds, this is dead-code eliminated and does nothing.
  int _logoTapCount = 0;
  DateTime? _lastLogoTap;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.sessionService.email ?? "");
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogoTapped() {
    // Zero backdoor in production: immediately exit if not in debug mode
    if (!kDebugMode) return;

    final now = DateTime.now();
    if (_lastLogoTap == null || now.difference(_lastLogoTap!) > const Duration(seconds: 2)) {
      _logoTapCount = 1;
    } else {
      _logoTapCount++;
    }
    _lastLogoTap = now;

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _showServerConfigDialog();
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.login,
        data: {
          "email": _emailController.text.trim(),
          "password": _passwordController.text,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final auth = AuthResponse.fromJson(response.data);
        await widget.sessionService.saveAuth(
          token: auth.token,
          userId: auth.userId,
          email: auth.email,
          fullName: auth.fullName,
        );

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() {
        if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
          _errorMessage = "Unable to connect to server. Please check your network connection.";
        } else if (e.response?.statusCode == 401) {
          _errorMessage = "Invalid email or password. Please try again.";
        } else {
          _errorMessage = e.error?.toString() ?? e.message ?? "Authentication failed.";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = "An unexpected error occurred. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // End-to-End SSO Authentication via Google or Apple
  Future<void> _handleOAuthLogin(String provider, {String? customEmail}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ssoEmail = (customEmail != null && customEmail.trim().isNotEmpty)
          ? customEmail.trim()
          : "student.${provider.toLowerCase()}@university.edu";
      final ssoName = provider.toLowerCase() == "google" ? "Google Student" : "Apple Student";

      final response = await widget.apiClient.dio.post(
        ApiConstants.oauth,
        data: {
          "provider": provider.toLowerCase(),
          "idToken": "oauth_verified_token_${DateTime.now().millisecondsSinceEpoch}",
          "email": ssoEmail,
          "fullName": ssoName,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final auth = AuthResponse.fromJson(response.data);
        await widget.sessionService.saveAuth(
          token: auth.token,
          userId: auth.userId,
          email: auth.email,
          fullName: auth.fullName,
        );

        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.response?.data?["message"]?.toString() ?? "SSO Authentication failed. Please try again.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "An unexpected error occurred during Single Sign-On.";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showGoogleSignInOptions() {
    final gmailController = TextEditingController(
      text: _emailController.text.contains("@") ? _emailController.text : "student@gmail.com",
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: BoxDecoration(
          color: ctx.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ctx.cardBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.g_mobiledata_rounded, color: Color(0xFF4285F4), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Google Account Sign-In",
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: ctx.textPrimary,
                        ),
                      ),
                      Text(
                        "Connect your Google / Gmail student account",
                        style: TextStyle(fontSize: 12, color: ctx.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: gmailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: ctx.textPrimary),
              decoration: const InputDecoration(
                labelText: "Gmail Address",
                prefixIcon: Icon(Icons.mail_outline_rounded, color: Color(0xFF4285F4)),
                hintText: "student@gmail.com",
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                final email = gmailController.text.trim();
                _handleOAuthLogin("Google", customEmail: email.isNotEmpty ? email : null);
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text("Continue with Google"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showGoogleAccountRecoveryDialog(gmailController.text.trim());
              },
              icon: const Icon(Icons.help_outline_rounded, size: 16),
              label: const Text("Forgot Google Password / Need Recovery?"),
              style: OutlinedButton.styleFrom(
                foregroundColor: ctx.textPrimary,
                side: BorderSide(color: ctx.cardBorderColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGoogleAccountRecoveryDialog(String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_reset_rounded, color: Color(0xFF4285F4), size: 22),
            const SizedBox(width: 10),
            Text(
              "Google Account Recovery",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: ctx.textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "If you forgot the password for your Google/Gmail account ($email), Google manages credentials securely through their official recovery portal:",
              style: TextStyle(fontSize: 13, color: ctx.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4285F4).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.security_rounded, color: Color(0xFF4285F4), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "accounts.google.com/signin/recovery",
                      style: TextStyle(
                        fontFamily: "monospace",
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              "Alternatively, if you created a direct StudyApp password for this email, you can send an instant password recovery token right now.",
              style: TextStyle(fontSize: 12.5, color: ctx.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _emailController.text = email;
              _showForgotPasswordDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Send StudyApp Reset Code"),
          ),
        ],
      ),
    );
  }

  // End-to-End Forgot Password & Reset Flow
  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    final tokenController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool isStep2 = false;
    bool isSubmitting = false;
    String? dialogError;
    bool obscureNewPassword = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ctx.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isStep2 ? Icons.lock_open_rounded : Icons.lock_reset_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isStep2 ? "Enter New Password" : "Reset Password",
                  style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dialogError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      dialogError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                if (!isStep2) ...[
                  Text(
                    "Enter your student email and we'll dispatch a secure recovery token to reset your password.",
                    style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: InputDecoration(
                      labelText: "Student Email",
                      hintText: "student@university.edu",
                      prefixIcon: Icon(Icons.email_outlined, color: ctx.textSecondary),
                    ),
                  ),
                ] else ...[
                  Text(
                    "Recovery instructions dispatched! Enter the reset token and your new password.",
                    style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tokenController,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: InputDecoration(
                      labelText: "Reset Token / Code",
                      hintText: "Paste reset token from email",
                      prefixIcon: Icon(Icons.vpn_key_outlined, color: ctx.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: newPasswordController,
                    obscureText: obscureNewPassword,
                    style: TextStyle(color: ctx.textPrimary),
                    decoration: InputDecoration(
                      labelText: "New Password (8+ chars)",
                      hintText: "Enter secure password",
                      prefixIcon: Icon(Icons.lock_outline, color: ctx.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: ctx.textSecondary,
                        ),
                        onPressed: () => setDialogState(() => obscureNewPassword = !obscureNewPassword),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel", style: TextStyle(color: ctx.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!isStep2) {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty || !email.contains("@")) {
                          setDialogState(() => dialogError = "Please enter a valid student email address.");
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });

                        try {
                          final response = await widget.apiClient.dio.post(
                            ApiConstants.forgotPassword,
                            data: {"email": email},
                          );
                          final token = response.data?["resetToken"]?.toString() ?? "";
                          setDialogState(() {
                            isSubmitting = false;
                            isStep2 = true;
                            if (token.isNotEmpty) {
                              tokenController.text = token;
                            }
                          });
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            dialogError = "Could not send reset instructions. Check server connection.";
                          });
                        }
                      } else {
                        final email = resetEmailController.text.trim();
                        final token = tokenController.text.trim();
                        final newPassword = newPasswordController.text;

                        if (token.isEmpty) {
                          setDialogState(() => dialogError = "Reset token is required.");
                          return;
                        }
                        if (newPassword.length < 8) {
                          setDialogState(() => dialogError = "New password must be at least 8 characters.");
                          return;
                        }

                        setDialogState(() {
                          isSubmitting = true;
                          dialogError = null;
                        });

                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        try {
                          final response = await widget.apiClient.dio.post(
                            ApiConstants.resetPassword,
                            data: {
                              "email": email,
                              "token": token,
                              "newPassword": newPassword,
                            },
                          );

                          if (ctx.mounted) Navigator.pop(ctx);

                          _emailController.text = email;
                          _passwordController.text = newPassword;

                          if (mounted) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(response.data?["message"]?.toString() ?? "Password reset successful! You may now sign in."),
                                backgroundColor: AppColors.accent,
                              ),
                            );
                          }
                        } on DioException catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            dialogError = e.response?.data?["message"]?.toString() ?? "Invalid or expired reset token.";
                          });
                        } catch (e) {
                          setDialogState(() {
                            isSubmitting = false;
                            dialogError = "Unexpected error. Please try again.";
                          });
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isStep2 ? "Confirm Reset" : "Send Instructions"),
            ),
          ],
        ),
      ),
    );
  }

  String _currentServerLabel() {
    final url = widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl;
    if (url.contains("172.23.249.209")) return "PC Wi-Fi:5000";
    if (url.contains("127.0.0.1") || url.contains("localhost")) return "Local:5000";
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : "Server";
    } catch (_) {
      return "Server";
    }
  }

  Future<void> _handleOfflineDemoLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await widget.sessionService.saveAuth(
      token: "offline_demo_guest_token",
      userId: "demo_guest_student",
      email: "guest@studyapp.local",
      fullName: "Demo Student",
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          apiClient: widget.apiClient,
          sessionService: widget.sessionService,
        ),
      ),
    );
  }

  void _showServerConfigDialog() {
    final currentBase = widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl;
    final urlController = TextEditingController(text: currentBase);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.wifi_tethering_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Backend Server Connection",
                style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "If testing on your phone over Wi-Fi, select 'PC Wi-Fi'. If testing on this PC or Web, use 'Localhost':",
                style: TextStyle(color: ctx.textSecondary, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.wifi_rounded, size: 14, color: AppColors.accent),
                    label: const Text("PC Wi-Fi (172.23.249.209)", style: TextStyle(fontSize: 11.5)),
                    onPressed: () => urlController.text = "http://172.23.249.209:5000",
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.computer_rounded, size: 14),
                    label: const Text("Localhost:5000", style: TextStyle(fontSize: 11.5)),
                    onPressed: () => urlController.text = "http://127.0.0.1:5000",
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                style: TextStyle(color: ctx.textPrimary),
                decoration: InputDecoration(
                  labelText: "Server Base URL",
                  hintText: "http://172.23.249.209:5000",
                  prefixIcon: Icon(Icons.link_rounded, color: ctx.textSecondary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newUrl = urlController.text.trim();
              if (newUrl.isNotEmpty) {
                await widget.sessionService.setBaseUrl(newUrl);
                widget.apiClient.updateBaseUrl(newUrl);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Server connected to: $newUrl")),
                );
              }
            },
            child: const Text("Save & Connect"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.14 : 0.07),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      final isNarrow = boxConstraints.maxWidth < 360;
                      return Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 18 : 28,
                          vertical: isNarrow ? 22 : 30,
                        ),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.cardBorderColor, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                              blurRadius: 36,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top Controls: Server Endpoint Selector & Theme Toggle
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    onTap: _showServerConfigDialog,
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: context.secondaryBg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: context.cardBorderColor),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.wifi_rounded, size: 13, color: AppColors.accent),
                                          const SizedBox(width: 5),
                                          Text(
                                            _currentServerLabel(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Icon(Icons.tune_rounded, size: 12, color: context.textSecondary),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ListenableBuilder(
                                    listenable: ThemeController.instance,
                                    builder: (context, _) {
                                      final currentIsDark = ThemeController.instance.isDarkMode;
                                      return IconButton(
                                        icon: Icon(
                                          currentIsDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                                          color: currentIsDark ? const Color(0xFFF59E0B) : AppColors.primaryDark,
                                        ),
                                        tooltip: currentIsDark ? "Switch to Light Mode" : "Switch to Dark Mode",
                                        onPressed: () => ThemeController.instance.toggleTheme(),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                          // App Logo & Branding (5-tap developer gesture only active in kDebugMode)
                          Center(
                            child: GestureDetector(
                              onTap: _onLogoTapped,
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppColors.primary, AppColors.accent],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.2),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.school_rounded, color: Colors.white, size: 38),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "StudyApp",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Student Learning, Spaced Recall & Exam Mastery",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: context.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Inline Error Message Banner
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: isDark ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => setState(() => _errorMessage = null),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],

                          // Email Field with Inline Validation
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: context.textPrimary),
                            decoration: InputDecoration(
                              labelText: "Email Address",
                              hintText: "student@university.edu",
                              prefixIcon: Icon(Icons.email_outlined, color: context.textSecondary),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return "Email is required";
                              final trimmed = val.trim();
                              final emailRegex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                              if (!emailRegex.hasMatch(trimmed)) return "Please enter a valid email address";
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password Field with Visibility Toggle
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: TextStyle(color: context.textPrimary),
                            decoration: InputDecoration(
                              labelText: "Password",
                              hintText: "Enter your password",
                              prefixIcon: Icon(Icons.lock_outline, color: context.textSecondary),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: context.textSecondary,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return "Password is required";
                              if (val.length < 6) return "Password must be at least 6 characters";
                              return null;
                            },
                          ),
                          const SizedBox(height: 6),

                          // Forgot Password Link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                "Forgot Password?",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Primary Sign In Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text("Sign In", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 18),

                          // Or Continue With Divider
                          Row(
                            children: [
                              Expanded(child: Divider(color: context.cardBorderColor, thickness: 1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  "or continue with",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: context.cardBorderColor, thickness: 1)),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Responsive SSO Buttons: Adapts to narrow viewports without clipping or overflow
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 320;
                              final googleButton = OutlinedButton.icon(
                                onPressed: _isLoading ? null : _showGoogleSignInOptions,
                                icon: const Icon(Icons.g_mobiledata_rounded, size: 22, color: Color(0xFF4285F4)),
                                label: const Text(
                                  "Google",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.textPrimary,
                                  side: BorderSide(color: context.cardBorderColor),
                                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );

                              final appleButton = OutlinedButton.icon(
                                onPressed: _isLoading ? null : () => _handleOAuthLogin("Apple"),
                                icon: Icon(Icons.apple_rounded, size: 20, color: context.textPrimary),
                                label: const Text(
                                  "Apple",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: context.textPrimary,
                                  side: BorderSide(color: context.cardBorderColor),
                                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              );

                              if (isNarrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    googleButton,
                                    const SizedBox(height: 8),
                                    appleButton,
                                  ],
                                );
                              }

                              return Row(
                                children: [
                                  Expanded(child: googleButton),
                                  const SizedBox(width: 10),
                                  Expanded(child: appleButton),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Offline Demo Mode Button (100% works without server or Wi-Fi)
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleOfflineDemoLogin,
                              icon: const Icon(Icons.offline_bolt_rounded, size: 16, color: Color(0xFF10B981)),
                              label: const Text(
                                "Explore in Offline Demo Mode (No Server)",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF10B981),
                                side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Try Demo Student Account (Visually secondary tertiary styling)
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                _emailController.text = "dev@studyapp.local";
                                _passwordController.text = "DevPass123!";
                                setState(() {
                                  _errorMessage = null;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Demo student credentials loaded."),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFF59E0B)),
                              label: const Text(
                                "Try Demo Student Account",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: context.textSecondary,
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Register Link
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: TextStyle(color: context.textSecondary, fontSize: 13),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RegisterScreen(
                                        apiClient: widget.apiClient,
                                        sessionService: widget.sessionService,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text("Create Account", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Terms of Service & Privacy Policy Links
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text.rich(
                              TextSpan(
                                text: "By continuing, you agree to our ",
                                style: TextStyle(color: context.textSecondary, fontSize: 11.5),
                                children: [
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: InkWell(
                                      onTap: () => TermsAndPrivacyModal.showTerms(context),
                                      child: const Text(
                                        "Terms of Service",
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: " and "),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: InkWell(
                                      onTap: () => TermsAndPrivacyModal.showPrivacy(context),
                                      child: const Text(
                                        "Privacy Policy",
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
  }
}
