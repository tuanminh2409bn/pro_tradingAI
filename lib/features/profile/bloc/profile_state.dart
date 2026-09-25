import 'package:equatable/equatable.dart';
import '../../../data/models/profile_models.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final UserProfile profile;
  final AccessQuota quota;
  final List<BrokerAccount> brokerAccounts;
  final bool is2FAEnabled;
  final bool pushNotificationsEnabled;
  final bool dataSharingEnabled;
  final int actionResultNonce;
  final String actionMessageKey;
  final bool actionSucceeded;

  const ProfileLoaded({
    required this.profile,
    required this.quota,
    this.brokerAccounts = const [],
    this.is2FAEnabled = false,
    this.pushNotificationsEnabled = false,
    this.dataSharingEnabled = false,
    this.actionResultNonce = 0,
    this.actionMessageKey = '',
    this.actionSucceeded = false,
  });

  ProfileLoaded copyWith({
    UserProfile? profile,
    AccessQuota? quota,
    List<BrokerAccount>? brokerAccounts,
    bool? is2FAEnabled,
    bool? pushNotificationsEnabled,
    bool? dataSharingEnabled,
    int? actionResultNonce,
    String? actionMessageKey,
    bool? actionSucceeded,
  }) {
    return ProfileLoaded(
      profile: profile ?? this.profile,
      quota: quota ?? this.quota,
      brokerAccounts: brokerAccounts ?? this.brokerAccounts,
      is2FAEnabled: is2FAEnabled ?? this.is2FAEnabled,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      dataSharingEnabled: dataSharingEnabled ?? this.dataSharingEnabled,
      actionResultNonce: actionResultNonce ?? this.actionResultNonce,
      actionMessageKey: actionMessageKey ?? this.actionMessageKey,
      actionSucceeded: actionSucceeded ?? this.actionSucceeded,
    );
  }

  @override
  List<Object?> get props => [
    profile,
    quota,
    brokerAccounts,
    is2FAEnabled,
    pushNotificationsEnabled,
    dataSharingEnabled,
    actionResultNonce,
    actionMessageKey,
    actionSucceeded,
  ];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
  @override
  List<Object?> get props => [message];
}
