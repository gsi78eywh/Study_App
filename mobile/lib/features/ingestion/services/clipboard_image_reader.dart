import "clipboard_image_stub.dart"
    if (dart.library.js_interop) "clipboard_image_web.dart";

export "clipboard_image_stub.dart" show ClipboardImagePayload;

Future<ClipboardImagePayload?> readClipboardScreenshot() =>
    readClipboardScreenshotImpl();

Future<ClipboardImagePayload?> readClipboardImage() =>
    readClipboardScreenshotImpl();
