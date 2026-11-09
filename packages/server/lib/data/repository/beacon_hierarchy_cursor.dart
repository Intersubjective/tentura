import 'dart:convert';

import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';

import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/exception.dart';

/// Opaque keyset cursor for [BeaconHierarchyChildGroup] pages.
final class BeaconHierarchyCursor {
  const BeaconHierarchyCursor({
    required this.publishedAt,
    required this.beaconId,
  });

  final DateTime publishedAt;
  final String beaconId;
}

String encodeBeaconHierarchyCursor({
  required String parentId,
  required BeaconHierarchyChildGroup group,
  required DateTime publishedAt,
  required String beaconId,
}) {
  final payload = jsonEncode({
    'v': kBeaconHierarchyCursorVersion,
    'p': parentId,
    'g': group.name,
    't': publishedAt.toUtc().toIso8601String(),
    'i': beaconId,
  });
  return base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
}

BeaconHierarchyCursor? decodeBeaconHierarchyCursor(
  String? after, {
  required String expectedParentId,
  required BeaconHierarchyChildGroup expectedGroup,
}) {
  if (after == null || after.isEmpty) {
    return null;
  }
  try {
    final normalized = after.padRight(
      after.length + ((4 - after.length % 4) % 4),
      '=',
    );
    final decoded = utf8.decode(base64Url.decode(normalized));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    if (map['v'] != kBeaconHierarchyCursorVersion) {
      throw const FormatException('cursor version');
    }
    if (map['p'] != expectedParentId) {
      throw const FormatException('cursor parent');
    }
    if (map['g'] != expectedGroup.name) {
      throw const FormatException('cursor group');
    }
    return BeaconHierarchyCursor(
      publishedAt: DateTime.parse(map['t'] as String),
      beaconId: map['i'] as String,
    );
  } on Object {
    throw const BeaconHierarchyCursorInvalidException();
  }
}
