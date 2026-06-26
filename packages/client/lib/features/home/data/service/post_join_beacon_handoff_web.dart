import 'dart:convert';

import 'package:web/web.dart' as web;

import '../../domain/entity/post_join_destination.dart';

const _storageKey = 'tentura_post_join_beacon';

PostJoinDestination? readPostJoinBeaconHandoff() {
  try {
    final raw = web.window.sessionStorage.getItem(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    web.window.sessionStorage.removeItem(_storageKey);
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final id = map['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return PostJoinDestination(
      beaconId: id,
      beaconTitle: map['title']?.toString() ?? '',
      inviterName: map['inviterName']?.toString() ?? '',
      showSnackbar: true,
    );
  } catch (_) {
    return null;
  }
}
