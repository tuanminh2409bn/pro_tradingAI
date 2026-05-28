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

class ProfileWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const ProfileWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileBloc(
        profileRepository: context.read<ProfileRepository>(),
      )..add(LoadProfileData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading || state is ProfileInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is ProfileError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is ProfileLoaded) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return Column(
                    children: [
                      _WebTopNavbar(onMenuPressed: onMenuPressed),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 24.0 : 40.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(context, isMobile),
                              const SizedBox(height: 32),
                              if (isMobile) ...[
                                _buildProfileInfoCard(context, state.profile),
                                const SizedBox(height: 24),
                                _buildBrokerAccountsCard(context, state.brokerAccounts),
                                const SizedBox(height: 24),
                                _buildQuotaGrid(context, state.quota, isMobile),
                                const SizedBox(height: 24),
                                _buildSecurityCard(context, state),
                                const SizedBox(height: 24),
                                const _PreferencesCard(),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildProfileInfoCard(context, state.profile),
                                          const SizedBox(height: 24),
                                          _buildBrokerAccountsCard(context, state.brokerAccounts),
                                          const SizedBox(height: 24),
                                          const _PreferencesCard(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      flex: 1,
                                      child: Column(
                                        children: [
                                          _buildQuotaGrid(context, state.quota, isMobile),
                                          const SizedBox(height: 24),
                                          _buildSecurityCard(context, state),
                                        ],
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
          context.tr('profile_title'),
          style: TextStyle(
            fontSize: isMobile ? 24 : 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('profile_subtitle'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: isMobile ? 12 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfoCard(BuildContext context, UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Real avatar with fallback
              CircleAvatar(
                radius: 40,
                backgroundImage: profile.avatarUrl.isNotEmpty ? NetworkImage(profile.avatarUrl) : null,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: profile.avatarUrl.isEmpty
                    ? const Icon(Icons.person, color: AppColors.primary, size: 40)
                    : null,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username with edit button
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.username,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 14, color: Colors.white38),
                          onPressed: () => _showEditUsernameDialog(context, profile.username),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Tier badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        profile.tier,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // User ID badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat(context.tr('profile_trades'), '${profile.totalTrades}'),
              _buildSimpleStat(context.tr('profile_win_rate'), '${profile.winRate}%'),
              _buildSimpleStat(context.tr('profile_rank'), '#${profile.rank}'),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditUsernameDialog(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(context.tr('profile_edit_username'), style: const TextStyle(color: Colors.white)),
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
                context.read<ProfileBloc>().add(UpdateUsernameRequested(ctrl.text.trim()));
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
        title: Text(context.tr('profile_change_key'), style: const TextStyle(color: Colors.white)),
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
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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

  Widget _buildBrokerAccountsCard(BuildContext context, List<BrokerAccount> accounts) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              TextButton.icon(
                onPressed: () => _showLinkAccountDialog(context),
                icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
                label: Text(
                  context.tr('profile_link_new'),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (accounts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  context.tr('profile_no_accounts'),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(acc.platform == 'mt5' ? Icons.looks_5 : Icons.looks_4, color: AppColors.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${acc.platform.toUpperCase()} - ${acc.login}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(acc.server, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLinkAccountDialog(BuildContext context) {
    final platformController = TextEditingController(text: 'mt4');
    final serverController = TextEditingController();
    final loginController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          context.tr('profile_link_broker_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: 'mt4',
              dropdownColor: AppColors.surface,
              decoration: InputDecoration(
                labelText: context.tr('profile_platform'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'mt4', child: Text('MT4')),
                DropdownMenuItem(value: 'mt5', child: Text('MT5')),
              ],
              onChanged: (v) => platformController.text = v ?? 'mt4',
            ),
            TextField(
              controller: serverController,
              decoration: InputDecoration(
                labelText: context.tr('profile_broker_server'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: loginController,
              decoration: InputDecoration(
                labelText: context.tr('profile_login_id'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: context.tr('profile_trading_password'),
                labelStyle: const TextStyle(color: Colors.white54),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            // Security warning banner
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('profile_security_notice'),
                      style: const TextStyle(color: Colors.green, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<ProfileBloc>().add(LinkBrokerAccountRequested(
                platform: platformController.text,
                server: serverController.text,
                login: loginController.text,
                password: passwordController.text,
              ));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('profile_link_sent'))),
              );
            },
            child: Text(context.tr('profile_link_account')),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _buildQuotaGrid(BuildContext context, AccessQuota quota, bool isMobile) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 1 : 1,
      mainAxisSpacing: 16,
      childAspectRatio: 4,
      children: [
        _buildQuotaCard(context.tr('profile_api_requests'), quota.apiUsed, quota.apiLimit, AppColors.primary),
        _buildQuotaCard(context.tr('profile_backtest_sessions'), quota.backtestUsed, quota.backtestLimit, AppColors.secondary),
        _buildQuotaCard(context.tr('profile_neural_storage'), quota.storageUsed.toInt(), quota.storageLimit.toInt(), AppColors.accent),
      ],
    );
  }

  Widget _buildQuotaCard(String label, int used, int limit, Color color) {
    double progress = used / limit;
    progress = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
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
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            color: color,
            backgroundColor: Colors.white.withValues(alpha: 0.03),
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(BuildContext context, ProfileLoaded state) {
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
            context.tr('profile_security_settings'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.phonelink_lock, color: AppColors.primary),
            title: Text(
              context.tr('profile_2fa_title'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              context.tr('profile_2fa_subtitle'),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: Switch(
              value: state.is2FAEnabled,
              onChanged: (v) => context.read<ProfileBloc>().add(Toggle2FARequested(v)),
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key, color: Colors.white38),
            title: Text(
              context.tr('profile_change_key'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => _showChangePasswordDialog(context),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preferences Card — BLoC-driven (reads from ProfileBloc & LocaleCubit)
// ---------------------------------------------------------------------------

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final loaded = profileState is ProfileLoaded ? profileState : null;
        final pushEnabled = loaded?.pushNotificationsEnabled ?? true;
        final dataEnabled = loaded?.dataSharingEnabled ?? true;

        return BlocBuilder<LocaleCubit, String>(
          builder: (context, lang) {
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
                    leading: const Icon(Icons.notifications_active, color: AppColors.primary),
                    title: Text(
                      context.tr('profile_push_notifications'),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      context.tr('profile_push_notifications_subtitle'),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    trailing: Switch(
                      value: pushEnabled,
                      onChanged: (v) => context.read<ProfileBloc>().add(UpdatePushNotificationsRequested(v)),
                      activeColor: AppColors.primary,
                    ),
                  ),
                  const Divider(color: Colors.white10),
                  // Language
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.language, color: Colors.white54),
                    title: Text(
                      context.tr('profile_language'),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    trailing: DropdownButton<String>(
                      value: lang,
                      dropdownColor: AppColors.surface,
                      underline: const SizedBox(),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: [
                        DropdownMenuItem(value: 'vi', child: Text(context.tr('profile_language_vi'))),
                        DropdownMenuItem(value: 'en', child: Text(context.tr('profile_language_en'))),
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
                    leading: const Icon(Icons.share, color: Colors.white54),
                    title: Text(
                      context.tr('profile_data_sharing'),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: Text(
                      context.tr('profile_data_sharing_subtitle'),
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    trailing: Switch(
                      value: dataEnabled,
                      onChanged: (v) => context.read<ProfileBloc>().add(UpdateDataSharingRequested(v)),
                      activeColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Top Navigation Bar
// ---------------------------------------------------------------------------

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
          const SizedBox(width: 40),
          Expanded(
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                final isAuth = authState.status == AuthStatus.authenticated;
                return Text(
                  isAuth ? context.tr('profile_system_online') : context.tr('profile_connecting'),
                  style: TextStyle(
                    color: isAuth ? AppColors.primary : Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                );
              },
            ),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
