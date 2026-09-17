// ignore: avoid_web_libraries_in_flutter
import "dart:html" as html;
import "audio_speech_interface.dart";

AudioSpeechService getAudioSpeechService() => AudioSpeechWeb();

class AudioSpeechWeb implements AudioSpeechService {
  @override
  bool get isSpeaking => html.window.speechSynthesis?.speaking ?? false;

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      final synth = html.window.speechSynthesis;
      if (synth == null) return;
      synth.cancel();
      final utterance = html.SpeechSynthesisUtterance(text.trim())
        ..rate = 0.92 // slightly slower, clear pace for young elementary learners
        ..pitch = 1.05
        ..lang = "en-US";
      synth.speak(utterance);
    } catch (_) {
      // Fallback gracefully if speech synthesis not permitted
    }
  }

  @override
  Future<void> stop() async {
    try {
      html.window.speechSynthesis?.cancel();
    } catch (_) {}
  }
}
