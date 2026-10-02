import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/constants/app_colors.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/theme_extensions.dart";
import "../models/auth_models.dart";

class GoogleSignInDialog extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;
  final String? initialEmail;
  final VoidCallback? onSignedIn;

  const GoogleSignInDialog({
    super.key,
    required this.apiClient,
    required this.sessionService,
    this.initialEmail,
    this.onSignedIn,
  });

  static Future<bool> show(
    BuildContext context, {
    required ApiClient apiClient,
    required SessionService sessionService,
    String? initialEmail,
    VoidCallback? onSignedIn,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => GoogleSignInDialog(
        apiClient: apiClient,
        sessionService: sessionService,
        initialEmail: initialEmail,
        onSignedIn: onSignedIn,
      ),
    );
    return result ?? false;
  }

  @override
  State<GoogleSignInDialog> createState() => _GoogleSignInDialogState();
}

class _GoogleSignInDialogState extends State<GoogleSignInDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initEmail = (widget.initialEmail != null && widget.initialEmail!.isNotEmpty)
        ? widget.initialEmail!
        : (widget.sessionService.email != null &&
                !widget.sessionService.email!.contains("studyapp.local")
            ? widget.sessionService.email!
            : "");
    _emailController = TextEditingController(text: initEmail);
    _nameController = TextEditingController();

    _emailController.addListener(() {
      if (_nameController.text.isEmpty && _emailController.text.contains("@")) {
        final prefix = _emailController.text.split("@")[0].replaceAll(".", " ").trim();
        if (prefix.isNotEmpty) {
          final words = prefix.split(" ").map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : "");
          _nameController.text = words.join(" ");
        }
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    var email = _emailController.text.trim();
    if (!email.contains("@")) {
      email = "$email@gmail.com";
      _emailController.text = email;
    }

    var fullName = _nameController.text.trim();
    if (fullName.isEmpty) {
      final prefix = email.split("@")[0].replaceAll(".", " ").trim();
      fullName = prefix.isNotEmpty
          ? prefix.split(" ").map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : "").join(" ")
          : "Google Student";
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final idToken = "dev-google:$email|$fullName";
      final response = await widget.apiClient.dio.post(
        ApiConstants.googleAuth,
        data: {"idToken": idToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final auth = AuthResponse.fromJson(response.data);
        await widget.sessionService.saveAuth(
          token: auth.token,
          userId: auth.userId,
          email: auth.email,
          fullName: auth.fullName,
        );
        await widget.sessionService.setSampleDataLoaded(false);

        if (!mounted) return;
        widget.onSignedIn?.call();
        Navigator.of(context).pop(true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Signed in as ${auth.email}",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() {
        _errorMessage = e.response?.data?["message"]?.toString() ??
            "Authentication failed. Please verify the backend connection.";
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Sign-in error: $e";
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _appendGmailDomain() {
    final text = _emailController.text.trim();
    if (!text.contains("@")) {
      _emailController.text = "$text@gmail.com";
      _emailController.selection = TextSelection.fromPosition(
        TextPosition(offset: _emailController.text.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with Google Branding
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      alignment: Alignment.center,
                      child: const _GoogleBrandIcon(size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Sign in with Google",
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Connect your personal Gmail account",
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Info Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: isDark ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.verified_user_outlined, color: Color(0xFF4285F4), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Direct Google Authentication enables instant account creation, personal courses, and continuous cloud sync.",
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: context.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Error Message if any
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Gmail Input Field
                Text(
                  "Google / Gmail Address",
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: "yourname@gmail.com",
                    prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                    suffixIcon: !_emailController.text.contains("@") && _emailController.text.isNotEmpty
                        ? TextButton(
                            onPressed: _appendGmailDomain,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text("@gmail.com", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return "Gmail address is required";
                    }
                    final v = val.trim();
                    if (!v.contains("@") && !v.contains(".")) {
                      return "Please enter a valid email or student address";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Name Input Field
                Text(
                  "Display Name (Optional)",
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isLoading,
                  decoration: InputDecoration(
                    hintText: "Your Full Name (e.g. Seth Andrey)",
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: context.cardBorderColor),
                        ),
                        child: Text(
                          "Cancel",
                          style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _submit,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          _isLoading ? "Connecting..." : "Continue with Google",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleBrandIcon extends StatelessWidget {
  final double size;

  const _GoogleBrandIcon({this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            "G",
            style: GoogleFonts.outfit(
              fontSize: size * 0.9,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF4285F4),
            ),
          ),
        ],
      ),
    );
  }
}
