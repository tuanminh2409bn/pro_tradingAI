import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/trading_models.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_event.dart';
import '../../bloc/trading_room_state.dart';

class InputConstraintModal extends StatefulWidget {
  const InputConstraintModal({super.key});

  /// Show as dialog overlay
  static Future<void> show(BuildContext context) {
    final state = context.read<TradingRoomBloc>().state;
    final isConfigured = state is TradingRoomLoaded && state.isRiskConfigured;
    return showDialog(
      context: context,
      barrierDismissible: isConfigured,
      barrierColor: Colors.black87,
      builder: (_) => BlocProvider.value(
        value: context.read<TradingRoomBloc>(),
        child: const InputConstraintModal(),
      ),
    );
  }

  @override
  State<InputConstraintModal> createState() => _InputConstraintModalState();
}

class _InputConstraintModalState extends State<InputConstraintModal>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  final _riskController = TextEditingController(text: '1.0');
  final _maxLossController = TextEditingController(text: '5.0');

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isHoveringButton = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<TradingRoomBloc>().state;
    if (state is TradingRoomLoaded && state.riskConfig != null) {
      final config = state.riskConfig!;
      _balanceController.text = config.balance.toStringAsFixed(0);
      _riskController.text = config.riskPerTrade.toStringAsFixed(1);
      _maxLossController.text = config.maxDailyLoss.toStringAsFixed(1);
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _riskController.dispose();
    _maxLossController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    final balance = double.tryParse(_balanceController.text) ?? 0;
    final risk = double.tryParse(_riskController.text) ?? 1.0;
    final maxLoss = double.tryParse(_maxLossController.text) ?? 5.0;

    final config = RiskConfig(
      balance: balance,
      riskPerTrade: risk,
      maxDailyLoss: maxLoss,
    );

    context.read<TradingRoomBloc>().add(SaveRiskConfig(config));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildCard(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      width: 440,
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 48,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 28),
                    _buildInputField(
                      context: context,
                      controller: _balanceController,
                      labelKey: 'risk_config_balance',
                      hintKey: 'risk_config_balance_hint',
                      prefix: '\$ ',
                      validator: (v) {
                        final val = double.tryParse(v ?? '');
                        if (val == null || val <= 0) {
                          return context.tr('risk_config_balance_error');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      context: context,
                      controller: _riskController,
                      labelKey: 'risk_config_risk',
                      hintKey: 'risk_config_risk_hint',
                      suffix: '%',
                      validator: (v) {
                        final val = double.tryParse(v ?? '');
                        if (val == null || val < 0.1 || val > 10.0) {
                          return context.tr('risk_config_risk_error');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildInputField(
                      context: context,
                      controller: _maxLossController,
                      labelKey: 'risk_config_max_loss',
                      hintKey: 'risk_config_max_loss_hint',
                      suffix: '%',
                      validator: (v) {
                        final val = double.tryParse(v ?? '');
                        if (val == null || val < 1.0 || val > 50.0) {
                          return context.tr('risk_config_max_loss_error');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),
                    _buildSubmitButton(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final state = context.read<TradingRoomBloc>().state;
    final isConfigured = state is TradingRoomLoaded && state.isRiskConfigured;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.25),
                AppColors.primary.withValues(alpha: 0.06),
              ],
            ),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35), width: 1),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('risk_config_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('risk_config_subtitle'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (isConfigured)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _buildInputField({
    required BuildContext context,
    required TextEditingController controller,
    required String labelKey,
    required String hintKey,
    String? prefix,
    String? suffix,
    required String? Function(String?) validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr(labelKey),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
          ],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: context.tr(hintKey),
            hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.15),
              fontSize: 14,
            ),
            prefixText: prefix,
            prefixStyle: TextStyle(
              color: AppColors.accent.withValues(alpha: 0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            suffixText: suffix,
            suffixStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: AppColors.background,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.alert.withValues(alpha: 0.6),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.alert,
                width: 1.5,
              ),
            ),
            errorStyle: TextStyle(
              color: AppColors.alert.withValues(alpha: 0.9),
              fontSize: 10,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveringButton = true),
      onExit: (_) => setState(() => _isHoveringButton = false),
      child: GestureDetector(
        onTap: _handleSubmit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _isHoveringButton
                ? AppColors.primary.withValues(alpha: 0.25)
                : AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary
                    .withValues(alpha: _isHoveringButton ? 0.4 : 0.2),
                blurRadius: _isHoveringButton ? 24 : 12,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.rocket_launch, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Text(
                context.tr('risk_config_btn'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
