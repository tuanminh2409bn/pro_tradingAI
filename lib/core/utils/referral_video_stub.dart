import 'dart:typed_data';
import 'referral_video_types.dart';

bool isReferralVideoSupported() => false;

Future<ReferralVideo?> renderReferralVideo(
  Uint8List bannerPng, {
  bool Function()? isCancelled,
}) async => null;

Future<bool> downloadReferralVideo(
  ReferralVideo video,
  String filename,
) async => false;
