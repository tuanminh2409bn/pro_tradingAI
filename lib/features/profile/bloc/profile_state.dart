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
  final bool is2FAEnabled;

  const ProfileLoaded({
    required this.profile,
    required this.quota,
    this.is2FAEnabled = true,
  });

  ProfileLoaded copyWith({
    UserProfile? profile,
    AccessQuota? quota,
    bool? is2FAEnabled,
  }) {
    return ProfileLoaded(
      profile: profile ?? this.profile,
      quota: quota ?? this.quota,
      is2FAEnabled: is2FAEnabled ?? this.is2FAEnabled,
    );
  }

  @override
  List<Object?> get props => [profile, quota, is2FAEnabled];
}

class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
