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
  static const String configuredIosClientId = String.fromEnvironment("GOOGLE_IOS_CLIENT_ID");
  static bool _isValidClientId(String id) =>
      id.trim().isNotEmpty && !id.trim().startsWith("YOUR_");

  static bool get isConfigured => kIsWeb
      ? _isValidClientId(configuredClientId)
      : defaultTargetPlatform == TargetPlatform.iOS
          ? _isValidClientId(configuredClientId) && _isValidClientId(configuredIosClientId)
          : _isValidClientId(configuredClientId);

  GoogleSignIn? _googleSignInInstance;

  GoogleSignIn get _googleSignIn {
    return _googleSignInInstance ??= GoogleSignIn(
      // The web client ID is the ID-token audience expected by the API. On iOS,
      // the native client ID identifies this app while serverClientId requests
      // the same web-audience token for backend verification.
      clientId: kIsWeb
          ? configuredClientId
          : defaultTargetPlatform == TargetPlatform.iOS && configuredIosClientId.isNotEmpty
              ? configuredIosClientId
              : null,
      serverClientId: !kIsWeb && configuredClientId.isNotEmpty ? configuredClientId : null,
      scopes: ["email", "profile"],
    );
  }

  Future<GoogleAuthResult> signIn() async {
    if (!isConfigured) {
      return GoogleAuthResult(
        success: false,
        errorMessage: defaultTargetPlatform == TargetPlatform.iOS
            ? "Google Sign-In is not configured for this iOS build."
            : "Google Sign-In is not configured for this build.",
      );
    }

    try {
      // Clear this app's cached selection first so Google presents its account
      // picker/authorization flow. Google itself decides whether credentials or
      // a second factor must be requested for the selected account.
      await signOut();
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
