import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_cubit.dart';
import '../../../core/utils/png_download.dart';
import '../../../core/utils/referral_video.dart';
import '../../../data/models/referral_models.dart';
import '../referral_kit_renderer.dart';

class ReferralKitCard extends StatefulWidget {
  final ReferralIdentity identity;
  const ReferralKitCard({super.key, required this.identity});
  @override
  State<ReferralKitCard> createState() => _ReferralKitCardState();
}

class _ReferralKitCardState extends State<ReferralKitCard> {
  bool _exporting = false;
  String? _feedback;

  Future<void> _download(bool banner, {bool video = false}) async {
    if (_exporting) return;
    final identity = widget.identity;
    final locale = context.read<LocaleCubit>().state;
    setState(() {
      _exporting = true;
      _feedback = null;
    });
    try {
      final bytes = await renderReferralPng(
        identity,
        banner: banner,
        locale: locale,
      );
      if (!mounted || widget.identity.code != identity.code) return;
      final bool queued;
      if (video) {
        final result = await renderReferralVideo(
          bytes,
          isCancelled: () => !mounted || widget.identity.code != identity.code,
        );
        if (!mounted || widget.identity.code != identity.code) return;
        if (result == null) {
          setState(() => _feedback = 'referral_video_unavailable');
          return;
        }
        queued = await downloadReferralVideo(
          result,
          'protrading-referral-${identity.code}-video',
        );
      } else {
        queued = await downloadPng(
          bytes,
          'protrading-referral-${identity.code}-${banner ? 'banner' : 'qr'}.png',
        );
      }
      if (!mounted || widget.identity.code != identity.code) return;
      setState(
        () => _feedback = queued
            ? 'referral_download_ready'
            : 'referral_download_failed',
      );
    } catch (_) {
      if (mounted && widget.identity.code == identity.code) {
        setState(() => _feedback = 'referral_download_failed');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('referral_kit_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('referral_kit_description'),
          style: const TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        Center(
          child: QrImageView(
            data: widget.identity.qrPayload,
            size: 220,
            padding: const EdgeInsets.all(24),
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            semanticsLabel: context.tr('referral_qr_label'),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _download(false),
              icon: const Icon(Icons.qr_code),
              label: Text(context.tr('referral_download_qr')),
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : () => _download(true),
              icon: const Icon(Icons.download),
              label: Text(context.tr('referral_download_banner')),
            ),
            OutlinedButton.icon(
              onPressed: _exporting || !isReferralVideoSupported()
                  ? null
                  : () => _download(true, video: true),
              icon: const Icon(Icons.movie_outlined),
              label: Text(context.tr('referral_download_video')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            context.tr(
              isReferralVideoSupported()
                  ? 'referral_video_description'
                  : 'referral_video_unavailable',
            ),
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
        if (_exporting)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_feedback != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              context.tr(_feedback!),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
      ],
    ),
  );
}
