import "package:flutter/foundation.dart";
import "package:google_sign_in/google_sign_in.dart";

class GoogleAuthResult {
  final bool success;
  final String? idToken;
  final String? email;
  final String? displayName;
  final String? errorMessage;

  GoogleAuthResult({
    required this.success,
    this.idToken,
    this.email,
    this.displayName,
    this.errorMessage,
  });
}

class GoogleAuthService {
  static final GoogleAuthService instance = GoogleAuthService._();
  GoogleAuthService._();

  static const String configuredClientId = String.fromEnvironment("GOOGLE_CLIENT_ID");

  GoogleSignIn? _googleSignInInstance;

  GoogleSignIn get _googleSignIn {
    return _googleSignInInstance ??= GoogleSignIn(
      clientId: kIsWeb && configuredClientId.isNotEmpty ? configuredClientId : null,
      scopes: ["email", "profile"],
    );
  }

  Future<GoogleAuthResult> signIn() async {
    // On web, google_sign_in_web asserts that clientId != null.
    // If not configured, provide a user-friendly message rather than an assertion crash.
    if (kIsWeb && configuredClientId.isEmpty) {
      return GoogleAuthResult(
        success: false,
        errorMessage: "Google Sign-In on Web requires GOOGLE_CLIENT_ID to be configured. Please sign in with email and password or use the Demo Student Account.",
      );
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return GoogleAuthResult(
          success: false,
          errorMessage: "Google Sign-In was cancelled by user.",
        );
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        return GoogleAuthResult(
          success: false,
          errorMessage: "Google did not provide an ID token. Ensure OAuth client ID is configured for your platform.",
        );
      }

      return GoogleAuthResult(
        success: true,
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
      );
    } catch (e) {
      debugPrint("[GoogleAuthService] Sign-in error: $e");
      return GoogleAuthResult(
        success: false,
        errorMessage: "Google Sign-In failed: ${e.toString().replaceAll("Exception:", "").trim()}",
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
