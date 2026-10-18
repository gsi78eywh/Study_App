import "dart:typed_data";

class ClipboardImagePayload {
  final Uint8List bytes;
  final String mimeType;
  final String name;

  const ClipboardImagePayload({
    required this.bytes,
    required this.mimeType,
    required this.name,
  });

  String get filename => name;
}

Future<ClipboardImagePayload?> readClipboardScreenshotImpl() async {
  return null;
}
