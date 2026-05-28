import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_state.dart';

class LiveDataBar extends StatelessWidget {
  const LiveDataBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        double balance = 0.0;
        double equity = 0.0;
        int leverage = 500;
        double spread = 0.0;
        double swap = 0.0;

        if (state is TradingRoomLoaded) {
          balance = state.riskConfig?.balance ?? state.account.balance;
          equity = state.account.equity > 0 ? state.account.equity : balance;
          leverage = state.account.leverage;
          spread = state.spread;
          swap = state.swap;
        }

        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Row(
            children: [
              _DataBox(
                label: 'BALANCE',
                value: '\$${_formatNumber(balance)}',
                valueColor: AppColors.primary,
              ),
              _divider(),
              _DataBox(
                label: 'EQUITY',
                value: '\$${_formatNumber(equity)}',
                valueColor: equity >= balance ? AppColors.primary : AppColors.bear,
              ),
              _divider(),
              _DataBox(
                label: 'LEVERAGE',
                value: '1:$leverage',
                valueColor: AppColors.accent,
              ),
              _divider(),
              _DataBox(
                label: 'SPREAD',
                value: '${spread.toStringAsFixed(1)} pips',
                valueColor: Colors.white70,
              ),
              _divider(),
              _DataBox(
                label: 'SWAP',
                value: '${swap >= 0 ? '+' : ''}${swap.toStringAsFixed(2)}',
                valueColor: swap >= 0 ? AppColors.primary : AppColors.bear,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatNumber(double num) {
    if (num >= 1000) {
      return num.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    }
    return num.toStringAsFixed(2);
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _DataBox extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _DataBox({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.45),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
