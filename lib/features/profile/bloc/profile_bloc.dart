import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/models/profile_models.dart';
import '../../../core/services/fcm_service.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final ProfileRepository _profileRepository;
  final FCMService? _fcmService;
  StreamSubscription? _profileSubscription;
  StreamSubscription? _quotaSubscription;
  StreamSubscription? _brokerSubscription;
  String? _currentUserId;

  ProfileBloc({
    required ProfileRepository profileRepository,
    FCMService? fcmService,
  }) : _profileRepository = profileRepository,
       _fcmService = fcmService,
       super(ProfileInitial()) {
    on<LoadProfileData>(_onLoadData);
    on<UpdateProfile>(_onUpdateProfile);
    on<UpdateQuota>(_onUpdateQuota);
    on<UpdateBrokerAccounts>(_onUpdateBrokerAccounts);
    on<ProfileStreamFailed>(_onStreamFailed);
    on<LinkBrokerAccountRequested>(_onLinkBrokerAccount);
    on<UpdateUsernameRequested>(_onUpdateUsername);
    on<Toggle2FARequested>(_onToggle2FA);
    on<UpdatePushNotificationsRequested>(_onUpdatePushNotifications);
    on<UpdateDataSharingRequested>(_onUpdateDataSharing);
  }

  Future<void> _onLoadData(
    LoadProfileData event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());
    try {
      _currentUserId = event.userId;
      final userId = _currentUserId;

      _profileSubscription?.cancel();
      _quotaSubscription?.cancel();
      _brokerSubscription?.cancel();

      // Tải preferences từ Firestore trước
      bool pushNotifications = false;
      bool dataSharing = false;
      bool is2FA = false;
      if (userId != null && userId.isNotEmpty) {
        final prefs = await _profileRepository.getPreferences(userId);
        pushNotifications = prefs['pushNotifications'] ?? false;
        dataSharing = prefs['dataSharing'] ?? false;
        is2FA = prefs['2fa'] ?? false;
        if (pushNotifications && _fcmService != null) {
          pushNotifications = await _fcmService.enable(userId);
          if (!pushNotifications) {
            await _profileRepository.savePreferences(
              userId,
              pushNotifications: false,
            );
          }
        }

        _profileSubscription = _profileRepository
            .getUserProfile(userId)
            .listen(
              (profile) => add(UpdateProfile(profile)),
              onError: (_) => add(const ProfileStreamFailed()),
            );

        _quotaSubscription = _profileRepository
            .getAccessQuota(userId)
            .listen(
              (quota) => add(UpdateQuota(quota)),
              onError: (_) => add(const ProfileStreamFailed()),
            );

        _brokerSubscription = _profileRepository
            .getBrokerAccounts(userId)
            .listen(
              (accounts) => add(UpdateBrokerAccounts(accounts)),
              onError: (_) => add(const ProfileStreamFailed()),
            );
      }

      emit(
        ProfileLoaded(
          profile: const UserProfile(
            username: 'Loading...',
            email: '',
            tier: 'FREE',
            totalTrades: 0,
            winRate: 0.0,
            rank: 0,
            avatarUrl: '',
          ),
          quota: const AccessQuota.unavailable(),
          brokerAccounts: const [],
          is2FAEnabled: is2FA,
          pushNotificationsEnabled: pushNotifications,
          dataSharingEnabled: dataSharing,
        ),
      );
    } catch (_) {
      emit(const ProfileError('Profile data unavailable'));
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

  void _onUpdateBrokerAccounts(
    UpdateBrokerAccounts event,
    Emitter<ProfileState> emit,
  ) {
    if (state is ProfileLoaded) {
      emit((state as ProfileLoaded).copyWith(brokerAccounts: event.accounts));
    }
  }

  void _onStreamFailed(ProfileStreamFailed event, Emitter<ProfileState> emit) {
    emit(const ProfileError('Profile data unavailable'));
  }

  Future<void> _onLinkBrokerAccount(
    LinkBrokerAccountRequested event,
    Emitter<ProfileState> emit,
  ) async {
    final current = state;
    if (_currentUserId == null || current is! ProfileLoaded) return;
    final success = await _profileRepository.linkBrokerAccount(
      userId: _currentUserId!,
      platform: event.platform,
      server: event.server,
      login: event.login,
      password: event.password,
    );
    final latest = state is ProfileLoaded ? state as ProfileLoaded : current;
    emit(
      latest.copyWith(
        actionResultNonce: latest.actionResultNonce + 1,
        actionMessageKey: success ? 'profile_link_sent' : 'profile_link_failed',
        actionSucceeded: success,
      ),
    );
  }

  Future<void> _onUpdateUsername(
    UpdateUsernameRequested event,
    Emitter<ProfileState> emit,
  ) async {
    final loaded = state;
    if (_currentUserId == null || loaded is! ProfileLoaded) return;
    try {
      await _profileRepository.updateUsername(_currentUserId!, event.newName);
      final current = loaded.profile;
      final updated = UserProfile(
        username: event.newName,
        email: current.email,
        tier: current.tier,
        totalTrades: current.totalTrades,
        winRate: current.winRate,
        rank: current.rank,
        avatarUrl: current.avatarUrl,
      );
      final latest = state is ProfileLoaded ? state as ProfileLoaded : loaded;
      emit(
        latest.copyWith(
          profile: updated,
          actionResultNonce: latest.actionResultNonce + 1,
          actionMessageKey: 'profile_username_updated',
          actionSucceeded: true,
        ),
      );
    } catch (_) {
      final latest = state is ProfileLoaded ? state as ProfileLoaded : loaded;
      emit(
        latest.copyWith(
          actionResultNonce: latest.actionResultNonce + 1,
          actionMessageKey: 'profile_username_update_failed',
          actionSucceeded: false,
        ),
      );
    }
  }

  Future<void> _onToggle2FA(
    Toggle2FARequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is ProfileLoaded && _currentUserId != null) {
      emit((state as ProfileLoaded).copyWith(is2FAEnabled: event.enabled));
      try {
        await _profileRepository.toggle2FA(_currentUserId!, event.enabled);
      } catch (_) {
        emit((state as ProfileLoaded).copyWith(is2FAEnabled: !event.enabled));
      }
    }
  }

  Future<void> _onUpdatePushNotifications(
    UpdatePushNotificationsRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is ProfileLoaded && _currentUserId != null) {
      final current = state as ProfileLoaded;
      try {
        var effective = event.enabled;
        if (_fcmService != null) {
          effective = event.enabled
              ? await _fcmService.enable(_currentUserId)
              : !(await _fcmService.disable());
        }
        await _profileRepository.savePreferences(
          _currentUserId!,
          pushNotifications: effective,
        );
        emit(current.copyWith(pushNotificationsEnabled: effective));
      } catch (_) {
        emit(current);
      }
    }
  }

  Future<void> _onUpdateDataSharing(
    UpdateDataSharingRequested event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is ProfileLoaded && _currentUserId != null) {
      // Optimistic update
      emit(
        (state as ProfileLoaded).copyWith(dataSharingEnabled: event.enabled),
      );
      try {
        await _profileRepository.savePreferences(
          _currentUserId!,
          dataSharing: event.enabled,
        );
      } catch (_) {
        // Revert
        emit(
          (state as ProfileLoaded).copyWith(dataSharingEnabled: !event.enabled),
        );
      }
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
