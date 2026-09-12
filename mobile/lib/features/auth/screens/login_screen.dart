import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
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
  final _emailController = TextEditingController(text: "alex@example.com");
  final _passwordController = TextEditingController(text: "Password123!");
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Clear stale session on login screen mount so background sync doesn't trigger 401
    widget.sessionService.clearAuth();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin({String? overrideEmail, String? overridePassword}) async {
    final email = overrideEmail ?? _emailController.text.trim();
    final password = overridePassword ?? _passwordController.text;

    if (overrideEmail == null && !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.login,
        data: {
          "email": email,
          "password": password,
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
          _errorMessage = "Cannot connect to backend server. Make sure the API is running at ${widget.sessionService.baseUrl ?? ApiConstants.defaultBaseUrl}";
        } else if (e.response?.statusCode == 401) {
          _errorMessage = "Invalid email or password. Please check your credentials.";
        } else {
          _errorMessage = e.error?.toString() ?? e.message ?? "Authentication failed.";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Unexpected error: $e";
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
        backgroundColor: AppColors.darkCard,
        title: Text("API Server Endpoint", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Configure backend URL for Flutter Web or physical device testing:",
              style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Base URL",
                hintText: "http://localhost:5000",
              ),
            ),
          ],
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 14),
                              SizedBox(width: 6),
                              Text("API Ready (Port 5000)", style: TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: AppColors.darkTextSecondary),
                          tooltip: "Backend Host Settings",
                          onPressed: _showServerConfigDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                              color: AppColors.primary.withValues(alpha: 0.35),
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
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Intelligent Student Active Recall & Exam Platform",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Quick Demo Student Login Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bolt_rounded, color: AppColors.primaryLight, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "Quick Demo Student Access",
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "Account: alex@example.com (CS, Bio & Math pre-loaded)",
                            style: TextStyle(color: AppColors.darkTextSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: const Text("1-Tap Sign In as Alex", style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _isLoading ? null : () => _handleLogin(overrideEmail: "alex@example.com", overridePassword: "Password123!"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppColors.darkCardBorder)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text("or sign in with password", style: GoogleFonts.inter(color: AppColors.darkTextSecondary, fontSize: 12)),
                        ),
                        const Expanded(child: Divider(color: AppColors.darkCardBorder)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: AppColors.danger, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "Email Address",
                        prefixIcon: Icon(Icons.email_outlined, color: AppColors.darkTextSecondary),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return "Email is required";
                        if (!val.contains("@")) return "Enter a valid email address";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.darkTextSecondary),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: AppColors.darkTextSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return "Password is required";
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.darkCard,
                        side: const BorderSide(color: AppColors.darkCardBorder),
                      ),
                      onPressed: _isLoading ? null : () => _handleLogin(),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("Sign In"),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account?",
                          style: TextStyle(color: AppColors.darkTextSecondary),
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
                          child: const Text("Create Account"),
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
    );
  }
}
