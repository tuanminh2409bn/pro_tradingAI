/// Build-time backend addresses. Override both for a local Web/VPS tunnel.
class BackendEndpoints {
  static const String apiBaseUrl = String.fromEnvironment(
    'PROTRADING_API_BASE_URL',
    defaultValue: 'https://103-69-189-243.sslip.io',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'PROTRADING_WS_BASE_URL',
    defaultValue: 'wss://103-69-189-243.sslip.io',
  );
}
