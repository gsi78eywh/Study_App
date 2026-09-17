abstract class AudioSpeechService {
  bool get isSpeaking;
  Future<void> speak(String text);
  Future<void> stop();
}
