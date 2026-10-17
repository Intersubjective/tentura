import 'package:tentura/consts.dart';

/// [message] when [value] has fewer than [kComplaintDetailsMinLength]
/// characters after trimming (empty included), else `null`.
///
/// Counts Unicode code points. The server counts UTF-16 units, which is never
/// fewer, so details the form accepts are never rejected by the server.
String? validateComplaintDetails(String? value, String message) {
  final details = value?.trim() ?? '';
  if (details.runes.length < kComplaintDetailsMinLength) return message;
  return null;
}
