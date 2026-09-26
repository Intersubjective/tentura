import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/beacon_request_preview_identity.dart';

/// Desk/triage list rows (My Work) compose [BeaconRequestPreviewIdentity].
/// Shared by widget tests and
/// `integration_test/request_lifecycle_beacon_cover_test.dart` (`_expectListIdentitySymbol`).
String? beaconCoverListIdentityBesideTitle(
  WidgetTester tester,
  String title,
) {
  final titleFinder = find.text(title);
  if (!_finderHasMatch(titleFinder)) {
    return null;
  }

  final preview = find.ancestor(
    of: titleFinder.first,
    matching: find.byType(BeaconRequestPreviewIdentity),
  );
  if (!_finderHasMatch(preview)) {
    return null;
  }

  final headerRow = find.descendant(
    of: preview,
    matching: find.ancestor(
      of: titleFinder.first,
      matching: find.byType(Row),
    ),
  );
  if (!_finderHasMatch(headerRow)) {
    return null;
  }

  final identityFrame = find.descendant(
    of: headerRow,
    matching: find.byType(TenturaIdentityTileFrame),
  );
  if (!_finderHasMatch(identityFrame)) {
    return null;
  }

  try {
    return beaconCoverIdentityBranch(tester, identityFrame.first);
    // ignore: avoid_catching_errors -- beaconCoverIdentityBranch signals "no branch painted" via StateError
  } on StateError {
    return null;
  }
}

/// Snapshot of `integration_test/request_lifecycle_beacon_cover_test.dart`
/// `_listIdentityBesideTitle` before tentura-ant (BeaconCardHeaderRow walker).
String? beaconCoverListIdentityBesideTitleCoverIntegrationLegacy(
  WidgetTester tester,
  String title,
) {
  final titleFinder = find.text(title);
  if (!_finderHasMatch(titleFinder)) {
    return null;
  }
  final headerRow = find.ancestor(
    of: titleFinder.first,
    matching: find.byType(BeaconCardHeaderRow),
  );
  if (!_finderHasMatch(headerRow)) {
    return null;
  }
  final tile = find.descendant(
    of: headerRow,
    matching: find.byType(BeaconIdentityTile),
  );
  if (!_finderHasMatch(tile)) {
    return null;
  }
  try {
    return beaconCoverIdentityBranch(tester, tile.first);
    // ignore: avoid_catching_errors -- beaconCoverIdentityBranch signals "no branch painted" via StateError
  } on StateError {
    return null;
  }
}

/// Classifies which identity branch is painted under [scope].
String beaconCoverIdentityBranch(WidgetTester tester, Finder scope) {
  if (scope.evaluate().isEmpty) {
    throw StateError('empty scope');
  }
  if (_finderHasMatch(
    find.descendant(of: scope, matching: find.byType(TenturaCapabilityGlyph)),
  )) {
    return 'symbol';
  }
  if (_finderHasMatch(
    find.descendant(of: scope, matching: find.byType(Image)),
  )) {
    return 'photo';
  }
  if (_finderHasMatch(
    find.descendant(of: scope, matching: find.byIcon(Icons.campaign_outlined)),
  )) {
    return 'neutral';
  }
  throw StateError('no identity branch painted in scope');
}

bool _finderHasMatch(Finder finder) => finder.evaluate().isNotEmpty;
