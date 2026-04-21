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
import 'features/auth/bloc/auth_state.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize GoogleSignIn for version 7.2.0
  await GoogleSignIn.instance.initialize(
    clientId: kIsWeb ? '22073478183-vahcdn471c8psgepsv3mukbsmqj3jv3o.apps.googleusercontent.com' : null,
  );
  
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
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthBloc(authRepository: authRepository),
          ),
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
      home: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          if (state.status == AuthStatus.authenticated) {
            return kIsWeb ? const WebDashboardShell() : const MobileDashboardShell();
          } else if (state.status == AuthStatus.unauthenticated) {
            return kIsWeb ? const LoginWebPage() : const LoginMobilePage();
          }
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        },
      ),
    );
  }
}
