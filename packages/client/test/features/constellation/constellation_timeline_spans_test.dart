// VM service is transitive and used only to observe real developer Timeline events.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_anchor_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_placement_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:vm_service/vm_service_io.dart';

import '../../support/test_realtime_sync.dart';
import 'fixtures/constellation_reference_fixture.dart';

import '../../support/constellation_apply_via_writes.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';

final class _Anchors implements ConstellationWriteFake {
  @override
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  }) => throw UnimplementedError('snapshots are not used by this test');

  @override
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  }) => throw UnimplementedError('restore is not used by this test');

  @override
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  }) => throw UnimplementedError('reset is not used by this test');

  final ack = Completer<void>();
  ConstellationAnchor? anchor;

  @override
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  }) => applyViaWrites(this, ops);

  @override
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    await ack.future;
    final revision = ConstellationAnchorRevision(BigInt.two);
    final saved = ConstellationAnchor(
      target: target,
      position: position,
      revision: revision,
      placedAt: DateTime.utc(2026, 10, 7),
    );
    anchor = saved;
    return ConstellationAnchorUpsertResult(anchor: saved, revision: revision);
  }

  @override
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  }) =>
      throw UnimplementedError('This fixture exercises only a successful drop');
}

final class _Field implements ConstellationRepositoryPort {
  _Field(this.anchors);
  final _Anchors anchors;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => constellationReferenceField(
    anchors: [?anchors.anchor],
  );
}

bool _completedSpan(List<Map<String, dynamic>> events, String name) {
  for (final begin in events.where((event) => event['name'] == name)) {
    if (begin['ph'] == 'X' &&
        begin['dur'] is num &&
        (begin['dur'] as num) >= 0) {
      return true;
    }
    if (begin['ph'] != 'B' && begin['ph'] != 'b') continue;
    final endPhase = begin['ph'] == 'B' ? 'E' : 'e';
    if (events.any(
      (end) =>
          end['ph'] == endPhase &&
          end['name'] == name &&
          end['pid'] == begin['pid'] &&
          (endPhase == 'e'
              ? end['id'] == begin['id']
              : end['tid'] == begin['tid']) &&
          end['ts'] is num &&
          begin['ts'] is num &&
          (end['ts'] as num) >= (begin['ts'] as num),
    )) {
      return true;
    }
  }
  return false;
}

void main() {
  testWidgets(
    'drop, layout, composition and scene work emit completed named spans',
    (tester) async {
      final service = await tester.runAsync(() async {
        final info = await developer.Service.controlWebServer(
          enable: true,
          silenceOutput: true,
        );
        final uri = info.serverUri;
        if (uri == null) return null;
        final vm = await vmServiceConnectUri(
          uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
        );
        final flags = await vm.getVMTimelineFlags();
        addTearDown(() async {
          await vm.setVMTimelineFlags(flags.recordedStreams ?? []);
          await vm.dispose();
        });
        await vm.setVMTimelineFlags(['Dart']);
        await vm.clearVMTimeline();
        return vm;
      });
      if (service == null) {
        // Plain `flutter test` runs without a VM service; the dedicated check
        // passes --enable-vmservice and exercises the spans.
        markTestSkipped(
          'VM Timeline capture needs flutter test --enable-vmservice',
        );
        return;
      }
      developer.Timeline.timeSync('constellation.test.capture', () {});

      final anchors = _Anchors();
      final field = _Field(anchors);
      final sync = buildTestRealtimeSync();
      final anchorCase = ConstellationAnchorCase(
        env: const Env.fromEnvironment(),
        logger: Logger('TimelineSpanFixture'),
      );
      final store = ConstellationStoreFixture(
        field,
        accountId: 'ego',
        realtime: sync.case_,
      ).store;
      final placementCase = ConstellationPlacementCase(
        anchors,
        store,
        FakeClockPort(),
        FakeWakeUpPort(),
        realtime: sync.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('TimelineSpanFixture'),
      );
      final cubit = ConstellationCubit(
        case_: store,
        anchorCase: anchorCase,
        placementCase: placementCase,
        viewer: kRefEgo,
        loadOnCreate: false,
      );
      addTearDown(() async {
        if (!anchors.ack.isCompleted) anchors.ack.complete();
        await cubit.close();
        await anchorCase.dispose();
        await placementCase.dispose();
        await sync.port.dispose();
      });
      await cubit.load();
      await pumpConstellationBody(tester, cubit);
      final initialTrace = await tester.runAsync(service.getVMTimeline);
      final initialEvents = initialTrace!.traceEvents!
          .map((event) => event.json!)
          .toList();
      expect(
        _completedSpan(initialEvents, 'constellation.test.capture'),
        isTrue,
        reason: 'Validate capture independently of production instrumentation',
      );
      for (final name in ['layout.job', 'compose', 'scene.build']) {
        expect(
          _completedSpan(initialEvents, name),
          isTrue,
          reason: '$name must be emitted while loading and rendering the field',
        );
      }
      for (final name in [
        'constellation.drop→draggable',
        'drop→acked',
        'drop→reflowed',
      ]) {
        expect(
          initialEvents.where((event) => event['name'] == name),
          isEmpty,
          reason:
              '$name must begin at a drop, rather than during unrelated work',
        );
      }
      final drop = cubit.onNewNodeDrop(
        target: ConstellationAnchorTarget.person('am'),
        sceneCentre: const Offset(2800, 1600),
      );
      await tester.pump();
      final pendingTrace = await tester.runAsync(service.getVMTimeline);
      final pendingEvents = pendingTrace!.traceEvents!
          .map((event) => event.json!)
          .toList();
      expect(
        _completedSpan(pendingEvents, 'constellation.drop→draggable'),
        isTrue,
        reason: 'Local interaction must be restored before the server ACK',
      );
      expect(
        _completedSpan(pendingEvents, 'drop→acked'),
        isFalse,
        reason: 'The ACK span must wait for the repository response',
      );
      for (final name in [
        'drop→acked',
        'drop→reflowed',
      ]) {
        expect(
          pendingEvents.where(
            (event) =>
                event['name'] == name &&
                (event['ph'] == 'B' || event['ph'] == 'b'),
          ),
          isNotEmpty,
          reason: '$name must measure from drop, including the pending ACK',
        );
        expect(
          _completedSpan(pendingEvents, name),
          isFalse,
          reason: '$name must remain open while the repository ACK is pending',
        );
      }
      anchors.ack.complete();
      await drop;
      await tester.pumpAndSettle();
      expect(cubit.isAnchored(ConstellationAnchorTarget.person('am')), isTrue);
      expect(tester.takeException(), isNull);

      final trace = await tester.runAsync(service.getVMTimeline);
      final events = trace!.traceEvents!.map((event) => event.json!).toList();
      for (final name in [
        'constellation.drop→draggable',
        'drop→acked',
        'drop→reflowed',
        'layout.job',
        'compose',
        'scene.build',
      ]) {
        expect(
          _completedSpan(events, name),
          isTrue,
          reason: '$name must be a completed Timeline span from real work',
        );
      }
    },
  );
}
