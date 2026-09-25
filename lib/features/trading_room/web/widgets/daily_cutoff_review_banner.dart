import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/localization/locale_cubit.dart';
import '../../../../data/models/trading_models.dart';

class DailyCutoffReviewBanner extends StatefulWidget {
  final Future<DailyCutoffStatus> Function() review;
  final Future<DailyCutoffStatus> Function() acknowledge;

  const DailyCutoffReviewBanner({
    super.key,
    required this.review,
    required this.acknowledge,
  });

  @override
  State<DailyCutoffReviewBanner> createState() =>
      _DailyCutoffReviewBannerState();
}

class _DailyCutoffReviewBannerState extends State<DailyCutoffReviewBanner> {
  bool _busy = false;

  String _message(String key) =>
      AppLocalizations.get(context.read<LocaleCubit>().state, key);

  Future<void> _openReview() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await widget.review();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.tr('cutoff_review_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dialogContext.tr('cutoff_review_body')),
              const SizedBox(height: 12),
              Text(
                '${dialogContext.tr('cutoff_session')}: ${status.sessionDate ?? '—'}',
              ),
              Text(
                '${dialogContext.tr('cutoff_realized')}: ${status.realizedPnl?.toStringAsFixed(2) ?? '—'}',
              ),
              Text(
                '${dialogContext.tr('cutoff_floating')}: ${status.floatingPnl?.toStringAsFixed(2) ?? '—'}',
              ),
              Text(
                '${dialogContext.tr('cutoff_limit')}: ${status.lossLimit?.toStringAsFixed(2) ?? '—'}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.tr('cancel')),
            ),
            TextButton(
              onPressed: status.acknowledged
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.tr('cutoff_acknowledge')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await widget.acknowledge();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message('cutoff_acknowledged_notice'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message('cutoff_review_unavailable'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bear.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.lock_clock, color: AppColors.bear),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('cutoff_locked_notice'))),
            TextButton(
              key: const ValueKey('cutoff-review'),
              onPressed: _busy ? null : _openReview,
              child: Text(context.tr('cutoff_review_action')),
            ),
          ],
        ),
      ),
    );
  }
}
