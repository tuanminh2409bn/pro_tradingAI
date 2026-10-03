import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/main.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/core/services/fcm_service.dart';
import 'package:protrading_ai/data/repositories/auth_repository.dart';
import 'package:protrading_ai/data/repositories/profile_repository.dart';
import 'package:protrading_ai/features/auth/bloc/auth_bloc.dart';
import 'package:protrading_ai/features/auth/bloc/auth_event.dart';

class _AuthRepository extends Fake implements AuthRepository {
  final users = StreamController<User?>.broadcast();
  final login = Completer<void>();
  @override
  Stream<User?> get user => users.stream;
  @override
  Future<void> logInWithEmailAndPassword({
    required String email,
    required String password,
  }) => login.future;
}

class _ProfileRepository extends Fake implements ProfileRepository {}

class _Fcm extends Fake implements FCMService {
  @override
  Future<bool> disable() async => true;
}

void main() {
  testWidgets(
    'Web keeps login draft during pending auth and shows localized error',
    (tester) async {
      final repository = _AuthRepository();
      final bloc = AuthBloc(
        authRepository: repository,
        profileRepository: _ProfileRepository(),
      );
      addTearDown(() async {
        if (!repository.login.isCompleted) repository.login.complete();
        await bloc.close();
        await repository.users.close();
      });
      await tester.pumpWidget(
        RepositoryProvider<FCMService>.value(
          value: _Fcm(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: bloc),
              BlocProvider(create: (_) => LocaleCubit()),
            ],
            child: const ProTradingApp(),
          ),
        ),
      );
      repository.users.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final email = find.byType(TextField).first;
      await tester.enterText(email, 'qa@example.test');
      final controller = tester.widget<TextField>(email).controller;
      bloc.add(
        const AuthLoginRequested(
          email: 'qa@example.test',
          password: 'local-fixture',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller,
        same(controller),
      );
      expect(controller!.text, 'qa@example.test');
      repository.login.completeError(
        FirebaseAuthException(code: 'wrong-password'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Email or password is invalid.'), findsOneWidget);
      expect(controller.text, 'qa@example.test');
    },
    skip: !kIsWeb,
  );
}
