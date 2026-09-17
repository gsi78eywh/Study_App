import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/theme/theme_controller.dart";
import "../models/auth_models.dart";
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

  @override
  void initState() {
    super.initState();
    // Remember previously entered email or start blank
    _emailController = TextEditingController(text: widget.sessionService.email ?? "");
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
          _errorMessage = "Cannot connect to server. Please verify your connection or server settings.";
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

  void _showServerConfigDialog() {
    final urlController = TextEditingController(
      text: widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("API Server Endpoint", style: GoogleFonts.outfit(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Configure backend URL for Flutter Web or local device testing:",
                style: TextStyle(color: ctx.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                style: TextStyle(color: ctx.textPrimary),
                decoration: const InputDecoration(
                  labelText: "Base URL",
                  hintText: "http://localhost:5000",
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
            },
            child: const Text("Save"),
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
          // Ambient radial background glow
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
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
                          // Top Controls: Theme Toggle & Settings
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              IconButton(
                                icon: Icon(Icons.settings_outlined, color: context.textSecondary),
                                tooltip: "Backend Host Settings",
                                onPressed: _showServerConfigDialog,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // App Logo & Branding
                          Center(
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.2),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.school_rounded, color: Colors.white, size: 40),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            "StudyApp",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 30,
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
                          const SizedBox(height: 28),

                          // Error Message
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
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
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Email Field
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
                              if (!val.contains("@")) return "Please enter a valid email address";
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),

                          // Password Field
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
                              return null;
                            },
                          ),
                          const SizedBox(height: 26),

                          // Sign In Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text("Sign In"),
                          ),
                          const SizedBox(height: 16),

                          // Demo Account Quick Button
                          OutlinedButton.icon(
                            onPressed: () {
                              _emailController.text = "dev@studyapp.local";
                              _passwordController.text = "DevPass123!";
                            },
                            icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFF59E0B)),
                            label: const Text("Use Demo Account (dev@studyapp.local)", style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.textSecondary,
                              side: BorderSide(color: context.cardBorderColor),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            ),
                          ),
                          const SizedBox(height: 16),

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
                        ],
                      ),
                    ),
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
