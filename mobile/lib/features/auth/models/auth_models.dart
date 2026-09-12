class AuthResponse {
  final String userId;
  final String email;
  final String fullName;
  final String token;
  final DateTime expiresAt;

  AuthResponse({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.token,
    required this.expiresAt,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      userId: json["userId"]?.toString() ?? "",
      email: json["email"] ?? "",
      fullName: json["fullName"] ?? "",
      token: json["token"] ?? "",
      expiresAt: DateTime.tryParse(json["expiresAt"] ?? "") ?? DateTime.now(),
    );
  }
}
