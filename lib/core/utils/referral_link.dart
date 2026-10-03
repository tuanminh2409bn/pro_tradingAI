String? referralCodeFromUri(Uri uri) {
  final values = uri.queryParametersAll['ref'];
  if (values == null ||
      values.length != 1 ||
      !RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(values.single)) {
    return null;
  }
  return values.single;
}
