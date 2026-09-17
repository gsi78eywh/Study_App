import "audio_speech_interface.dart";

AudioSpeechService getAudioSpeechService() => AudioSpeechStub();

class AudioSpeechStub implements AudioSpeechService {
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<void> speak(String text) async {
    _speaking = true;
    await Future.delayed(const Duration(milliseconds: 300));
    _speaking = false;
  }

  @override
  Future<void> stop() async {
    _speaking = false;
  }
}
