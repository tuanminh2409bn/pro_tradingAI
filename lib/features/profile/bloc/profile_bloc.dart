import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/models/profile_models.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _profileRepository;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _quotaSubscription;
  StreamSubscription? _brokerSubscription;
  String? _currentUserId;

  ProfileBloc({required ProfileRepository profileRepository})
      : _profileRepository = profileRepository,
        super(ProfileInitial()) {
    on<LoadProfileData>(_onLoadData);
    on<UpdateProfile>(_onUpdateProfile);
    on<UpdateQuota>(_onUpdateQuota);
    on<UpdateBrokerAccounts>(_onUpdateBrokerAccounts);
    on<LinkBrokerAccountRequested>(_onLinkBrokerAccount);
    on<UpdateUsernameRequested>(_onUpdateUsername);
    on<Toggle2FARequested>(_onToggle2FA);
  }

  Future<void> _onLoadData(LoadProfileData event, Emitter<ProfileState> emit) async {
    emit(ProfileLoading());
    try {
      _currentUserId = event.userId;
      final userId = _currentUserId;
      
      _profileSubscription?.cancel();
      _quotaSubscription?.cancel();
      _brokerSubscription?.cancel();

      if (userId != null && userId.isNotEmpty) {
        _profileSubscription = _profileRepository.getUserProfile(userId).listen(
          (profile) => add(UpdateProfile(profile)),
          onError: (e) => print('ProfileBloc: Profile error: $e'),
        );

        _quotaSubscription = _profileRepository.getAccessQuota(userId).listen(
          (quota) => add(UpdateQuota(quota)),
          onError: (e) => print('ProfileBloc: Quota error: $e'),
        );

        _brokerSubscription = _profileRepository.getBrokerAccounts(userId).listen(
          (accounts) => add(UpdateBrokerAccounts(accounts)),
          onError: (e) => print('ProfileBloc: Broker error: $e'),
        );
      }

      emit(const ProfileLoaded(
        profile: UserProfile(
          username: 'Loading...',
          email: '',
          tier: 'FREE',
          totalTrades: 0,
          winRate: 0.0,
          rank: 0,
          avatarUrl: '',
        ),
        quota: AccessQuota(apiUsed: 0, apiLimit: 100, backtestUsed: 0, backtestLimit: 100, storageUsed: 0.0, storageLimit: 100.0),
        brokerAccounts: [],
      ));
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  void _onUpdateProfile(UpdateProfile event, Emitter<ProfileState> emit) {
    if (state is ProfileLoaded) {
      emit((state as ProfileLoaded).copyWith(profile: event.profile));
    }
  }

  void _onUpdateQuota(UpdateQuota event, Emitter<ProfileState> emit) {
    if (state is ProfileLoaded) {
      emit((state as ProfileLoaded).copyWith(quota: event.quota));
    }
  }

  void _onUpdateBrokerAccounts(UpdateBrokerAccounts event, Emitter<ProfileState> emit) {
    if (state is ProfileLoaded) {
      emit((state as ProfileLoaded).copyWith(brokerAccounts: event.accounts));
    }
  }

  Future<void> _onLinkBrokerAccount(LinkBrokerAccountRequested event, Emitter<ProfileState> emit) async {
    if (_currentUserId == null) return;
    
    final success = await _profileRepository.linkBrokerAccount(
      userId: _currentUserId!,
      platform: event.platform,
      server: event.server,
      login: event.login,
      password: event.password,
    );

    if (!success) {
      // Potentially emit an error state or a side effect for UI
      print('ProfileBloc: Failed to link broker account');
    }
  }

  Future<void> _onUpdateUsername(UpdateUsernameRequested event, Emitter<ProfileState> emit) async {
    if (_currentUserId != null) {
      await _profileRepository.updateUsername(_currentUserId!, event.newName);
    }
  }

  Future<void> _onToggle2FA(Toggle2FARequested event, Emitter<ProfileState> emit) async {
    if (state is ProfileLoaded) {
      emit((state as ProfileLoaded).copyWith(is2FAEnabled: event.enabled));
    }
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    _quotaSubscription?.cancel();
    _brokerSubscription?.cancel();
    return super.close();
  }
}
