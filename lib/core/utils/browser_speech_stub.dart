class BrowserSpeech {
  bool get isAvailable => false;

  bool speak(String text, String language, void Function() onDone) => false;

  void stop() {}
}
