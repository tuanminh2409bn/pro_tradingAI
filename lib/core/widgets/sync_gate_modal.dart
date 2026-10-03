import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/colors.dart';
import '../localization/app_localizations.dart';
import '../security/partner_access.dart';
import '../../data/repositories/profile_repository.dart';
import '../../logic/navigation_cubit.dart';

/// Day 5 Sync Gate — first-run broker link / manual risk path.
class SyncGateHost extends StatefulWidget {
  final String? userId;
  final Widget child;

  const SyncGateHost({super.key, required this.userId, required this.child});

  @override
  State<SyncGateHost> createState() => _SyncGateHostState();
}

class _SyncGateHostState extends State<SyncGateHost> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void didUpdateWidget(covariant SyncGateHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _checked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
    }
  }

  Future<void> _maybeShow() async {
    final uid = widget.userId;
    if (_checked || uid == null || uid.isEmpty || !mounted) return;
    _checked = true;
    final repo = context.read<ProfileRepository>();
    final gate = await repo.getSyncGateState(uid);
    if (!mounted) return;
    if (gate.brokerLinked || gate.syncGateDismissed) return;
    if (kIsWeb && !await currentUserHasVerifiedPartnerClaim()) return;
    if (!mounted) return;
    await SyncGateModal.show(
      context,
      userId: uid,
      onConnectNow: () {
        context.read<NavigationCubit>().getNavBarItem(NavbarItem.profile);
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SyncGateModal extends StatelessWidget {
  final String userId;
  final VoidCallback onConnectNow;

  const SyncGateModal({
    super.key,
    required this.userId,
    required this.onConnectNow,
  });

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required VoidCallback onConnectNow,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          SyncGateModal(userId: userId, onConnectNow: onConnectNow),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProfileRepository>();
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONNECT YOUR BROKER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Link MT4/MT5 on Web to unlock live relay, Journal clarity, and synced risk. '
                'Or continue in manual mode with Input Constraint.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    onConnectNow();
                  },
                  child: const Text(
                    'CONNECT NOW',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await repo.dismissSyncGate(userId, manualMode: true);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text(
                    'SKIP & ENTER MANUALLY',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blur Journal (and similar) until broker is linked.
class BrokerLinkGate extends StatelessWidget {
  final String? userId;
  final Widget child;
  final VoidCallback? onConnect;

  const BrokerLinkGate({
    super.key,
    required this.userId,
    required this.child,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final uid = userId;
    final connect =
        onConnect ??
        () => context.read<NavigationCubit>().getNavBarItem(NavbarItem.profile);
    if (uid == null || uid.trim().isEmpty) {
      return BrokerLinkGateView(
        linked: false,
        onConnect: connect,
        child: child,
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      key: ValueKey(uid),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final linked =
            snap.connectionState == ConnectionState.active &&
            !snap.hasError &&
            data?['brokerLinked'] == true;
        return BrokerLinkGateView(
          linked: linked,
          onConnect: connect,
          child: child,
        );
      },
    );
  }
}

/// Presents the broker-link state; data authorization remains in Rules/API.
class BrokerLinkGateView extends StatelessWidget {
  final bool linked;
  final Widget child;
  final VoidCallback onConnect;

  const BrokerLinkGateView({
    super.key,
    required this.linked,
    required this.child,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ExcludeFocus(
          excluding: !linked,
          child: linked
              ? child
              : ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: ExcludeSemantics(child: AbsorbPointer(child: child)),
                ),
        ),
        if (!linked)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.tr('journal_locked_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('journal_locked_body'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: onConnect,
                        child: Text(
                          context.tr('sync_gate_connect'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
