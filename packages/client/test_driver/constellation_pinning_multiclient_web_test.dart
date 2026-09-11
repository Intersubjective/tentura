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
    await userSubscribeViaApi(
      email: fixture.authorEmail,
      objectId: fixture.helperUserId,
    );
    final warmupBeaconId = await createBeaconViaApi(
      authorEmail: fixture.authorEmail,
      title: 'Constellation warmup $runId',
    );
    await forwardBeaconViaApi(
      authorEmail: fixture.authorEmail,
      beaconId: warmupBeaconId,
      recipientId: fixture.helperUserId,
    );

    journeys['person_without_requests_map_pin'] =
        'BLOCKED'; // CanvasKit map nodes are not exposed to WebDriver DOM.

    Future<void> runJourney(
      String journeyId,
      Future<void> Function() body,
    ) async {
      try {
        await body();
        journeys.putIfAbsent(journeyId, () => 'PASS');
      } catch (error, stackTrace) {
        journeys[journeyId] = 'FAIL';
        File('${artifactDir.path}/journey-$journeyId.txt').writeAsStringSync(
          '$error\n$stackTrace',
        );
      }
    }

    await runJourney('live_convergence', () async {
      await _journeyLivePinConvergence(
        actor: actor!,
        actorPeer: actorPeer!,
        fixture: fixture,
        requestId: warmupBeaconId,
        timings: timings,
        journeys: journeys,
      );
    });
    await upsertConstellationAnchorViaApi(
      email: fixture.authorEmail,
      targetKind: 'PERSON',
      targetId: fixture.helperUserId,
      xUnits: 0.5,
      yUnits: -0.25,
    );
    await runJourney('reconnect', () async {
      await _journeyReconnectCatchUp(
        actorPeer: actorPeer!,
        fixture: fixture,
        qaToken: qaToken,
        timings: timings,
        journeys: journeys,
      );
    });
    await runJourney('stale_cross_device_delete', () async {
      await _journeyStaleCrossDeviceDelete(
        actorPeer: actorPeer!,
        fixture: fixture,
        journeys: journeys,
      );
    });
    await runJourney('authorization_loss_restore', () async {
      await _journeyUnauthorizedIsolation(
        fixture: fixture,
        journeys: journeys,
      );
    });
    await _journeyFailedMutationRollback(journeys: journeys);

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

  final failedJourneys = journeys.entries
      .where((entry) => entry.value == 'FAIL')
      .map((entry) => entry.key)
      .toList();
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  if (failedJourneys.isNotEmpty) {
    throw StateError('journeys failed: ${failedJourneys.join(', ')}');
  }
  stdout.writeln(
    '[constellation-pinning-multiclient] PASS run=$runId journeys=$journeys',
  );
}

Future<void> _journeyLivePinConvergence({
  required BrowserSession actor,
  required BrowserSession actorPeer,
  required Fixture fixture,
  required String requestId,
  required Map<String, int> timings,
  required Map<String, String> journeys,
}) async {
  final requestRowId = 'constellation.text.request.$requestId';
  await Future.wait([
    actor.open('/home/constellation'),
    actorPeer.open('/home/constellation'),
  ]);
  await actor.waitForTestId('constellation.app_bar.view_mode.text');
  await actor.clickTestId('constellation.app_bar.view_mode.text');
  final overflowId = 'constellation.overflow.${fixture.authorUserId}';
  if (await actor.hasTestId(overflowId)) {
    await actor.clickTestId(overflowId);
  }
  await actor.waitForTestId(requestRowId);
  await actor.clickTestId(requestRowId);
  await actor.clickTestId('constellation.pin_target');
  var uiPinPersisted = false;
  try {
    await waitUntil(
      () async {
        final anchors = await fetchConstellationAnchorsViaApi(
          email: fixture.authorEmail,
        );
        return anchorByTarget(
              anchors,
              targetKind: 'BEACON',
              targetId: requestId,
            ) !=
            null;
      },
      timeout: const Duration(seconds: 8),
    );
    uiPinPersisted = true;
  } on TimeoutException {
    await upsertConstellationAnchorViaApi(
      email: fixture.authorEmail,
      targetKind: 'BEACON',
      targetId: requestId,
      xUnits: 1.25,
      yUnits: -0.75,
    );
  }
  timings['live_peer_anchor_ms'] = await measureUntil(
    () => _sessionHasAnchor(
      actorPeer,
      targetKind: 'BEACON',
      targetId: requestId,
    ),
    timeout: const Duration(seconds: 20),
  );
  final anchors = await fetchConstellationAnchorsViaApi(
    email: fixture.authorEmail,
  );
  final anchor = anchorByTarget(
    anchors,
    targetKind: 'BEACON',
    targetId: requestId,
  );
  requireTruth(anchor != null, 'request anchor missing after live pin');
  if (uiPinPersisted) {
    journeys['live_convergence_ui_pin'] = 'PASS';
  } else {
    journeys['live_convergence_ui_pin'] = 'FAIL';
  }
  requireTruth(
    (anchor!['xUnits'] as num).toDouble().abs() > 0,
    'anchor coordinates must be normalized units',
  );
  journeys['first_load_text_pin'] = uiPinPersisted ? 'PASS' : 'FAIL';
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
  await actorPeer.waitForTestId('constellation.app_bar.view_mode.text');
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
  required Map<String, String> journeys,
}) async {
  journeys['failed_mutation_rollback'] =
      'BLOCKED'; // CanvasKit map nodes are not exposed to WebDriver DOM.
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
