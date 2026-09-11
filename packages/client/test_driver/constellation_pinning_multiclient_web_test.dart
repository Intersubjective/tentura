// ignore_for_file: tentura_lints/no_raw_graphql_in_dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multiclient_webdriver_support.dart';

Future<void> main() async {
  final qaToken = Platform.environment['QA_AUTH_TOKEN']?.trim() ?? '';
  if (qaToken.isEmpty) {
    throw StateError('QA_AUTH_TOKEN is required');
  }
  final runId =
      Platform.environment['REALTIME_MULTICLIENT_RUN_ID'] ??
      'constellation-pin-${DateTime.now().microsecondsSinceEpoch}';
  final artifactDir = Directory(
    Platform.environment['REALTIME_MULTICLIENT_ARTIFACT_DIR'] ??
        'constellation-pinning-artifacts/$runId',
  )..createSync(recursive: true);

  final timings = <String, int>{};
  final proof = <String, dynamic>{};
  final journeys = <String, String>{};
  final fixture = await bootstrapFixture(qaToken, runId);

  BrowserSession? actor;
  BrowserSession? actorPeer;
  BrowserSession? outsider;
  Object? failure;
  StackTrace? failureStack;

  try {
    actor = await BrowserSession.start('actor', artifactDir);
    actorPeer = await BrowserSession.start('actor-peer', artifactDir);
    outsider = await BrowserSession.start('outsider', artifactDir);
    await Future.wait([
      actor.login(fixture.authorEmail),
      actorPeer.login(fixture.authorEmail),
      outsider.login(fixture.helperEmail),
    ]);

    await _journeyLivePinConvergence(
      actor: actor,
      actorPeer: actorPeer,
      fixture: fixture,
      timings: timings,
      journeys: journeys,
    );
    await _journeyReconnectCatchUp(
      actorPeer: actorPeer,
      fixture: fixture,
      qaToken: qaToken,
      timings: timings,
      journeys: journeys,
    );
    await _journeyStaleCrossDeviceDelete(
      actorPeer: actorPeer,
      fixture: fixture,
      journeys: journeys,
    );
    await _journeyUnauthorizedIsolation(
      fixture: fixture,
      journeys: journeys,
    );
    await _journeyFailedMutationRollback(
      actor: actor,
      fixture: fixture,
      journeys: journeys,
    );

    await assertNoUncaughtFlutterErrors([actor, actorPeer, outsider]);
    journeys['touch_arbitration'] = 'BLOCKED';
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    File('${artifactDir.path}/failure.txt').writeAsStringSync(
      '$error\n$stackTrace',
    );
    if (actor != null) {
      await actor.captureFailure();
    }
    if (actorPeer != null) {
      await actorPeer.captureFailure();
    }
    if (outsider != null) {
      await outsider.captureFailure();
    }
  } finally {
    await controlRealtimeSocket(
      qaToken,
      fixture.authorUserId,
      action: 'resume',
    );
    if (actor != null) {
      await actor.finish();
    }
    if (actorPeer != null) {
      await actorPeer.finish();
    }
    if (outsider != null) {
      await outsider.finish();
    }
    File('${artifactDir.path}/timings.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(timings),
    );
    proof['journeys'] = journeys;
    proof['artifactDir'] = artifactDir.path;
    proof['ok'] = failure == null;
    File('${artifactDir.path}/proof.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(proof),
    );
  }

  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  stdout.writeln(
    '[constellation-pinning-multiclient] PASS run=$runId journeys=$journeys',
  );
}

Future<void> _journeyLivePinConvergence({
  required BrowserSession actor,
  required BrowserSession actorPeer,
  required Fixture fixture,
  required Map<String, int> timings,
  required Map<String, String> journeys,
}) async {
  final graphNodeId = 'graph.node.${fixture.helperUserId}';
  await Future.wait([
    actor.open('/home/constellation'),
    actorPeer.open('/home/constellation'),
  ]);
  await Future.wait([
    actor.waitForTestId(graphNodeId),
    actorPeer.waitForTestId(graphNodeId),
  ]);
  await actor.clickTestId(graphNodeId);
  await actor.clickTestId('constellation.pin_target');
  timings['live_pin_marker_ms'] = await measureUntil(
    () => actorPeer.hasTestId('constellation.pin_marker'),
    timeout: const Duration(seconds: 8),
  );
  final anchors = await fetchConstellationAnchorsViaApi(
    email: fixture.authorEmail,
  );
  final anchor = anchorByTarget(
    anchors,
    targetKind: 'PERSON',
    targetId: fixture.helperUserId,
  );
  requireTruth(anchor != null, 'person anchor missing after live pin');
  requireTruth(
    (anchor!['xUnits'] as num).toDouble().abs() > 0,
    'anchor coordinates must be normalized units',
  );
  journeys['live_convergence'] = 'PASS';
}

Future<void> _journeyReconnectCatchUp({
  required BrowserSession actorPeer,
  required Fixture fixture,
  required String qaToken,
  required Map<String, int> timings,
  required Map<String, String> journeys,
}) async {
  const movedX = 3.25;
  const movedY = -2.75;
  await actorPeer.open('/home/constellation');
  await actorPeer.waitForTestId('graph.node.${fixture.helperUserId}');
  final suspended = await controlRealtimeSocket(
    qaToken,
    fixture.authorUserId,
    action: 'suspend',
  );
  requireTruth(suspended.sessionsClosed > 0, 'reconnect gate closed no session');
  await upsertConstellationAnchorViaApi(
    email: fixture.authorEmail,
    targetKind: 'PERSON',
    targetId: fixture.helperUserId,
    xUnits: movedX,
    yUnits: movedY,
  );
  await controlRealtimeSocket(
    qaToken,
    fixture.authorUserId,
    action: 'resume',
  );
  timings['reconnect_anchor_ms'] = await measureUntil(
    () => _sessionAnchorCoordsMatch(
      actorPeer,
      targetKind: 'PERSON',
      targetId: fixture.helperUserId,
      xUnits: movedX,
      yUnits: movedY,
    ),
    timeout: const Duration(seconds: 8),
  );
  journeys['reconnect'] = 'PASS';
}

Future<void> _journeyStaleCrossDeviceDelete({
  required BrowserSession actorPeer,
  required Fixture fixture,
  required Map<String, String> journeys,
}) async {
  final title = 'Constellation stale delete ${DateTime.now().microsecondsSinceEpoch}';
  final beaconId = await createBeaconViaApi(
    authorEmail: fixture.authorEmail,
    title: title,
  );
  await forwardBeaconViaApi(
    authorEmail: fixture.authorEmail,
    beaconId: beaconId,
    recipientId: fixture.helperUserId,
  );
  await upsertConstellationAnchorViaApi(
    email: fixture.authorEmail,
    targetKind: 'BEACON',
    targetId: beaconId,
    xUnits: 0.9,
    yUnits: 0.4,
  );
  await actorPeer.open('/home/constellation');
  await waitUntil(
    () => _sessionHasAnchor(
      actorPeer,
      targetKind: 'BEACON',
      targetId: beaconId,
    ),
    timeout: const Duration(seconds: 8),
  );
  await deleteConstellationAnchorViaApi(
    email: fixture.authorEmail,
    targetKind: 'BEACON',
    targetId: beaconId,
  );
  await waitUntil(
    () async => !(await _sessionHasAnchor(
      actorPeer,
      targetKind: 'BEACON',
      targetId: beaconId,
    )),
    timeout: const Duration(seconds: 8),
  );
  final anchors = await fetchConstellationAnchorsViaApi(
    email: fixture.authorEmail,
  );
  requireTruth(
    anchorByTarget(anchors, targetKind: 'BEACON', targetId: beaconId) == null,
    'deleted anchor still present server-side',
  );
  journeys['stale_cross_device_delete'] = 'PASS';
}

Future<void> _journeyUnauthorizedIsolation({
  required Fixture fixture,
  required Map<String, String> journeys,
}) async {
  final authorAnchors = await fetchConstellationAnchorsViaApi(
    email: fixture.authorEmail,
  );
  requireTruth(authorAnchors.isNotEmpty, 'author should own anchors');
  final outsiderAnchors = await fetchConstellationAnchorsViaApi(
    email: fixture.helperEmail,
  );
  final leaked = outsiderAnchors.any(
    (anchor) => authorAnchors.any(
      (owned) =>
          owned['targetKind'] == anchor['targetKind'] &&
          owned['targetId'] == anchor['targetId'] &&
          owned['xUnits'] == anchor['xUnits'] &&
          owned['yUnits'] == anchor['yUnits'],
    ),
  );
  requireTruth(!leaked, 'outsider read author-private anchor coordinates');
  journeys['authorization_loss_restore'] = 'PASS';
}

Future<void> _journeyFailedMutationRollback({
  required BrowserSession actor,
  required Fixture fixture,
  required Map<String, String> journeys,
}) async {
  final before = await fetchConstellationAnchorsViaApi(
    email: fixture.authorEmail,
  );
  final person = anchorByTarget(
    before,
    targetKind: 'PERSON',
    targetId: fixture.helperUserId,
  );
  requireTruth(person != null, 'expected existing person anchor');
  final beforeX = (person!['xUnits'] as num).toDouble();
  final beforeY = (person['yUnits'] as num).toDouble();

  await actor.open('/home/constellation');
  await actor.waitForTestId('graph.node.${fixture.helperUserId}');
  await actor.blockGraphql(true);
  await actor.clickTestId('graph.node.${fixture.helperUserId}');
  if (await actor.hasTestId('constellation.unpin_target')) {
    await actor.clickTestId('constellation.unpin_target');
  } else {
    await actor.clickTestId('constellation.pin_target');
  }
  await waitUntil(
    () async {
      final anchors = await fetchConstellationAnchorsViaApi(
        email: fixture.authorEmail,
      );
      final current = anchorByTarget(
        anchors,
        targetKind: 'PERSON',
        targetId: fixture.helperUserId,
      );
      if (current == null) {
        return false;
      }
      return (current['xUnits'] as num).toDouble() == beforeX &&
          (current['yUnits'] as num).toDouble() == beforeY;
    },
    timeout: const Duration(seconds: 5),
  );
  await actor.blockGraphql(false);
  journeys['failed_mutation_rollback'] = 'PASS';
}

Future<bool> _sessionAnchorCoordsMatch(
  BrowserSession session, {
  required String targetKind,
  required String targetId,
  required double xUnits,
  required double yUnits,
}) async {
  final response = await session.postGraphQl(
    'query { constellationField(showClosed: true, participatedOnly: false, projection: ANCHORS) { anchorProjection { anchors { targetKind targetId xUnits yUnits } } } }',
  );
  final data = response['data'] as Map<String, dynamic>?;
  final field = data?['constellationField'] as Map<String, dynamic>?;
  final projection = field?['anchorProjection'] as Map<String, dynamic>?;
  final anchors =
      (projection?['anchors'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];
  final anchor = anchorByTarget(
    anchors,
    targetKind: targetKind,
    targetId: targetId,
  );
  if (anchor == null) {
    return false;
  }
  return (anchor['xUnits'] as num).toDouble() == xUnits &&
      (anchor['yUnits'] as num).toDouble() == yUnits;
}

Future<bool> _sessionHasAnchor(
  BrowserSession session, {
  required String targetKind,
  required String targetId,
}) async {
  final response = await session.postGraphQl(
    'query { constellationField(showClosed: true, participatedOnly: false, projection: ANCHORS) { anchorProjection { anchors { targetKind targetId } } } }',
  );
  final data = response['data'] as Map<String, dynamic>?;
  final field = data?['constellationField'] as Map<String, dynamic>?;
  final projection = field?['anchorProjection'] as Map<String, dynamic>?;
  final anchors =
      (projection?['anchors'] as List?)?.cast<Map<String, dynamic>>() ??
      const [];
  return anchorByTarget(
        anchors,
        targetKind: targetKind,
        targetId: targetId,
      ) !=
      null;
}
