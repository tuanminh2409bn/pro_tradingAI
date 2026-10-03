import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'referral_event.dart';
import 'referral_state.dart';
import '../../../data/repositories/referral_repository.dart';
import '../../../data/models/referral_models.dart';

class ReferralBloc extends Bloc<ReferralEvent, ReferralState> {
  final ReferralRepository _referralRepository;
  StreamSubscription? _statsSubscription;
  StreamSubscription? _networkSubscription;
  StreamSubscription? _historySubscription;
  int _loadGeneration = 0;

  ReferralBloc({required ReferralRepository referralRepository})
    : _referralRepository = referralRepository,
      super(ReferralInitial()) {
    on<LoadReferralData>(_onLoadData);
    on<UpdateReferralStats>(_onUpdateStats);
    on<UpdateReferralNetwork>(_onUpdateNetwork);
    on<UpdateRewardHistory>(_onUpdateHistory);
    on<ReferralStreamFailed>(_onStreamFailed);
  }

  Future<void> _onLoadData(
    LoadReferralData event,
    Emitter<ReferralState> emit,
  ) async {
    final generation = ++_loadGeneration;
    emit(ReferralLoading());
    try {
      final userId = event.userId;
      await Future.wait([
        if (_statsSubscription != null) _statsSubscription!.cancel(),
        if (_networkSubscription != null) _networkSubscription!.cancel(),
        if (_historySubscription != null) _historySubscription!.cancel(),
      ]);
      if (emit.isDone || generation != _loadGeneration) return;

      final identity = userId != null && userId.isNotEmpty
          ? await _referralRepository.provisionIdentity()
          : null;
      if (emit.isDone || generation != _loadGeneration) return;
      emit(
        ReferralLoaded(
          stats: identity == null
              ? const ReferralStats.unavailable()
              : ReferralStats(
                  totalEarnings: 0,
                  f1Count: 0,
                  f2Count: 0,
                  referralLink: identity.qrPayload,
                  referralCode: identity.code,
                  currency: '',
                  isAvailable: false,
                ),
          network: const [],
          history: const [],
        ),
      );

      if (userId != null && userId.isNotEmpty) {
        _statsSubscription = _referralRepository
            .getReferralStats(userId)
            .listen(
              (stats) {
                if (!isClosed) {
                  add(UpdateReferralStats(stats, generation: generation));
                }
              },
              onError: (_) {
                if (!isClosed) {
                  add(ReferralStreamFailed(generation: generation));
                }
              },
            );

        _networkSubscription = _referralRepository
            .getNetwork(userId)
            .listen(
              (network) {
                if (!isClosed) {
                  add(UpdateReferralNetwork(network, generation: generation));
                }
              },
              onError: (_) {
                if (!isClosed) {
                  add(ReferralStreamFailed(generation: generation));
                }
              },
            );

        _historySubscription = _referralRepository
            .getRewardHistory(userId)
            .listen(
              (history) {
                if (!isClosed) {
                  add(UpdateRewardHistory(history, generation: generation));
                }
              },
              onError: (_) {
                if (!isClosed) {
                  add(ReferralStreamFailed(generation: generation));
                }
              },
            );
      }
    } catch (_) {
      if (!emit.isDone && generation == _loadGeneration) {
        emit(const ReferralError('common_data_unavailable'));
      }
    }
  }

  void _onUpdateStats(UpdateReferralStats event, Emitter<ReferralState> emit) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(stats: event.stats));
    }
  }

  void _onUpdateNetwork(
    UpdateReferralNetwork event,
    Emitter<ReferralState> emit,
  ) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(network: event.network));
    }
  }

  void _onUpdateHistory(
    UpdateRewardHistory event,
    Emitter<ReferralState> emit,
  ) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(history: event.history));
    }
  }

  void _onStreamFailed(
    ReferralStreamFailed event,
    Emitter<ReferralState> emit,
  ) {
    if (event.generation != null && event.generation != _loadGeneration) return;
    emit(const ReferralError('common_data_unavailable'));
  }

  @override
  Future<void> close() {
    ++_loadGeneration;
    _statsSubscription?.cancel();
    _networkSubscription?.cancel();
    _historySubscription?.cancel();
    return super.close();
  }
}
