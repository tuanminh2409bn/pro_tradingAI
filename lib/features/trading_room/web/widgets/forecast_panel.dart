import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/trading_models.dart';

class ForecastPanel extends StatelessWidget {
  final TradingSignal? signal;

  const ForecastPanel({super.key, required this.signal});

  @override
  Widget build(BuildContext context) {
    final forecast = signal?.forecastText?.trim();
    if (forecast == null || forecast.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('forecast-panel'),
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('forecast_title'),
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              forecast,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
