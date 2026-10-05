import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'features/dashboard/web/web_dashboard_shell.dart';
import 'features/dashboard/mobile/mobile_dashboard_shell.dart';
import 'features/auth/web/login_web_page.dart';
import 'features/auth/mobile/login_mobile_page.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'core/localization/locale_cubit.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/trading_repository.dart';
import 'data/repositories/news_repository.dart';
import 'data/repositories/journal_repository.dart';
import 'data/repositories/backtest_repository.dart';
import 'data/repositories/community_repository.dart';
import 'data/repositories/radar_repository.dart';
import 'data/repositories/referral_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'data/repositories/admin_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'core/constants/colors.dart';
import 'core/constants/local_qa_mode.dart';
import 'core/utils/firebase_qa_bootstrap.dart';
import 'core/utils/referral_link.dart';
import 'core/localization/app_localizations.dart';
import 'core/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb && LocalQaMode.enabled) {
    await prepareFirebaseQa(DefaultFirebaseOptions.currentPlatform);
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize GoogleSignIn for version 7.2.0
  if (!(kIsWeb && LocalQaMode.enabled)) {
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb
          ? '22073478183-vahcdn471c8psgepsv3mukbsmqj3jv3o.apps.googleusercontent.com'
          : null,
    );
  }

  final authRepository = AuthRepository();
  final tradingRepository = TradingRepository();
  final newsRepository = NewsRepository();
  final journalRepository = JournalRepository();
  final backtestRepository = BacktestRepository();
  final communityRepository = CommunityRepository();
  final radarRepository = RadarRepository();
  final referralRepository = ReferralRepository();
  final profileRepository = ProfileRepository();
  final adminRepository = AdminRepository();
  final fcmService = FCMService();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: tradingRepository),
        RepositoryProvider.value(value: newsRepository),
        RepositoryProvider.value(value: journalRepository),
        RepositoryProvider.value(value: backtestRepository),
        RepositoryProvider.value(value: communityRepository),
        RepositoryProvider.value(value: radarRepository),
        RepositoryProvider.value(value: referralRepository),
        RepositoryProvider.value(value: profileRepository),
        RepositoryProvider.value(value: adminRepository),
        RepositoryProvider.value(value: fcmService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(
              authRepository: authRepository,
              profileRepository: profileRepository,
              referralRepository: referralRepository,
              signupReferralCode: kIsWeb ? referralCodeFromUri(Uri.base) : null,
              completeOnboarding: kIsWeb
                  ? authRepository.completeWebOnboarding
                  : null,
            ),
          ),
          BlocProvider(create: (context) => LocaleCubit()),
        ],
        child: const ProTradingApp(),
      ),
    ),
  );
}

class ProTradingApp extends StatelessWidget {
  const ProTradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleCubit, String>(
      builder: (context, lang) {
        return MaterialApp(
          title: 'ProTrading AI',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppColors.background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            fontFamily: 'Inter',
          ),
          home: BlocListener<AuthBloc, AuthState>(
            listenWhen: (previous, current) =>
                previous.status != current.status ||
                previous.user?.uid != current.user?.uid ||
                previous.errorMessage != current.errorMessage ||
                previous.registrationReferralMessageNonce !=
                    current.registrationReferralMessageNonce,
            listener: (context, state) {
              if (kIsWeb && state.registrationReferralMessageKey != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  final current = context.read<AuthBloc>().state;
                  if (current.user?.uid != state.user?.uid ||
                      current.registrationReferralMessageNonce !=
                          state.registrationReferralMessageNonce) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.get(
                          context.read<LocaleCubit>().state,
                          state.registrationReferralMessageKey!,
                        ),
                      ),
                    ),
                  );
                });
              }
              if (state.status == AuthStatus.authenticated) {
                if (!kIsWeb) {
                  context.read<FCMService>().enable(state.user?.uid);
                }
              } else if (state.status == AuthStatus.unauthenticated && kIsWeb) {
                context.read<FCMService>().disable();
              }
            },
            child: BlocBuilder<AuthBloc, AuthState>(
              buildWhen: (previous, current) =>
                  !kIsWeb ||
                  current.status != AuthStatus.loading ||
                  previous.status != AuthStatus.unauthenticated,
              builder: (context, state) {
                if (state.status == AuthStatus.authenticated) {
                  return kIsWeb
                      ? WebDashboardShell(key: ValueKey(state.user?.uid))
                      : const MobileDashboardShell();
                } else if (state.status == AuthStatus.unauthenticated) {
                  return kIsWeb
                      ? const LoginWebPage()
                      : const LoginMobilePage();
                } else if (state.status == AuthStatus.onboarding &&
                    state.errorMessage != null) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.tr('auth_onboarding_unavailable'),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => context.read<AuthBloc>().add(
                                const AuthOnboardingRetryRequested(),
                              ),
                              child: Text(context.tr('auth_onboarding_retry')),
                            ),
                            TextButton(
                              onPressed: () => context.read<AuthBloc>().add(
                                AuthLogoutRequested(),
                              ),
                              child: Text(context.tr('tr_logout_tooltip')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
