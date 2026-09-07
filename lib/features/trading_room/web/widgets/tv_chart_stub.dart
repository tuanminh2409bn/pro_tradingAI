// Non-web stub — TradingView Widget only supported on Flutter Web
import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';

class TradingViewChart extends StatelessWidget {
  final String symbol;
  final String interval;

  const TradingViewChart({
    required this.symbol,
    required this.interval,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: Text(
          'Chart available on Web only',
          style: TextStyle(color: Colors.white38),
        ),
      ),
    );
  }
}
