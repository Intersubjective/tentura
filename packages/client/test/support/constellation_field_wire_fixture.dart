/// A FULL Field response with the viewer's direct contacts and private people.
Map<String, dynamic> constellationFieldWire({
  required DateTime now,
  required String viewerId,
  required List<Map<String, dynamic>> phantoms,
  Map<String, String> contacts = const {},
}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': now.toIso8601String(),
    'context': '',
    'peersCapped': false,
    'requestsCapped': false,
    'directContactIds': contacts.keys.toList(),
    'peers': [
      for (final contact in contacts.entries)
        {
          '__typename': 'v2_ConstellationPeer',
          'id': contact.key,
          'displayName': contact.value,
          'contactOnly': false,
          'presence': 'visible',
          'temporaryBeaconId': null,
          'bondContexts': <Object?>[],
          'handle': null,
          'image': null,
          'pinState': null,
          'isNew': false,
        },
    ],
    'edges': [
      for (final id in contacts.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': viewerId,
          'dst': id,
          'tier': 1,
        },
    ],
    'requests': <Object?>[],
    'posts': <Object?>[],
    'memberWebs': <Object?>[],
    'pendingForwards': <Object?>[],
    'linkHints': <Object?>[],
    'phantoms': phantoms,
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '1',
      'anchors': <Object?>[],
      'pinnedPeers': <Object?>[],
      'pinnedRequests': <Object?>[],
      'supportPeers': <Object?>[],
      'supportEdges': <Object?>[],
      'serverFilteredBeaconIds': <String>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

Map<String, dynamic> constellationPhantomWire(
  String id,
  String name, {
  required DateTime now,
  List<String> tags = const [],
  int? inviteDaysAgo,
}) => {
  '__typename': 'v2_ConstellationPhantom',
  'id': id,
  'displayName': name,
  'emoji': null,
  'hasPrivateAvatar': false,
  'ownTagIds': tags,
  'pinState': null,
  'inviteState': inviteDaysAgo == null ? 'none' : 'live',
  'inviteCreatedAt': inviteDaysAgo == null
      ? null
      : now.subtract(Duration(days: inviteDaysAgo, hours: 1)).toIso8601String(),
  'createdAt': now.subtract(const Duration(days: 9)).toIso8601String(),
};
