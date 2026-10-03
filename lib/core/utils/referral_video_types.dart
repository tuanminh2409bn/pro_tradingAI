import 'dart:typed_data';

class ReferralVideo {
  final Uint8List bytes;
  final String mimeType;
  final String extension;

  factory ReferralVideo(Uint8List bytes, String mimeType) {
    final container = mimeType.split(';').first;
    final isMp4 =
        container == 'video/mp4' &&
        bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';
    final isWebm =
        container == 'video/webm' &&
        bytes.length >= 12 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3;
    if (bytes.length > 20 * 1024 * 1024 || (!isMp4 && !isWebm)) {
      throw ArgumentError('Invalid referral video container');
    }
    return ReferralVideo._(bytes, mimeType, isMp4 ? 'mp4' : 'webm');
  }

  const ReferralVideo._(this.bytes, this.mimeType, this.extension);
}
