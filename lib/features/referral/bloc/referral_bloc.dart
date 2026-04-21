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
    on<WithdrawRewards>(_onWithdraw);
  }

  Future<void> _onLoadData(LoadReferralData event, Emitter<ReferralState> emit) async {
    emit(ReferralLoading());
    try {
      final userId = event.userId;
      
      _statsSubscription?.cancel();
      _networkSubscription?.cancel();
      _historySubscription?.cancel();

      if (userId != null && userId.isNotEmpty) {
        _statsSubscription = _referralRepository.getReferralStats(userId).listen(
          (stats) => add(UpdateReferralStats(stats)),
          onError: (e) => print('ReferralBloc: Stats error: $e'),
        );

        _networkSubscription = _referralRepository.getNetwork(userId).listen(
          (network) => add(UpdateReferralNetwork(network)),
          onError: (e) => print('ReferralBloc: Network error: $e'),
        );

        _historySubscription = _referralRepository.getRewardHistory(userId).listen(
          (history) => add(UpdateRewardHistory(history)),
          onError: (e) => print('ReferralBloc: History error: $e'),
        );
      }

      // Emit initial Loaded state immediately to avoid infinite spinner
      emit(const ReferralLoaded(
        stats: ReferralStats(totalEarnings: 0.0, f1Count: 0, f2Count: 0, referralLink: 'https://protrading.ai/ref/demo'),
        network: [],
        history: [],
      ));
    } catch (e) {
      emit(ReferralError(e.toString()));
    }
  }

  void _onUpdateStats(UpdateReferralStats event, Emitter<ReferralState> emit) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(stats: event.stats));
    }
  }

  void _onUpdateNetwork(UpdateReferralNetwork event, Emitter<ReferralState> emit) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(network: event.network));
    }
  }

  void _onUpdateHistory(UpdateRewardHistory event, Emitter<ReferralState> emit) {
    if (state is ReferralLoaded) {
      emit((state as ReferralLoaded).copyWith(history: event.history));
    }
  }

  Future<void> _onWithdraw(WithdrawRewards event, Emitter<ReferralState> emit) async {
    // Withdrawal logic
  }

  @override
  Future<void> close() {
    _statsSubscription?.cancel();
    _networkSubscription?.cancel();
    _historySubscription?.cancel();
    return super.close();
  }
}
