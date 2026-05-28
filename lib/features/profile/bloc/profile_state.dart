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

  const ProfileLoaded({
    required this.profile,
    required this.quota,
    this.brokerAccounts = const [],
    this.is2FAEnabled = true,
    this.pushNotificationsEnabled = true,
    this.dataSharingEnabled = true,
  });

  ProfileLoaded copyWith({
    UserProfile? profile,
    AccessQuota? quota,
    List<BrokerAccount>? brokerAccounts,
    bool? is2FAEnabled,
    bool? pushNotificationsEnabled,
    bool? dataSharingEnabled,
  }) {
    return ProfileLoaded(
      profile: profile ?? this.profile,
      quota: quota ?? this.quota,
      brokerAccounts: brokerAccounts ?? this.brokerAccounts,
      is2FAEnabled: is2FAEnabled ?? this.is2FAEnabled,
      pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      dataSharingEnabled: dataSharingEnabled ?? this.dataSharingEnabled,
    );
  }

  @override
  List<Object?> get props => [
    profile, quota, brokerAccounts,
    is2FAEnabled, pushNotificationsEnabled, dataSharingEnabled,
  ];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);
  @override
  List<Object?> get props => [message];
}
