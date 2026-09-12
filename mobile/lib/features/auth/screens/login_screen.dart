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
        _errorMessage = e.error?.toString() ?? e.message ?? "Authentication failed.";
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
              "Configure backend URL for your current emulator or device:",
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text("Windows/Web (localhost)"),
                  onPressed: () => urlController.text = "http://localhost:5000",
                ),
                ActionChip(
                  label: const Text("Android (10.0.2.2)"),
                  onPressed: () => urlController.text = "http://10.0.2.2:5000",
                ),
              ],
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
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: AppColors.darkTextSecondary),
                          tooltip: "Backend Host Settings",
                          onPressed: _showServerConfigDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
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
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 24),
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
                      "AI-Powered Learning & Practice Platform",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withOpacity(0.5)),
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
                      const SizedBox(height: 20),
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
                    const SizedBox(height: 28),
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
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
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
