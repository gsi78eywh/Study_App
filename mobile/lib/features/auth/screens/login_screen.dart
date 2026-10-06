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
import "../widgets/google_sign_in_dialog.dart";
import "../../../core/services/google_auth_service.dart";
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
          _errorMessage = "Unable to connect to server. Please check your network connection or server status.";
        } else if (e.response?.statusCode == 429) {
          _errorMessage = "High request volume. Please wait a moment and try again.";
        } else if (e.response?.statusCode == 503) {
          _errorMessage = "Server is temporarily balancing load. Please try again in a few moments.";
        } else if (e.response?.statusCode == 401) {
          _errorMessage = "Invalid email or password. Please try again.";
        } else if (e.response?.data is Map && (e.response?.data as Map)["message"] != null) {
          _errorMessage = (e.response!.data as Map)["message"].toString();
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

  void _goToDashboard() {
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

  /// Opens the local developer Google sign-in dialog. This dialog performs no real
  /// Google verification, so it is only offered in debug builds (the backend also
  /// rejects its tokens outside Development).
  Future<void> _openLocalGoogleDialog() async {
    if (!GoogleSignInDialog.isAvailable) {
      setState(() {
        _errorMessage = "Google Sign-In isn't set up on this version yet. "
            "Please sign in with your email and password.";
      });
      return;
    }
    final success = await GoogleSignInDialog.show(
      context,
      apiClient: widget.apiClient,
      sessionService: widget.sessionService,
      initialEmail: _emailController.text.trim(),
    );
    if (success) _goToDashboard();
  }

  // Real Google Sign-In with Server-Side ID Token Verification
  Future<void> _handleRealGoogleSignIn() async {
    // Web builds without a GOOGLE_CLIENT_ID cannot run the real Google SDK.
    if (!GoogleAuthService.isConfigured) {
      await _openLocalGoogleDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await GoogleAuthService.instance.signIn();
      if (!result.success) {
        if (result.requiresDirectPrompt) {
          if (!mounted) return;
          await _openLocalGoogleDialog();
          return;
        }

        if (result.errorMessage != null && !result.errorMessage!.contains("cancelled")) {
          // In local web development the SDK may fail; fall back to the dev dialog.
          if (kIsWeb && GoogleSignInDialog.isAvailable) {
            if (!mounted) return;
            await _openLocalGoogleDialog();
            return;
          }
          setState(() => _errorMessage = result.errorMessage);
        }
        return;
      }

      final response = await widget.apiClient.dio.post(
        ApiConstants.googleAuth,
        data: {"idToken": result.idToken},
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
        _errorMessage = e.response?.data?["message"]?.toString() ??
            "Google Authentication failed. Please verify server connection.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Google Sign-In failed: $e";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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


  void _showServerConfigDialog() {
    if (!kDebugMode) return;
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
                "Developer Endpoint",
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
                "Select server endpoint or enter custom URL:",
                style: TextStyle(color: ctx.textSecondary, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.cloud_rounded, size: 14, color: AppColors.primary),
                    label: const Text("Railway Production", style: TextStyle(fontSize: 11.5)),
                    onPressed: () => urlController.text = "https://your-app.up.railway.app",
                  ),
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
                  labelText: "Base URL",
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
                              // Top Controls: Theme Toggle
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
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
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            style: TextStyle(color: context.textPrimary),
                            decoration: InputDecoration(
                              labelText: "Email Address",
                              hintText: "student@university.edu",
                              prefixIcon: Icon(Icons.email_outlined, color: context.textSecondary),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return "Email is required";
                              final trimmed = val.trim();
                              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                              if (!emailRegex.hasMatch(trimmed)) return "Please enter a valid email address";
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password Field with Visibility Toggle
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) => _handleLogin(),
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
                              if (val.length < 8) return "Password must be at least 8 characters";
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

                          // Google Sign-In (Real OAuth verified server-side)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _handleRealGoogleSignIn,
                              icon: const Icon(Icons.g_mobiledata_rounded, size: 24, color: Color(0xFF4285F4)),
                              label: const Text(
                                "Continue with Google",
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.textPrimary,
                                side: BorderSide(color: context.cardBorderColor),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),

                          // Demo Student Account (Debug builds only • clearly labeled sample mode)
                          if (kDebugMode) ...[
                            const SizedBox(height: 14),
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
                                      content: Text("Demo credentials loaded (Sample Mode • No Cloud Sync)."),
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
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

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
                          const SizedBox(height: 16),

                          // Version Footer (Long-press in Debug mode reveals Developer Endpoint dialog)
                          Center(
                            child: GestureDetector(
                              onLongPress: kDebugMode ? _showServerConfigDialog : null,
                              child: Text(
                                "StudyApp v1.0.0",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary.withValues(alpha: 0.6),
                                  letterSpacing: 0.5,
                                ),
                              ),
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
