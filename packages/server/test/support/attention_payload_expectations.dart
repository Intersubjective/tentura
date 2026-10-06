import 'dart:convert';

import 'package:test/test.dart';

/// Requires valid presentation fields to survive. Each problematic scalar
/// must either be removed or retain its value as a string; no other fields or
/// non-string values may reach the public payload.
void expectSanitizedAttentionPayload(
  Object? payloadJson, {
  required Map<String, String> requiredFields,
  Map<String, String> coercibleFields = const {},
}) {
  expect(payloadJson, isA<String>());
  final payload = jsonDecode(payloadJson! as String) as Map<String, dynamic>;
  expect(
    payload.keys,
    everyElement(isIn({...requiredFields.keys, ...coercibleFields.keys})),
  );
  for (final entry in requiredFields.entries) {
    expect(payload, containsPair(entry.key, entry.value));
  }
  for (final entry in coercibleFields.entries) {
    if (payload.containsKey(entry.key)) {
      expect(payload[entry.key], entry.value);
    }
  }
  expect(payload.values, everyElement(isA<String>()));
}
