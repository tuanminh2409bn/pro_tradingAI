import 'package:equatable/equatable.dart';
import '../../../data/models/profile_models.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

class LoadProfileData extends ProfileEvent {
  final String? userId;
  const LoadProfileData({this.userId});

  @override
  List<Object?> get props => [userId];
}

class UpdateProfile extends ProfileEvent {
  final UserProfile profile;
  const UpdateProfile(this.profile);

  @override
  List<Object?> get props => [profile];
}

class UpdateQuota extends ProfileEvent {
  final AccessQuota quota;
  const UpdateQuota(this.quota);

  @override
  List<Object?> get props => [quota];
}

class UpdateUsernameRequested extends ProfileEvent {
  final String newName;
  const UpdateUsernameRequested(this.newName);

  @override
  List<Object?> get props => [newName];
}

class Toggle2FARequested extends ProfileEvent {
  final bool enabled;
  const Toggle2FARequested(this.enabled);

  @override
  List<Object?> get props => [enabled];
}
