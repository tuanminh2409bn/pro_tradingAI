import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';
import 'package:protrading_ai/features/referral/bloc/referral_bloc.dart';
import 'package:protrading_ai/features/referral/bloc/referral_event.dart';
import 'package:protrading_ai/features/referral/bloc/referral_state.dart';

final _identity = ReferralIdentity.fromServerLink(
  code: 'abcdefghijklmnopqrstuvwx',
  link: 'https://protrading-ai-2026.web.app/?ref=abcdefghijklmnopqrstuvwx',
);

class _Repository extends Fake implements ReferralRepository {
  final pending = <Completer<ReferralIdentity>>[];
  final watched = <String>[];
  @override
  Future<ReferralIdentity> provisionIdentity() {
    final operation = Completer<ReferralIdentity>();
    pending.add(operation);
    return operation.future;
  }

  @override
  Stream<ReferralStats> getReferralStats(String uid) {
    watched.add(uid);
    return const Stream.empty();
  }

  @override
  Stream<List<MemberNode>> getNetwork(String uid) => const Stream.empty();
  @override
  Stream<List<RewardTransaction>> getRewardHistory(String uid) =>
      const Stream.empty();
}

void main() {
  test(
    'provision waits for the backend and code availability does not imply money',
    () async {
      final repository = _Repository();
      final bloc = ReferralBloc(referralRepository: repository);
      addTearDown(bloc.close);
      bloc.add(const LoadReferralData(userId: 'alice'));
      await bloc.stream.firstWhere((state) => state is ReferralLoading);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state, isA<ReferralLoading>());
      repository.pending.single.complete(_identity);
      final loaded =
          await bloc.stream.firstWhere((state) => state is ReferralLoaded)
              as ReferralLoaded;
      expect(loaded.stats.hasReferralLink, isTrue);
      expect(loaded.stats.isAvailable, isFalse);
      expect(repository.watched, ['alice']);
    },
  );

  test(
    'reload ignores old identity/stream/error and retry can recover',
    () async {
      final repository = _Repository();
      final bloc = ReferralBloc(referralRepository: repository);
      addTearDown(bloc.close);
      bloc.add(const LoadReferralData(userId: 'alice'));
      await bloc.stream.firstWhere((state) => state is ReferralLoading);
      await Future<void>.delayed(Duration.zero);
      bloc.add(const LoadReferralData(userId: 'bob'));
      await Future<void>.delayed(Duration.zero);
      repository.pending.first.complete(_identity);
      repository.pending.last.completeError(StateError('unavailable'));
      await bloc.stream.firstWhere((state) => state is ReferralError);
      expect(repository.watched, isEmpty);
      bloc.add(const LoadReferralData(userId: 'bob'));
      await bloc.stream.firstWhere((state) => state is ReferralLoading);
      await Future<void>.delayed(Duration.zero);
      repository.pending.last.complete(_identity);
      await bloc.stream.firstWhere((state) => state is ReferralLoaded);
      bloc.add(const ReferralStreamFailed(generation: 1));
      bloc.add(
        const UpdateReferralStats(ReferralStats.unavailable(), generation: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as ReferralLoaded).stats.hasReferralLink, isTrue);
      expect(repository.watched, ['bob']);
    },
  );
}
