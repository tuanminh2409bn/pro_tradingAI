import 'dart:js_interop';

@JS('speechSynthesis')
external _SpeechSynthesis? get _synthesis;

@JS()
extension type _SpeechSynthesis(JSObject _) implements JSObject {
  external void cancel();
  external void speak(_SpeechUtterance utterance);
}

@JS('SpeechSynthesisUtterance')
extension type _SpeechUtterance._(JSObject _) implements JSObject {
  external _SpeechUtterance(String text);
  external set lang(String value);
  external set onend(JSFunction callback);
  external set onerror(JSFunction callback);
}

class BrowserSpeech {
  bool get isAvailable => _synthesis != null;

  bool speak(String text, String language, void Function() onDone) {
    final synth = _synthesis;
    if (synth == null || text.trim().isEmpty) return false;
    try {
      synth.cancel();
      final utterance = _SpeechUtterance(text)
        ..lang = language
        ..onend = (() => onDone()).toJS
        ..onerror = (() => onDone()).toJS;
      synth.speak(utterance);
      return true;
    } catch (_) {
      return false;
    }
  }

  void stop() => _synthesis?.cancel();
}
