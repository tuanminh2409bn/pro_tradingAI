import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/localization/locale_cubit.dart';
import '../../../data/models/profile_models.dart';
import '../../../data/repositories/profile_repository.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import '../bloc/profile_state.dart';

class ProfileMobilePage extends StatelessWidget {
  const ProfileMobilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId =
        authState.user?.uid ?? FirebaseAuth.instance.currentUser?.uid;

    return BlocProvider(
      create: (context) =>
          ProfileBloc(profileRepository: context.read<ProfileRepository>())
            ..add(LoadProfileData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: const Color(0xFF111417),
          elevation: 0,
          title: const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          actions: [
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                final isAuth = authState.status == AuthStatus.authenticated;
                return Row(
                  children: [
                    Icon(
                      Icons.circle,
                      color: isAuth ? AppColors.primary : Colors.orange,
                      size: 8,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAuth ? 'ONLINE' : 'CONNECTING',
                      style: TextStyle(
                        color: isAuth ? AppColors.primary : Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                );
              },
            ),
          ],
        ),
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (state is ProfileError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    state.message,
                    style: const TextStyle(color: AppColors.bear),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (state is ProfileLoaded) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUserIdentityCard(context, userId, state.profile),
                    const SizedBox(height: 16),
                    _buildBrokerAccountsCard(context, state.brokerAccounts),
                    const SizedBox(height: 16),
                    _buildQuotaSection(context, state.quota),
                    const SizedBox(height: 16),
                    _buildSecurityCard(context, state),
                    const SizedBox(height: 16),
                    _PreferencesCard(state: state),
                    const SizedBox(height: 24),
                    _buildSignOutBtn(context),
                    const SizedBox(height: 80), // bottom nav safe space
                  ],
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildUserIdentityCard(
    BuildContext context,
    String? userId,
    UserProfile profile,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: profile.avatarUrl.isNotEmpty
                    ? NetworkImage(profile.avatarUrl)
                    : null,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: profile.avatarUrl.isEmpty
                    ? const Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 30,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white38,
                          ),
                          onPressed: () => _showEditUsernameDialog(
                            context,
                            profile.username,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.email,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            profile.tier,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ID: ${userId?.substring(0, 8).toUpperCase() ?? "--------"}',
                            style: const TextStyle(
                              color: Colors.white24,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat(
                context.tr('profile_trades'),
                '${profile.totalTrades}',
              ),
              _buildSimpleStat(
                context.tr('profile_win_rate'),
                '${profile.winRate}%',
              ),
              _buildSimpleStat(context.tr('profile_rank'), '#${profile.rank}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.white24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildBrokerAccountsCard(
    BuildContext context,
    List<BrokerAccount> accounts,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('profile_broker_accounts'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          // Day 5 API Relay — no MT4/MT5 credential form on mobile (App Store).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              context.tr('profile_link_on_web_only'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  context.tr('profile_no_accounts'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            ...accounts.map((acc) => _buildBrokerItem(acc)),
        ],
      ),
    );
  }

  Widget _buildBrokerItem(BrokerAccount acc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            acc.platform == 'mt5' ? Icons.looks_5 : Icons.looks_4,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${acc.platform.toUpperCase()} - ${acc.login}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  acc.server,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: acc.status == 'CONNECTED'
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              acc.status,
              style: TextStyle(
                color: acc.status == 'CONNECTED' ? Colors.green : Colors.orange,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaSection(BuildContext context, AccessQuota quota) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuotaRow(
            context.tr('profile_api_requests'),
            quota.apiUsed,
            quota.apiLimit,
            AppColors.primary,
          ),
          const SizedBox(height: 16),
          _buildQuotaRow(
            context.tr('profile_backtest_sessions'),
            quota.backtestUsed,
            quota.backtestLimit,
            AppColors.secondary,
          ),
          const SizedBox(height: 16),
          _buildQuotaRow(
            context.tr('profile_neural_storage'),
            quota.storageUsed.toInt(),
            quota.storageLimit.toInt(),
            AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaRow(String label, int used, int limit, Color color) {
    double progress = used / limit;
    progress = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white54,
                letterSpacing: 1,
              ),
            ),
            Text(
              '$used / $limit',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          color: color,
          backgroundColor: Colors.white.withValues(alpha: 0.03),
          minHeight: 4,
        ),
      ],
    );
  }

  Widget _buildSecurityCard(BuildContext context, ProfileLoaded state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('profile_security_settings'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.phonelink_lock,
              color: AppColors.primary,
              size: 20,
            ),
            title: Text(
              context.tr('profile_2fa_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              context.tr('profile_2fa_subtitle'),
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            trailing: Transform.scale(
              scale: 0.8,
              child: Switch(
                value: state.is2FAEnabled,
                onChanged: (v) =>
                    context.read<ProfileBloc>().add(Toggle2FARequested(v)),
                activeColor: AppColors.primary,
              ),
            ),
          ),
          const Divider(color: Colors.white10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key, color: Colors.white38, size: 20),
            title: Text(
              context.tr('profile_change_key'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.white24,
              size: 18,
            ),
            onTap: () => _showChangePasswordDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutBtn(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          context.read<AuthBloc>().add(AuthLogoutRequested());
        },
        icon: const Icon(Icons.logout, size: 14),
        label: const Text(
          'Sign Out',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.bear,
          side: BorderSide(color: AppColors.bear.withValues(alpha: 0.2)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showEditUsernameDialog(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          context.tr('profile_edit_username'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: context.tr('profile_new_username'),
            labelStyle: const TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                context.read<ProfileBloc>().add(
                  UpdateUsernameRequested(ctrl.text.trim()),
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('profile_username_updated')),
                    backgroundColor: AppColors.primary,
                  ),
                );
              }
            },
            child: Text(context.tr('profile_save')),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          context.tr('profile_change_key'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.tr('profile_current_password'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: newCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.tr('profile_new_password'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.tr('profile_confirm_password'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              if (newCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('profile_password_mismatch')),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (newCtrl.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('profile_password_short')),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null && user.email != null) {
                  final cred = EmailAuthProvider.credential(
                    email: user.email!,
                    password: currentCtrl.text,
                  );
                  await user.reauthenticateWithCredential(cred);
                  await user.updatePassword(newCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('profile_password_changed')),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(context.tr('profile_change_btn')),
          ),
        ],
      ),
    );
  }

  // Day 5: MT4/MT5 link form removed from mobile (API Relay / App Store).
}

class _PreferencesCard extends StatelessWidget {
  final ProfileLoaded state;
  const _PreferencesCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final pushEnabled = state.pushNotificationsEnabled;
    final dataEnabled = state.dataSharingEnabled;

    return BlocBuilder<LocaleCubit, String>(
      builder: (context, lang) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('profile_preferences'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white54,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              // Push Notifications
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.notifications_active,
                  color: AppColors.primary,
                  size: 20,
                ),
                title: Text(
                  context.tr('profile_push_notifications'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  context.tr('profile_push_notifications_subtitle'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: pushEnabled,
                    onChanged: (v) => context.read<ProfileBloc>().add(
                      UpdatePushNotificationsRequested(v),
                    ),
                    activeColor: AppColors.primary,
                  ),
                ),
              ),
              const Divider(color: Colors.white10),
              // Language
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.language,
                  color: Colors.white54,
                  size: 20,
                ),
                title: Text(
                  context.tr('profile_language'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: DropdownButton<String>(
                  value: lang,
                  dropdownColor: AppColors.surface,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  items: [
                    DropdownMenuItem(
                      value: 'vi',
                      child: Text(context.tr('profile_language_vi')),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text(context.tr('profile_language_en')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) context.read<LocaleCubit>().setLanguage(v);
                  },
                ),
              ),
              const Divider(color: Colors.white10),
              // Data Sharing
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.share,
                  color: Colors.white54,
                  size: 20,
                ),
                title: Text(
                  context.tr('profile_data_sharing'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  context.tr('profile_data_sharing_subtitle'),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: dataEnabled,
                    onChanged: (v) => context.read<ProfileBloc>().add(
                      UpdateDataSharingRequested(v),
                    ),
                    activeColor: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
