import "package:flutter/material.dart";
import "package:dio/dio.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../models/auth_models.dart";
import "../../courses/screens/dashboard_screen.dart";

class RegisterScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;

  const RegisterScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.register,
        data: {
          "fullName": _fullNameController.text.trim(),
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
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DashboardScreen(
              apiClient: widget.apiClient,
              sessionService: widget.sessionService,
            ),
          ),
          (route) => false,
        );
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.error?.toString() ?? e.message ?? "Registration failed.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Unexpected error: $e";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create Account"),
      ),
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
                    Text(
                      "Join StudyApp",
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Master complex subjects with AI active-recall sets",
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.darkTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
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
                      controller: _fullNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "Full Name",
                        prefixIcon: Icon(Icons.person_outline, color: AppColors.darkTextSecondary),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return "Name is required";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
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
                        if (val == null || val.length < 6) return "Must be at least 6 characters";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: "Confirm Password",
                        prefixIcon: Icon(Icons.lock_outline, color: AppColors.darkTextSecondary),
                      ),
                      validator: (val) {
                        if (val != _passwordController.text) return "Passwords do not match";
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("Create Account"),
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
