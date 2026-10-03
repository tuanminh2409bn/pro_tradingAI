import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/models/referral_models.dart';

/// Original ProTrading text/card artwork, rendered locally with the active code.
Future<Uint8List> renderReferralPng(
  ReferralIdentity identity, {
  required bool banner,
  required String locale,
}) async {
  ReferralIdentity.fromServerLink(
    code: identity.code,
    link: identity.qrPayload,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = banner ? const Size(1200, 630) : const Size(600, 600);
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = banner ? const Color(0xFF0A1020) : Colors.white,
  );
  final qr = QrPainter(
    data: identity.qrPayload,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  );
  if (banner) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(764, 98, 408, 408),
        const Radius.circular(12),
      ),
      Paint()..color = Colors.white,
    );
    _label(
      canvas,
      'ProTrading AI',
      const Offset(56, 72),
      620,
      52,
      Colors.white,
    );
    _label(
      canvas,
      AppLocalizations.get(locale, 'referral_kit_tagline'),
      const Offset(56, 158),
      640,
      28,
      const Color(0xFFB6C8E2),
    );
    _label(
      canvas,
      AppLocalizations.get(locale, 'referral_code_label'),
      const Offset(56, 310),
      640,
      18,
      const Color(0xFFB6C8E2),
    );
    _label(
      canvas,
      identity.code,
      const Offset(56, 350),
      640,
      27,
      const Color(0xFF8EF0CE),
    );
    _label(
      canvas,
      identity.qrPayload,
      const Offset(56, 422),
      640,
      18,
      Colors.white,
    );
    _label(
      canvas,
      AppLocalizations.get(locale, 'referral_kit_disclaimer'),
      const Offset(56, 545),
      1090,
      18,
      const Color(0xFFB6C8E2),
    );
    canvas.save();
    canvas.translate(812, 146);
    qr.paint(canvas, const Size(312, 312));
    canvas.restore();
  } else {
    canvas.save();
    canvas.translate(64, 64);
    qr.paint(canvas, const Size(472, 472));
    canvas.restore();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Unable to render referral PNG');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void _label(
  Canvas canvas,
  String text,
  Offset offset,
  double width,
  double fontSize,
  Color color,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  painter.paint(canvas, offset);
  painter.dispose();
}
