import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_cubit.dart';
import '../../../data/models/referral_models.dart';
import '../../../data/repositories/referral_repository.dart';
import '../bloc/referral_bloc.dart';
import '../bloc/referral_event.dart';
import '../bloc/referral_state.dart';
import 'referral_kit_card.dart';

class ReferralWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  final bool registrationPending;
  final String? registrationMessageKey;
  final VoidCallback? onRegistrationRetry;
  const ReferralWebPage({
    super.key,
    this.userId,
    this.onMenuPressed,
    this.registrationPending = false,
    this.registrationMessageKey,
    this.onRegistrationRetry,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ReferralBloc(referralRepository: context.read<ReferralRepository>())
            ..add(LoadReferralData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<ReferralBloc, ReferralState>(
          builder: (context, state) {
            if (state is ReferralLoading || state is ReferralInitial) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (state is ReferralError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr(state.message),
                      style: const TextStyle(color: AppColors.bear),
                    ),
                    TextButton(
                      onPressed: () => context.read<ReferralBloc>().add(
                        LoadReferralData(userId: userId),
                      ),
                      child: Text(context.tr('community_retry')),
                    ),
                  ],
                ),
              );
            }

            if (state is ReferralLoaded) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return Column(
                    children: [
                      _WebTopNavbar(onMenuPressed: onMenuPressed),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(context, isMobile),
                              if (registrationPending ||
                                  registrationMessageKey != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.tr(
                                          registrationPending
                                              ? 'referral_registration_pending'
                                              : registrationMessageKey!,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      if (!registrationPending &&
                                          onRegistrationRetry != null)
                                        TextButton(
                                          onPressed: onRegistrationRetry,
                                          child: Text(
                                            context.tr(
                                              'referral_registration_retry',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 32),
                              if (isMobile) ...[
                                _buildStatsCard(context, state.stats),
                                const SizedBox(height: 24),
                                if (state.stats.identity != null) ...[
                                  ReferralKitCard(
                                    key: ValueKey(state.stats.referralCode),
                                    identity: state.stats.identity!,
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                _buildNetworkCard(context, state.network),
                                const SizedBox(height: 24),
                                _buildHistoryCard(context, state.history),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildStatsCard(context, state.stats),
                                          const SizedBox(height: 24),
                                          if (state.stats.identity != null) ...[
                                            ReferralKitCard(
                                              key: ValueKey(
                                                state.stats.referralCode,
                                              ),
                                              identity: state.stats.identity!,
                                            ),
                                            const SizedBox(height: 24),
                                          ],
                                          _buildHistoryCard(
                                            context,
                                            state.history,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 1,
                                      child: _buildNetworkCard(
                                        context,
                                        state.network,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('referral_page_title'),
          style: TextStyle(
            fontSize: isMobile ? 24 : 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('referral_page_desc'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: isMobile ? 12 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(BuildContext context, ReferralStats stats) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('referral_performance'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 32),
          _buildStatItem(
            context.tr('referral_registered_invites'),
            stats.registeredInviteCount?.toString() ?? '—',
            Colors.white,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 28,
            runSpacing: 20,
            children: [
              _buildStatItem(
                context.tr('referral_total_earnings'),
                stats.isAvailable
                    ? '${stats.currency} ${stats.totalEarnings.toStringAsFixed(2)}'
                    : '—',
                AppColors.primary,
              ),
              _buildStatItem(
                context.tr('referral_f1_members'),
                stats.isAvailable ? '${stats.f1Count}' : '—',
                Colors.white,
              ),
              _buildStatItem(
                context.tr('referral_f2_members'),
                stats.isAvailable ? '${stats.f2Count}' : '—',
                Colors.white,
              ),
            ],
          ),
          if (!stats.isAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                context.tr('referral_ledger_unavailable'),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          const SizedBox(height: 40),
          Text(
            context.tr('referral_link_label'),
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stats.hasReferralLink ? stats.referralLink : '—',
                    style: TextStyle(
                      color: stats.hasReferralLink
                          ? Colors.white70
                          : Colors.white24,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: context.tr('referral_copy_link'),
                  onPressed: stats.hasReferralLink
                      ? () async {
                          await Clipboard.setData(
                            ClipboardData(text: stats.referralLink),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppLocalizations.get(
                                  context.read<LocaleCubit>().state,
                                  'referral_link_copied',
                                ),
                              ),
                              backgroundColor: AppColors.primary,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.copy, size: 16),
                  color: AppColors.primary,
                  disabledColor: Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkCard(BuildContext context, List<MemberNode> network) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr('referral_network_title'),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white54,
                letterSpacing: 1,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (network.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: Text(
                  context.tr('referral_network_empty'),
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: network.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final member = network[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Colors.white12,
                    radius: 16,
                    child: Text(
                      member.level,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  title: Text(
                    member.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Contribution: \$${member.earningsContribution.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(
    BuildContext context,
    List<RewardTransaction> history,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              context.tr('referral_history_title'),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white54,
                letterSpacing: 1,
              ),
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: Text(
                  context.tr('referral_history_empty'),
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                final tx = history[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  title: Text(
                    tx.title,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  subtitle: Text(
                    tx.status,
                    style: TextStyle(
                      color: tx.status == 'COMPLETED'
                          ? AppColors.primary
                          : Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: Text(
                    '${tx.amount >= 0 ? '+' : '-'}\$${tx.amount.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: tx.amount >= 0
                          ? AppColors.primary
                          : AppColors.bear,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const _WebTopNavbar({this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
