import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/core/utils/browser_speech.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_audio_button.dart';

class FakeSpeech extends BrowserSpeech {
  FakeSpeech(this.supported);

  final bool supported;
  int starts = 0;
  int stops = 0;
  String? spokenText;
  String? spokenLanguage;
  VoidCallback? finish;

  @override
  bool get isAvailable => supported;

  @override
  bool speak(String text, String language, void Function() onDone) {
    starts++;
    spokenText = text;
    spokenLanguage = language;
    finish = onDone;
    return true;
  }

  @override
  void stop() => stops++;
}

void main() {
  Future<void> show(
    WidgetTester tester,
    String insight,
    FakeSpeech speech,
  ) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LocaleCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: JournalAudioButton(insight: insight, speech: speech),
          ),
        ),
      ),
    );
  }

  testWidgets('real insight can play, stop, and release on completion', (
    tester,
  ) async {
    final speech = FakeSpeech(true);
    await show(tester, 'Two losing trades followed the same hour.', speech);
    expect(find.byTooltip('Play voice analysis'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-audio-control')));
    await tester.pump();
    expect(speech.spokenText, 'Two losing trades followed the same hour.');
    expect(speech.spokenLanguage, 'en-US');
    expect(find.byTooltip('Stop voice analysis'), findsOneWidget);
    speech.finish!();
    await tester.pump();
    expect(find.byTooltip('Play voice analysis'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-audio-control')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('journal-audio-control')));
    await tester.pump();
    expect(speech.starts, 2);
    expect(speech.stops, 1);
  });

  testWidgets('missing trades or browser speech disables playback', (
    tester,
  ) async {
    final speech = FakeSpeech(true);
    await show(tester, '__NO_TRADES__', speech);
    expect(find.byTooltip('Audio advice is unavailable'), findsOneWidget);
    await show(tester, 'A real insight', FakeSpeech(false));
    expect(find.byTooltip('Audio advice is unavailable'), findsOneWidget);
  });
}
