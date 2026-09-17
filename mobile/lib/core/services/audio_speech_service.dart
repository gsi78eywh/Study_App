import "package:flutter/foundation.dart";
import "speech/audio_speech_interface.dart";
import "speech/audio_speech_stub.dart"
    if (dart.library.html) "speech/audio_speech_web.dart";

/// Reactive Audio Speech Assist service for young learners (Grades 1-6)
/// and universal accessibility per DSWD child-friendly guidelines.
class AudioSpeechHelper extends ChangeNotifier {
  static final AudioSpeechHelper instance = AudioSpeechHelper._();
  late final AudioSpeechService _service;
  String? _currentlySpeakingText;

  AudioSpeechHelper._() {
    _service = getAudioSpeechService();
  }

  bool get isSpeaking => _currentlySpeakingText != null;
  String? get currentText => _currentlySpeakingText;

  bool isSpeakingThis(String text) => _currentlySpeakingText == text;

  Future<void> speak(String text) async {
    final clean = text.replaceAll(RegExp(r'[*#_`•\-]'), ' ').trim();
    if (clean.isEmpty) return;

    if (_currentlySpeakingText == clean) {
      await stop();
      return;
    }

    _currentlySpeakingText = clean;
    notifyListeners();

    await _service.speak(clean);

    // After reasonable read-time, reset indicator
    final wordCount = clean.split(RegExp(r'\s+')).length;
    final estimatedDurationSec = (wordCount / 2.2).clamp(2.0, 30.0);
    Future.delayed(Duration(seconds: estimatedDurationSec.round()), () {
      if (_currentlySpeakingText == clean) {
        _currentlySpeakingText = null;
        notifyListeners();
      }
    });
  }

  Future<void> stop() async {
    _currentlySpeakingText = null;
    notifyListeners();
    await _service.stop();
  }
}
