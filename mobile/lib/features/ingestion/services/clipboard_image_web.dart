import "dart:convert";
import "dart:js_interop";
import "dart:typed_data";
import "clipboard_image_stub.dart";

export "clipboard_image_stub.dart" show ClipboardImagePayload;

@JS("studyAppReadClipboardImage")
external JSPromise<JSString>? _jsReadClipboardImage();

Future<ClipboardImagePayload?> readClipboardScreenshotImpl() async {
  try {
    final promise = _jsReadClipboardImage();
    if (promise == null) return null;
    final jsStr = await promise.toDart;
    final raw = jsStr.toDart.trim();
    if (raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final base64Str = map["base64"]?.toString() ?? "";
    if (base64Str.isEmpty) return null;
    final bytes = base64Decode(base64Str);
    return ClipboardImagePayload(
      bytes: Uint8List.fromList(bytes),
      mimeType: map["mimeType"]?.toString() ?? "image/png",
      name: map["name"]?.toString() ?? "pasted_screenshot.png",
    );
  } catch (_) {
    return null;
  }
}

