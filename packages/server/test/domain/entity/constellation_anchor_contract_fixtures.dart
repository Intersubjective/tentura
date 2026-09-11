/// Serializable C1/C2 contract fixtures for constellation anchor domain tests.
library;

const constellationAnchorCoordinateFixtureCases = <Map<String, Object?>>[
  {
    'id': 'origin_v1',
    'xUnits': 0,
    'yUnits': 0,
    'coordinateSpaceVersion': 1,
    'expect': 'valid',
  },
  {
    'id': 'max_corner',
    'xUnits': 10,
    'yUnits': 10,
    'coordinateSpaceVersion': 1,
    'expect': 'valid',
  },
  {
    'id': 'min_corner',
    'xUnits': -10,
    'yUnits': -10,
    'coordinateSpaceVersion': 1,
    'expect': 'valid',
  },
  {
    'id': 'above_max',
    'xUnits': 10.0000001,
    'yUnits': 0,
    'coordinateSpaceVersion': 1,
    'expect': 'outOfRange',
  },
  {
    'id': 'below_min',
    'xUnits': 0,
    'yUnits': -10.0000001,
    'coordinateSpaceVersion': 1,
    'expect': 'outOfRange',
  },
  {
    'id': 'nan_x',
    'xUnits': double.nan,
    'yUnits': 0,
    'coordinateSpaceVersion': 1,
    'expect': 'nonFinite',
  },
  {
    'id': 'pos_infinity',
    'xUnits': 0,
    'yUnits': double.infinity,
    'coordinateSpaceVersion': 1,
    'expect': 'nonFinite',
  },
  {
    'id': 'neg_infinity',
    'xUnits': double.negativeInfinity,
    'yUnits': 0,
    'coordinateSpaceVersion': 1,
    'expect': 'nonFinite',
  },
  {
    'id': 'unsupported_version',
    'xUnits': 0,
    'yUnits': 0,
    'coordinateSpaceVersion': 2,
    'expect': 'unsupportedCoordinateSpace',
  },
];

const constellationAnchorRevisionFixtureCases = <Map<String, Object>>[
  {'wire': '0', 'expectValid': true, 'exceedsJsSafeInteger': false},
  {'wire': '9007199254740992', 'expectValid': true, 'exceedsJsSafeInteger': false},
  {'wire': '9007199254740993', 'expectValid': true, 'exceedsJsSafeInteger': true},
  {'wire': '', 'expectValid': false, 'exceedsJsSafeInteger': false},
  {'wire': '-1', 'expectValid': false, 'exceedsJsSafeInteger': false},
  {'wire': '12abc', 'expectValid': false, 'exceedsJsSafeInteger': false},
];

const constellationAnchorTargetFixtureCases = <Map<String, Object>>[
  {
    'kindWire': 'PERSON',
    'targetId': 'U_viewer',
    'viewerId': 'U_viewer',
    'expect': 'invalidEgoPerson',
  },
  {
    'kindWire': 'PERSON',
    'targetId': 'U_peer',
    'viewerId': 'U_viewer',
    'expect': 'valid',
  },
  {
    'kindWire': 'BEACON',
    'targetId': 'U_viewer',
    'viewerId': 'U_viewer',
    'expect': 'valid',
  },
  {
    'kindWire': 'PERSON',
    'targetId': '',
    'viewerId': 'U_viewer',
    'expect': 'emptyId',
  },
  {
    'kindWire': 'UNKNOWN',
    'targetId': 'B_shared',
    'viewerId': 'U_viewer',
    'expect': 'unknownWireKind',
  },
];

const constellationAnchorDistinctTypedKeyFixture = <String, String>{
  'sharedRawId': 'X_overlap',
  'personMapKey': 'PERSON:X_overlap',
  'beaconMapKey': 'BEACON:X_overlap',
};

const constellationBeaconStatusFixtureCases = <Map<String, Object>>[
  {'status': 0, 'showClosed': false, 'permitted': true},
  {'status': 7, 'showClosed': false, 'permitted': true},
  {'status': 5, 'showClosed': false, 'permitted': false},
  {'status': 5, 'showClosed': true, 'permitted': true},
  {'status': 3, 'showClosed': true, 'permitted': false},
  {'status': 1, 'showClosed': true, 'permitted': false},
  {'status': 99, 'showClosed': true, 'permitted': false},
];
