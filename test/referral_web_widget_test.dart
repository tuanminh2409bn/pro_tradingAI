import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:protrading_ai/core/utils/referral_video.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';
import 'package:protrading_ai/features/referral/web/referral_web_page.dart';

final _identity = ReferralIdentity.fromServerLink(
  code: 'abcdefghijklmnopqrstuvwx',
  link: 'https://protrading-ai-2026.web.app/?ref=abcdefghijklmnopqrstuvwx',
);

class _Repository extends Fake implements ReferralRepository {
  bool fail = false;
  int provisions = 0;
  @override
  Future<ReferralIdentity> provisionIdentity() async {
    ++provisions;
    if (fail) throw StateError('unavailable');
    return _identity;
  }

  @override
  Stream<ReferralStats> getReferralStats(String uid) => Stream.value(
    ReferralStats.fromJson({
      'referralCode': _identity.code,
      'referralLink': _identity.qrPayload,
      'registeredInviteCount': 3,
    }),
  );
  @override
  Stream<List<MemberNode>> getNetwork(String uid) => Stream.value(const []);
  @override
  Stream<List<RewardTransaction>> getRewardHistory(String uid) =>
      Stream.value(const []);
}

Widget _page(
  _Repository repository, {
  String? message,
  VoidCallback? onRetry,
}) => RepositoryProvider<ReferralRepository>.value(
  value: repository,
  child: BlocProvider(
    create: (_) => LocaleCubit()..setLanguage('vi'),
    child: MaterialApp(
      home: ReferralWebPage(
        userId: 'alice',
        registrationMessageKey: message,
        onRegistrationRetry: onRetry,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    '390px Referral shows real QR/link, copies it and labels money unavailable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_page(_Repository()));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Chưa có phần thưởng và số thành viên trả phí được xác minh.',
        ),
        findsOneWidget,
      );
      expect(find.text('USD 0.00'), findsNothing);
      expect(find.text('ĐĂNG KÝ TỪ LINK CỦA BẠN'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Tải video'), findsOneWidget);
      expect(
        find.textContaining(
          isReferralVideoSupported()
              ? 'Video 6 giây không âm thanh'
              : 'Trình duyệt này chưa hỗ trợ xuất video',
        ),
        findsOneWidget,
      );
      final copy = find.byTooltip('Sao chép link giới thiệu');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied, _identity.qrPayload);
      expect(find.text('Đã sao chép liên kết giới thiệu.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provision failure exposes retry instead of a fake code', (
    tester,
  ) async {
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(_page(repository));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    repository.fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration feedback can retry without reprovisioning the page',
    (tester) async {
      final repository = _Repository();
      var retries = 0;
      await tester.pumpWidget(_page(repository));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _page(
          repository,
          message: 'referral_registration_unavailable',
          onRetry: () => retries++,
        ),
      );
      await tester.pumpAndSettle();
      final retry = find.text('Thử lại ghi nhận giới thiệu');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      expect(retries, 1);
      expect(repository.provisions, 1);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
