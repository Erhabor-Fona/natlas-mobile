/// Thrown when the N-ATLaS gateway returns an error or the request fails.
class NAtlasException implements Exception {
  /// HTTP status from the gateway, or null if the request never completed.
  final int? statusCode;

  /// Short human-readable summary of what went wrong.
  final String message;

  /// The raw response body, when there was one.
  final String? detail;

  /// Creates an exception with an explicit [message].
  const NAtlasException({
    this.statusCode,
    required this.message,
    this.detail,
  });

  /// Builds an exception from a non-2xx response, deriving [message] from
  /// [statusCode] and keeping [body] as [detail].
  factory NAtlasException.fromStatus(int statusCode, String body) {
    return NAtlasException(
      statusCode: statusCode,
      message: _statusMessage(statusCode),
      detail: body,
    );
  }

  static String _statusMessage(int code) => switch (code) {
        400 => 'Bad request',
        401 => 'Unauthorized — check your API key',
        422 => 'Unprocessable content',
        429 => 'Rate limited',
        500 => 'Gateway internal error',
        _ => 'HTTP $code',
      };

  @override
  String toString() => 'NAtlasException(status: $statusCode, message: $message'
      '${detail != null ? ", detail: $detail" : ""})';
}
