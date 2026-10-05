import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/models/referral_wallet.dart';
import '../../../data/repositories/referral_repository.dart';

class ReferralWalletCard extends StatefulWidget {
  final String userId;
  const ReferralWalletCard({super.key, required this.userId});
  @override
  State<ReferralWalletCard> createState() => _ReferralWalletCardState();
}

class _ReferralWalletCardState extends State<ReferralWalletCard> {
  late Stream<ReferralWallet?> _wallet;
  late Stream<List<ReferralWithdrawal>> _withdrawals;
  final _amount = TextEditingController();
  String? _requestId;
  int? _requestAmount;
  String? _message;
  bool _pending = false;

  void _load() {
    try {
      _wallet = context.read<ReferralRepository>().getWallet(widget.userId);
      _withdrawals = context.read<ReferralRepository>().getWithdrawals(
        widget.userId,
      );
    } catch (_) {
      _wallet = Stream.error(StateError('Wallet unavailable'));
      _withdrawals = Stream.error(StateError('Withdrawals unavailable'));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReferralWalletCard old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) {
      _load();
      _requestId = null;
      _requestAmount = null;
      _message = null;
      _amount.clear();
      _pending = false;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit(ReferralWallet wallet) async {
    final match = RegExp(
      r'^([0-9]{1,10})(?:\.([0-9]{1,2}))?$',
    ).firstMatch(_amount.text.trim());
    final minor = match == null
        ? null
        : int.parse(match[1]!) * 100 +
              int.parse((match[2] ?? '').padRight(2, '0'));
    if (minor == null || minor < 2000 || minor > wallet.availableMinor) {
      setState(() => _message = 'referral_withdrawal_amount_invalid');
      return;
    }
    final uid = widget.userId;
    _requestId ??= 'withdrawal-${DateTime.now().microsecondsSinceEpoch}';
    if (_requestAmount != null && _requestAmount != minor) {
      setState(() => _message = 'referral_withdrawal_retry_amount');
      return;
    }
    _requestAmount = minor;
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await context.read<ReferralRepository>().requestWithdrawal(
        requestId: _requestId!,
        amountMinor: minor,
      );
      if (!mounted || widget.userId != uid) return;
      setState(() {
        _requestId = null;
        _requestAmount = null;
        _amount.clear();
        _message = 'referral_withdrawal_received';
      });
    } catch (error) {
      if (mounted && widget.userId == uid) {
        setState(() {
          if (error is ReferralWithdrawalException &&
              {400, 403, 409, 422}.contains(error.statusCode)) {
            _requestId = null;
            _requestAmount = null;
          }
          _message = 'referral_withdrawal_failed';
        });
      }
    } finally {
      if (mounted && widget.userId == uid) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ReferralWallet?>(
    stream: _wallet,
    builder: (context, snapshot) {
      final wallet = snapshot.hasError ? null : snapshot.data;
      if (snapshot.hasError) {
        return Column(
          children: [
            Text(context.tr('referral_ledger_unavailable')),
            TextButton(
              onPressed: () => setState(_load),
              child: Text(context.tr('community_retry')),
            ),
          ],
        );
      }
      if (wallet == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('referral_wallet_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${context.tr('referral_available_balance')}: ${ReferralWallet.money(wallet.availableMinor)}',
            ),
            Text(
              '${context.tr('referral_held_balance')}: ${ReferralWallet.money(wallet.heldMinor)}',
            ),
            Text(context.tr('referral_manual_payment_note')),
            if (wallet.pendingRequestId != null)
              Text(context.tr('referral_withdrawal_pending')),
            if (wallet.canRequestWithdrawal) ...[
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _amount,
                  enabled: !_pending && _requestAmount == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: context.tr('referral_withdrawal_amount'),
                  ),
                ),
              ),
              FilledButton(
                onPressed: _pending ? null : () => _submit(wallet),
                child: Text(
                  context.tr(
                    _pending
                        ? 'referral_registration_pending'
                        : 'referral_withdrawal_submit',
                  ),
                ),
              ),
            ],
            if (_message != null) Text(context.tr(_message!)),
            StreamBuilder<List<ReferralWithdrawal>>(
              stream: _withdrawals,
              builder: (context, history) {
                if (history.hasError) {
                  return Text(context.tr('referral_ledger_unavailable'));
                }
                final entries = history.data ?? const [];
                if (entries.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(context.tr('referral_withdrawal_history')),
                    for (final request in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${ReferralWallet.money(request.amountMinor)} · ${context.tr('referral_withdrawal_status_${request.status.toLowerCase()}')}',
                        ),
                        subtitle: Text(
                          request.createdAt.toLocal().toString().substring(
                            0,
                            16,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
