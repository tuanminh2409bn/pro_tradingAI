import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/referral_models.dart';

void main() {
  group('Canonical referral identity', () {
    test('missing server-provisioned stats expose no fabricated link', () {
      const stats = ReferralStats.unavailable();

      expect(stats.hasReferralLink, isFalse);
      expect(stats.referralLink, isEmpty);
    });

    test('server-issued code produces one canonical link and QR payload', () {
      final identity = ReferralIdentity.fromServerIssuedCode(
        baseUri: Uri.parse('https://protrading.ai/ref/'),
        code: 'PARTNER_2026',
      );

      expect(identity.code, 'PARTNER_2026');
      expect(identity.uri.toString(), 'https://protrading.ai/ref/PARTNER_2026');
      expect(identity.qrPayload, identity.uri.toString());
      expect(Uri.parse(identity.qrPayload), identity.uri);
    });

    test('rejects insecure origins and malformed referral codes', () {
      expect(
        () => ReferralIdentity.fromServerIssuedCode(
          baseUri: Uri.parse('http://protrading.ai/ref/'),
          code: 'PARTNER_2026',
        ),
        throwsArgumentError,
      );
      expect(
        () => ReferralIdentity.fromServerIssuedCode(
          baseUri: Uri.parse('https://protrading.ai/ref/'),
          code: '../another-user',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Marketing Kit preparation', () {
    test(
      'personalizes every approved descriptor with only the active code',
      () {
        final identity = ReferralIdentity.fromServerIssuedCode(
          baseUri: Uri.parse('https://protrading.ai/ref/'),
          code: 'ACTIVE_CODE',
        );
        final result = MarketingKitPreparation.prepare(
          identity: identity,
          templates: [
            MarketingAssetTemplate(
              id: 'banner-1',
              type: MarketingAssetType.banner,
              sourceUri: Uri.parse('https://cdn.protrading.ai/banner-1.png'),
              licenseReference: 'license-banner-1',
              isApproved: true,
              overlayTemplate: 'Trade smarter — {{REFERRAL_CODE}}',
            ),
            MarketingAssetTemplate(
              id: 'video-1',
              type: MarketingAssetType.video,
              sourceUri: Uri.parse('https://cdn.protrading.ai/video-1.mp4'),
              licenseReference: 'license-video-1',
              isApproved: true,
              overlayTemplate: '{{REFERRAL_CODE}}',
            ),
          ],
        );

        expect(result.status, MarketingKitStatus.readyForRenderer);
        expect(result.assets, hasLength(2));
        expect(
          result.assets.every(
            (asset) =>
                asset.referralCode == 'ACTIVE_CODE' &&
                asset.overlayText.contains('ACTIVE_CODE') &&
                !asset.overlayText.contains('{{REFERRAL_CODE}}'),
          ),
          isTrue,
        );
      },
    );

    test(
      'returns explicit unavailable state when no approved asset exists',
      () {
        final identity = ReferralIdentity.fromServerIssuedCode(
          baseUri: Uri.parse('https://protrading.ai/ref/'),
          code: 'ACTIVE_CODE',
        );
        final result = MarketingKitPreparation.prepare(
          identity: identity,
          templates: [
            MarketingAssetTemplate(
              id: 'unapproved-banner',
              type: MarketingAssetType.banner,
              sourceUri: Uri.parse('https://cdn.protrading.ai/banner.png'),
              licenseReference: '',
              isApproved: false,
              overlayTemplate: '{{REFERRAL_CODE}}',
            ),
          ],
        );

        expect(result.status, MarketingKitStatus.unavailable);
        expect(result.unavailableReason, 'no_approved_marketing_assets');
        expect(result.assets, isEmpty);
      },
    );

    test('fails closed when an approved template cannot embed the code', () {
      final identity = ReferralIdentity.fromServerIssuedCode(
        baseUri: Uri.parse('https://protrading.ai/ref/'),
        code: 'ACTIVE_CODE',
      );
      expect(
        () => MarketingKitPreparation.prepare(
          identity: identity,
          templates: [
            MarketingAssetTemplate(
              id: 'bad-banner',
              type: MarketingAssetType.banner,
              sourceUri: Uri.parse('https://cdn.protrading.ai/banner.png'),
              licenseReference: 'license-banner',
              isApproved: true,
              overlayTemplate: 'Missing required token',
            ),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}
