import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/utils/referral_video.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/features/referral/referral_kit_renderer.dart';

void main() {
  final mp4 = Uint8List.fromList([
    0,
    0,
    0,
    24,
    102,
    116,
    121,
    112,
    105,
    115,
    111,
    109,
  ]);
  final webm = Uint8List.fromList([
    0x1a,
    0x45,
    0xdf,
    0xa3,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  test('container determines extension and rejects an unrelated MIME', () {
    expect(ReferralVideo(mp4, 'video/mp4;codecs=avc1').extension, 'mp4');
    expect(ReferralVideo(webm, 'video/webm;codecs=vp8').extension, 'webm');
    expect(
      () => ReferralVideo(Uint8List(12), 'image/png'),
      throwsArgumentError,
    );
    expect(() => ReferralVideo(webm, 'video/mp4'), throwsArgumentError);
    expect(() => ReferralVideo(mp4, 'video/webm'), throwsArgumentError);
    expect(
      () => ReferralVideo(Uint8List(20 * 1024 * 1024 + 1), 'video/mp4'),
      throwsArgumentError,
    );
  });

  test('invalid input is rejected before recording or download', () async {
    expect(await renderReferralVideo(Uint8List(0)), isNull);
    expect(await renderReferralVideo(Uint8List(5 * 1024 * 1024 + 1)), isNull);
    expect(
      await downloadReferralVideo(ReferralVideo(mp4, 'video/mp4'), '../other'),
      isFalse,
    );
  });

  test(
    'unsupported platform exposes unavailable instead of pretending to export',
    () async {
      if (isReferralVideoSupported()) return;
      expect(
        await renderReferralVideo(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        ),
        isNull,
      );
      expect(
        await downloadReferralVideo(
          ReferralVideo(webm, 'video/webm'),
          'referral',
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'Chrome cancels an active recording and then encodes a real video',
    (tester) async {
      expect(isReferralVideoSupported(), isTrue);
      await tester.runAsync(() async {
        final identity = ReferralIdentity.fromServerLink(
          code: 'abcdefghijklmnopqrstuvwx',
          link:
              'https://protrading-ai-2026.web.app/?ref=abcdefghijklmnopqrstuvwx',
        );
        final png = await renderReferralPng(
          identity,
          banner: true,
          locale: 'vi',
        );
        final cancellation = Stopwatch()..start();
        expect(
          await renderReferralVideo(
            png,
            isCancelled: () => cancellation.elapsedMilliseconds > 200,
          ),
          isNull,
        );
        expect(cancellation.elapsedMilliseconds, lessThan(3000));
        final result = await renderReferralVideo(png);
        expect(result, isNotNull);
        expect(result!.bytes.length, greaterThan(2000));
        expect(result.bytes.length, lessThan(20 * 1024 * 1024));
        expect(result.extension, anyOf('mp4', 'webm'));
        if (result.extension == 'mp4') {
          expect(result.mimeType.toLowerCase(), contains('avc1'));
        }
      });
    },
    skip: !kIsWeb,
  );
}
