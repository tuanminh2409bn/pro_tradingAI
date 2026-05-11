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

class UpdateBrokerAccounts extends ProfileEvent {
  final List<BrokerAccount> accounts;
  const UpdateBrokerAccounts(this.accounts);

  @override
  List<Object?> get props => [accounts];
}

class LinkBrokerAccountRequested extends ProfileEvent {
  final String platform;
  final String server;
  final String login;
  final String password;

  const LinkBrokerAccountRequested({
    required this.platform,
    required this.server,
    required this.login,
    required this.password,
  });

  @override
  List<Object?> get props => [platform, server, login, password];
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
