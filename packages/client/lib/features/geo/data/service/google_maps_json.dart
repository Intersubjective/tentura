import 'dart:convert';

Map<String, Object?> decodeGoogleMapsJsonObject(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  throw StateError('Google Maps API returned unexpected JSON');
}

List<Object?> readGoogleMapsJsonList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String? googleMapsApiErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return null;
    }
    final error = decoded['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
      final status = error['status'];
      if (status is String && status.isNotEmpty) {
        return status;
      }
    }
    final status = decoded['status'];
    if (status is String &&
        status.isNotEmpty &&
        status != 'OK' &&
        status != 'ZERO_RESULTS') {
      final message = decoded['error_message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
      return status;
    }
  } on Object {
    return null;
  }
  return null;
}

String googleMapsHttpFailureLabel({
  required String serviceName,
  required int statusCode,
  required String body,
}) {
  final detail = googleMapsApiErrorMessage(body);
  if (detail != null && detail.isNotEmpty) {
    return '$serviceName request failed ($statusCode): $detail';
  }
  return '$serviceName request failed: HTTP $statusCode';
}
