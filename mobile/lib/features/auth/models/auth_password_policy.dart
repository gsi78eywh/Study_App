import "dart:convert";

class AuthPasswordPolicy {
  static const int minimumLength = 12;
  static const int maximumLength = 128;
  static const int maximumUtf8Bytes = 72;

  static const Set<String> _commonPasswords = {
    "password123!",
    "password123",
    "password1!",
    "qwerty123456",
    "letmein12345",
    "welcome12345",
    "admin123456",
    "iloveyou123",
    "123456789012",
    "studyapp123",
  };

  static String? errorFor(String? password) {
    if (password == null || password.isEmpty) return "Password is required.";
    if (password.runes.length < minimumLength) {
      return "Use at least $minimumLength characters.";
    }
    if (password.runes.length > maximumLength) {
      return "Use no more than $maximumLength characters.";
    }
    if (utf8.encode(password).length > maximumUtf8Bytes) {
      return "Use at most $maximumUtf8Bytes UTF-8 bytes.";
    }
    if (_commonPasswords.contains(password.trim().toLowerCase())) {
      return "Choose a less common password or a longer passphrase.";
    }
    return null;
  }
}
