bool _validPostId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

String? sharedCommunityPostId(Uri uri) {
  final values = uri.queryParametersAll['communityPost'];
  if (values == null || values.length != 1 || !_validPostId(values.single)) {
    return null;
  }
  return values.single;
}

Uri communityPostLink(Uri base, String postId) {
  if (!_validPostId(postId)) throw ArgumentError('Invalid post ID');
  final origin =
      (base.scheme == 'https' || base.scheme == 'http') && base.host.isNotEmpty
      ? base
      : Uri.parse('https://protrading-ai-2026.web.app/');
  return Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/',
    queryParameters: {'communityPost': postId},
  );
}
