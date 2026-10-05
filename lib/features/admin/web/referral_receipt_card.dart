import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/localization/app_localizations.dart';
import '../bloc/admin_bloc.dart';
import '../bloc/admin_event.dart';

class ReferralReceiptCard extends StatefulWidget {
  final bool busy;
  final String? receiptId;
  const ReferralReceiptCard({super.key, required this.busy, this.receiptId});
  @override
  State<ReferralReceiptCard> createState() => _ReferralReceiptCardState();
}

class _ReferralReceiptCardState extends State<ReferralReceiptCard> {
  final _form = GlobalKey<FormState>();
  final _reference = TextEditingController();
  final _payer = TextEditingController();
  final _net = TextEditingController();
  final _settled = TextEditingController();
  final _reversal = TextEditingController();
  bool _verified = false;

  @override
  void dispose() {
    for (final controller in [_reference, _payer, _net, _settled, _reversal]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _minor(String value) {
    final match = RegExp(
      r'^([0-9]{1,10})(?:\.([0-9]{1,2}))?$',
    ).firstMatch(value.trim());
    return match == null
        ? null
        : int.parse(match[1]!) * 100 +
              int.parse((match[2] ?? '').padRight(2, '0'));
  }

  DateTime? _date(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    return parsed?.toIso8601String().substring(0, 10) == value ? parsed : null;
  }

  Widget _field(
    TextEditingController controller,
    String label,
    bool Function(String) valid,
  ) => SizedBox(
    width: 300,
    child: TextFormField(
      controller: controller,
      enabled: !widget.busy,
      decoration: InputDecoration(labelText: context.tr(label)),
      validator: (value) => valid(value?.trim() ?? '')
          ? null
          : context.tr('referral_receipt_invalid'),
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('referral_receipt_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(context.tr('referral_receipt_note')),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _field(
                  _reference,
                  'referral_receipt_reference',
                  (v) => RegExp(r'^[A-Za-z0-9_-]{16,96}$').hasMatch(v),
                ),
                _field(
                  _payer,
                  'referral_receipt_payer',
                  (v) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(v),
                ),
                _field(
                  _net,
                  'referral_receipt_net',
                  (v) => (_minor(v) ?? 0) > 0 && _minor(v)! <= 1000000000000,
                ),
                _field(
                  _settled,
                  'referral_receipt_date',
                  (v) => _date(v) != null,
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _verified,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _verified = value == true),
              title: Text(context.tr('referral_receipt_verified')),
            ),
            FilledButton(
              onPressed: widget.busy || !_verified
                  ? null
                  : () {
                      if (_form.currentState?.validate() != true) return;
                      context.read<AdminBloc>().add(
                        ImportReferralReceipt(
                          _reference.text.trim(),
                          _payer.text.trim(),
                          _minor(_net.text)!,
                          _date(_settled.text.trim())!,
                        ),
                      );
                    },
              child: Text(context.tr('referral_receipt_submit')),
            ),
            if (widget.receiptId != null)
              SelectableText(
                '${context.tr('referral_receipt_id')}: ${widget.receiptId}',
              ),
            const Divider(),
            SizedBox(
              width: 480,
              child: TextField(
                controller: _reversal,
                enabled: !widget.busy,
                decoration: InputDecoration(
                  labelText: context.tr('referral_receipt_reversal_id'),
                ),
              ),
            ),
            TextButton(
              onPressed: widget.busy
                  ? null
                  : () async {
                      final id = _reversal.text.trim();
                      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) return;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(
                            context.tr('referral_receipt_reversal_confirm'),
                          ),
                          content: SelectableText(id),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: Text(context.tr('referral_cancel')),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: Text(
                                context.tr('referral_receipt_reverse'),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (context.mounted && confirmed == true) {
                        context.read<AdminBloc>().add(
                          ReverseReferralReceipt(id),
                        );
                      }
                    },
              child: Text(context.tr('referral_receipt_reverse')),
            ),
          ],
        ),
      ),
    ),
  );
}
