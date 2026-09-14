import "dart:convert";
import "dart:typed_data";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:study_app_mobile/core/network/api_client.dart";
import "package:study_app_mobile/core/services/session_service.dart";
import "package:study_app_mobile/features/ai_tutor/screens/ai_tutor_screen.dart";

class MockAiTutorHttpAdapter implements HttpClientAdapter {
  String? lastCapturedRequestBody;
  String? lastCapturedApiKeyHeader;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastCapturedApiKeyHeader = options.headers["X-Gemini-ApiKey"]?.toString();
    if (options.data != null) {
      lastCapturedRequestBody = jsonEncode(options.data);
    }

    final responseMap = {
      "reply": "### 🚀 Flutter Development Setup\n\nRun `flutter doctor -v` and `flutter create app`.",
      "modelUsed": "Built-In Academic Engine",
      "timestamp": DateTime.now().toIso8601String(),
    };

    return ResponseBody.fromString(
      jsonEncode(responseMap),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets("AiTutorScreen renders header, key indicator, and built-in model tag without key", (WidgetTester tester) async {
    final sessionService = await SessionService.init();
    final apiClient = ApiClient(sessionService);
    final mockAdapter = MockAiTutorHttpAdapter();
    apiClient.dio.httpClientAdapter = mockAdapter;

    await tester.pumpWidget(MaterialApp(
      home: AiTutorScreen(
        apiClient: apiClient,
        courses: const [],
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Title & Subtitle
    expect(find.text("Gemini Study Tutor"), findsOneWidget);
    expect(find.text("Google Gemini Multimodal AI Engine"), findsOneWidget);

    // Verify key indicator shows "API Key" when no key configured
    expect(find.text("API Key"), findsOneWidget);

    // Verify default initial greeting shows "Built-In Academic Engine"
    expect(find.text("Built-In Academic Engine"), findsOneWidget);
  });

  testWidgets("AiTutorScreen allows opening Gemini Key dialog and saving key", (WidgetTester tester) async {
    final sessionService = await SessionService.init();
    final apiClient = ApiClient(sessionService);
    final mockAdapter = MockAiTutorHttpAdapter();
    apiClient.dio.httpClientAdapter = mockAdapter;

    await tester.pumpWidget(MaterialApp(
      home: AiTutorScreen(
        apiClient: apiClient,
        courses: const [],
      ),
    ));
    await tester.pumpAndSettle();

    // Tap on API Key button
    await tester.tap(find.text("API Key"));
    await tester.pumpAndSettle();

    // Dialog should be open
    expect(find.text("Google Gemini API Key"), findsOneWidget);
    expect(find.text("Save Key"), findsOneWidget);

    // Enter a mock Gemini Key into the dialog TextField
    await tester.enterText(find.widgetWithText(TextField, "Gemini API Key"), "AIzaSyLiveTestKey123");
    await tester.tap(find.text("Save Key"));
    await tester.pumpAndSettle();

    // Verify key is saved in SessionService
    expect(sessionService.geminiApiKey, equals("AIzaSyLiveTestKey123"));

    // Key badge should now say "Cloud AI"
    expect(find.text("Cloud AI"), findsOneWidget);
  });

  testWidgets("AiTutorScreen sends question with apiKey and receives synthesized reply", (WidgetTester tester) async {
    final sessionService = await SessionService.init();
    await sessionService.setGeminiApiKey("AIzaSyLiveTestKey123");
    final apiClient = ApiClient(sessionService);
    final mockAdapter = MockAiTutorHttpAdapter();
    apiClient.dio.httpClientAdapter = mockAdapter;

    await tester.pumpWidget(MaterialApp(
      home: AiTutorScreen(
        apiClient: apiClient,
        courses: const [],
      ),
    ));
    await tester.pumpAndSettle();

    // Enter prompt into chat input
    final inputFinder = find.byType(TextField).last;
    await tester.enterText(inputFinder, "generate flutter setup");
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    // Verify user message appears
    expect(find.text("generate flutter setup"), findsOneWidget);

    // Verify tutor reply appears
    expect(find.textContaining("Flutter Development Setup"), findsOneWidget);

    // Verify adapter captured the apiKey in request
    expect(mockAdapter.lastCapturedRequestBody, contains("AIzaSyLiveTestKey123"));
    expect(mockAdapter.lastCapturedApiKeyHeader, equals("AIzaSyLiveTestKey123"));
  });
}
