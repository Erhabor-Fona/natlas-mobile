/// Thrown when the N-ATLaS gateway returns an error or the request fails.
class NAtlasException implements Exception {
  final int? statusCode;
  final String message;
  final String? detail;

  const NAtlasException({
    this.statusCode,
    required this.message,
    this.detail,
  });

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
  String toString() =>
      'NAtlasException(status: $statusCode, message: $message'
      '${detail != null ? ", detail: $detail" : ""})';
}
