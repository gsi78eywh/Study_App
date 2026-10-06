import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";

import "../../../core/constants/api_constants.dart";
import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../models/auth_models.dart";

/// Local-development Google sign-in.
///
/// SECURITY: this dialog sends an unverified `dev-google:email|name` token. The
/// backend accepts that format ONLY when it runs in the Development environment,
/// and this dialog is only offered in debug builds ([isAvailable]). Release builds
/// must use the real Google SDK flow in `GoogleAuthService`.
class GoogleSignInDialog extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;
  final String? initialEmail;

  const GoogleSignInDialog({
    super.key,
    required this.apiClient,
    required this.sessionService,
    this.initialEmail,
  });

  /// Token prefix understood by the backend's Development-only sign-in path.
  static const String devTokenPrefix = "dev-google:";

  /// Overridable in tests. Defaults to debug builds only.
  @visibleForTesting
  static bool? debugAvailabilityOverride;

  static bool get isAvailable => debugAvailabilityOverride ?? kDebugMode;

  static final RegExp _emailPattern = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$");

  /// Returns null when [value] is a valid email, otherwise a friendly error.
  static String? validateEmail(String? value) {
    final v = value?.trim() ?? "";
    if (v.isEmpty) return "Please type your Gmail address";
    if (v.length > 254) return "That email is too long";
    final candidate = v.contains("@") ? v : "$v@gmail.com";
    if (!_emailPattern.hasMatch(candidate)) return "That doesn't look like an email address";
    return null;
  }

  /// Builds the dev token, stripping the `|` separator from the name so it can't
  /// be used to smuggle extra fields.
  static String buildDevToken(String email, String fullName) {
    final safeName = fullName.replaceAll("|", " ").trim();
    return "$devTokenPrefix${email.trim().toLowerCase()}|$safeName";
  }

  static Future<bool> show(
    BuildContext context, {
    required ApiClient apiClient,
    required SessionService sessionService,
    String? initialEmail,
  }) async {
    if (!isAvailable) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => GoogleSignInDialog(
        apiClient: apiClient,
        sessionService: sessionService,
        initialEmail: initialEmail,
      ),
    );
    return result ?? false;
  }

  @override
  State<GoogleSignInDialog> createState() => _GoogleSignInDialogState();
}

class _GoogleSignInDialogState extends State<GoogleSignInDialog> {
  static const Color _googleBlue = Color(0xFF4285F4);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _nameController;
  bool _nameEditedByUser = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final sessionEmail = widget.sessionService.email;
    final initEmail = (widget.initialEmail?.isNotEmpty ?? false)
        ? widget.initialEmail!
        : (sessionEmail != null && !sessionEmail.contains("studyapp.local") ? sessionEmail : "");
    _emailController = TextEditingController(text: initEmail);
    _nameController = TextEditingController(text: _nameFromEmail(initEmail));
    _emailController.addListener(_onEmailChanged);
  }

  void _onEmailChanged() {
    // Keep the suggested name in sync until the student types their own.
    if (!_nameEditedByUser) {
      _nameController.text = _nameFromEmail(_emailController.text);
    }
    setState(() {}); // refresh the "@gmail.com" helper button
  }

  static String _nameFromEmail(String email) {
    if (!email.contains("@")) return "";
    final prefix = email.split("@").first.replaceAll(RegExp(r"[._\-]+"), " ").trim();
    return prefix
        .split(" ")
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(" ");
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
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
      fullName = _nameFromEmail(email);
      if (fullName.isEmpty) fullName = "Google Student";
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        ApiConstants.googleAuth,
        data: {"idToken": GoogleSignInDialog.buildDevToken(email, fullName)},
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
        // Capture the messenger before popping; the dialog context goes away after pop.
        final messenger = ScaffoldMessenger.maybeOf(context);
        Navigator.of(context).pop(true);
        messenger?.showSnackBar(
          SnackBar(
            content: Text("Signed in as ${auth.email}", style: const TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.accent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final status = e.response?.statusCode;
      setState(() {
        if (status == 401) {
          _errorMessage = "This server only accepts real Google sign-in. "
              "Please use your email and password instead.";
        } else if (data is Map && data["message"] != null) {
          _errorMessage = data["message"].toString();
        } else {
          _errorMessage = "We couldn't reach the server. Check your connection and try again.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = "Something went wrong. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _appendGmailDomain() {
    final text = _emailController.text.trim();
    if (text.isNotEmpty && !text.contains("@")) {
      _emailController.text = "$text@gmail.com";
      _emailController.selection = TextSelection.collapsed(offset: _emailController.text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showGmailHelper = _emailController.text.isNotEmpty && !_emailController.text.contains("@");

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.secondaryBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.cardBorderColor),
                        ),
                        alignment: Alignment.center,
                        child: ExcludeSemantics(
                          child: Text(
                            "G",
                            style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900, color: _googleBlue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                "Sign in with Google",
                                style: GoogleFonts.outfit(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Local test sign-in",
                              style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key("google_dialog_close"),
                        tooltip: "Close",
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.developer_mode_rounded, color: Color(0xFFB45309), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Developer mode: this skips Google's password check and only works "
                            "with a local development server. Real app builds use Google's secure sign-in.",
                            style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        key: const Key("google_dialog_error"),
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  TextFormField(
                    key: const Key("google_dialog_email"),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    autofocus: true,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: "Gmail address",
                      hintText: "yourname@gmail.com",
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      suffixIcon: showGmailHelper
                          ? TextButton(
                              onPressed: _appendGmailDomain,
                              child: const Text("@gmail.com", style: TextStyle(fontWeight: FontWeight.bold)),
                            )
                          : null,
                    ),
                    validator: GoogleSignInDialog.validateEmail,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key("google_dialog_name"),
                    controller: _nameController,
                    enabled: !_isLoading,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.done,
                    maxLength: 150,
                    onChanged: (_) => _nameEditedByUser = true,
                    onFieldSubmitted: (_) => _isLoading ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: "Your name (optional)",
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      counterText: "",
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: context.cardBorderColor),
                          ),
                          child: Text("Cancel", style: TextStyle(color: context.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          key: const Key("google_dialog_submit"),
                          onPressed: _isLoading ? null : _submit,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: Text(
                            _isLoading ? "Signing in..." : "Continue",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _googleBlue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
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
      ),
    );
  }
}
