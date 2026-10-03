import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_cubit.dart';
import '../../../../core/utils/browser_speech.dart';

class JournalAudioButton extends StatefulWidget {
  final String insight;
  final BrowserSpeech? speech;

  const JournalAudioButton({super.key, required this.insight, this.speech});

  @override
  State<JournalAudioButton> createState() => _JournalAudioButtonState();
}

class _JournalAudioButtonState extends State<JournalAudioButton> {
  late BrowserSpeech _speech = widget.speech ?? BrowserSpeech();
  bool _playing = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant JournalAudioButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.insight != widget.insight ||
        oldWidget.speech != widget.speech) {
      ++_generation;
      _speech.stop();
      _speech = widget.speech ?? BrowserSpeech();
      _playing = false;
      _failed = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _speech.stop();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      ++_generation;
      _speech.stop();
      setState(() => _playing = false);
      return;
    }
    final language = context.read<LocaleCubit>().state == 'vi'
        ? 'vi-VN'
        : 'en-US';
    final generation = ++_generation;
    final started = _speech.speak(widget.insight, language, () {
      if (mounted && generation == _generation) {
        ++_generation;
        setState(() => _playing = false);
      }
    });
    if (generation == _generation) {
      setState(() {
        _playing = started;
        _failed = !started;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final available =
        !_failed &&
        _speech.isAvailable &&
        widget.insight.trim().isNotEmpty &&
        widget.insight != '__NO_TRADES__';
    final label = !available
        ? context.tr('journal_audio_unavailable')
        : _playing
        ? context.tr('journal_stop_voice')
        : context.tr('journal_play_voice');
    return IconButton(
      key: const ValueKey('journal-audio-control'),
      tooltip: label,
      onPressed: available ? _toggle : null,
      icon: Icon(
        !available
            ? Icons.volume_off
            : _playing
            ? Icons.stop
            : Icons.volume_up,
        size: 16,
      ),
      disabledColor: Colors.white24,
    );
  }
}
