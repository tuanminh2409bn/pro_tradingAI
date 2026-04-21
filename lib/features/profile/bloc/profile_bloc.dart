import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/models/profile_models.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _profileRepository;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _quotaSubscription;

  ProfileBloc({required ProfileRepository profileRepository})
      : _profileRepository = profileRepository,
        super(ProfileInitial()) {
    on<LoadProfileData>(_onLoadData);
    on<UpdateProfile>(_onUpdateProfile);
    on<UpdateQuota>(_onUpdateQuota);
    on<UpdateUsernameRequested>(_onUpdateUsername);
    on<Toggle2FARequested>(_onToggle2FA);
  }

  Future<void> _onLoadData(LoadProfileData event, Emitter<ProfileState> emit) async {
    emit(ProfileLoading());
    try {
      final userId = event.userId;
      
      _profileSubscription?.cancel();
      _quotaSubscription?.cancel();

      if (userId != null && userId.isNotEmpty) {
        _profileSubscription = _profileRepository.getUserProfile(userId).listen(
          (profile) => add(UpdateProfile(profile)),
          onError: (e) => print('ProfileBloc: Profile error: $e'),
        );

        _quotaSubscription = _profileRepository.getAccessQuota(userId).listen(
          (quota) => add(UpdateQuota(quota)),
          onError: (e) => print('ProfileBloc: Quota error: $e'),
        );
      }

      // Emit initial Loaded state immediately with mock data
      emit(const ProfileLoaded(
        profile: UserProfile(
          username: 'Demo User',
          email: 'demo@protrading.ai',
          tier: 'VIP',
          totalTrades: 0,
          winRate: 0.0,
          rank: 0,
          avatarUrl: '',
        ),
        quota: AccessQuota(apiUsed: 0, apiLimit: 100, backtestUsed: 0, backtestLimit: 100, storageUsed: 0.0, storageLimit: 100.0),
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

  Future<void> _onUpdateUsername(UpdateUsernameRequested event, Emitter<ProfileState> emit) async {
    // Note: In real app, we need the userId to update the correct record
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
    return super.close();
  }
}
