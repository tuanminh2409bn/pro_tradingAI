import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';

Widget? communityCharacterCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) {
  if (maxLength == null) return null;
  final label = context
      .tr('community_input_character_count')
      .replaceAll('{count}', '$currentLength')
      .replaceAll('{max}', '$maxLength');
  return Text(
    '$currentLength / $maxLength',
    semanticsLabel: label,
    style: const TextStyle(color: Colors.white54, fontSize: 12),
  );
}
