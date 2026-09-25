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
    emit(ReferralLoading());
    try {
      final userId = event.userId;

      _statsSubscription?.cancel();
      _networkSubscription?.cancel();
      _historySubscription?.cancel();

      if (userId != null && userId.isNotEmpty) {
        _statsSubscription = _referralRepository
            .getReferralStats(userId)
            .listen(
              (stats) => add(UpdateReferralStats(stats)),
              onError: (_) => add(const ReferralStreamFailed()),
            );

        _networkSubscription = _referralRepository
            .getNetwork(userId)
            .listen(
              (network) => add(UpdateReferralNetwork(network)),
              onError: (_) => add(const ReferralStreamFailed()),
            );

        _historySubscription = _referralRepository
            .getRewardHistory(userId)
            .listen(
              (history) => add(UpdateRewardHistory(history)),
              onError: (_) => add(const ReferralStreamFailed()),
            );
      }

      // Emit initial Loaded state immediately to avoid infinite spinner
      emit(
        const ReferralLoaded(
          stats: ReferralStats.unavailable(),
          network: [],
          history: [],
        ),
      );
    } catch (_) {
      emit(const ReferralError('common_data_unavailable'));
    }
  }

  void _onUpdateStats(UpdateReferralStats event, Emitter<ReferralState> emit) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(stats: event.stats));
    }
  }

  void _onUpdateNetwork(
    UpdateReferralNetwork event,
    Emitter<ReferralState> emit,
  ) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(network: event.network));
    }
  }

  void _onUpdateHistory(
    UpdateRewardHistory event,
    Emitter<ReferralState> emit,
  ) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(history: event.history));
    }
  }

  void _onStreamFailed(
    ReferralStreamFailed event,
    Emitter<ReferralState> emit,
  ) {
    emit(const ReferralError('common_data_unavailable'));
  }

  @override
  Future<void> close() {
    _statsSubscription?.cancel();
    _networkSubscription?.cancel();
    _historySubscription?.cancel();
    return super.close();
  }
}
