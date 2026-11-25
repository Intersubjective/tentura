import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';

import '../../support/constellation_field_wire_fixture.dart';
import '../../support/constellation_tag_lens_body_harness.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';

void main() {
  for (final (tag, members) in [
    (tagLensNeighbour, ['Ann', 'Bob', 'Anna K.']),
    (tagLensWorkshop, ['Ann', 'Boris']),
  ]) {
    testWidgets('Find in ${tag.name} lists only the selected tag’s members', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 11, 8);
      final sent = <WireSent>[];
      await tester.runAsync(
        () => withRemoteWire(
          {
            'ConstellationFieldFetch': constellationFieldWire(
              now: now,
              viewerId: tagLensHarnessEgo.id,
              contacts: const {
                'ann': 'Ann',
                'bob': 'Bob',
                'cid': 'Cid',
                'dan': 'Dan',
              },
              phantoms: [
                constellationPhantomWire(
                  'PHanna0000001',
                  'Anna K.',
                  now: now,
                  tags: [tagLensNeighbour.id],
                ),
                constellationPhantomWire(
                  'PHboris000001',
                  'Boris',
                  now: now,
                  tags: [tagLensWorkshop.id],
                ),
              ],
            ),
          },
          sent,
          (remote) async {
            final realtime = buildTestRealtimeSync();
            final store = ConstellationFieldStoreCase(
              ConstellationRepository(remote),
              const _FieldAccount(),
              FakeClockPort(now),
              FakeWakeUpPort(),
              realtime.case_,
              env: const Env(),
              logger: Logger('FieldTagMembersTest'),
              phantomsEnabled: true,
            );
            addTearDown(() async {
              await store.dispose();
              await realtime.port.dispose();
            });
            final harness = await mountTagLensBody(
              tester,
              fieldStore: store,
            ).timeout(const Duration(seconds: 10));
            final people = harness.field.state.field!.phantoms;
            expect(
              {
                for (final person in people)
                  person.displayName: person.ownTagIds,
              },
              {
                'Anna K.': [tagLensNeighbour.id],
                'Boris': [tagLensWorkshop.id],
              },
              reason:
                  'The Field response must reach the cubit with both tag assignments.',
            );
          },
        ),
      );
      expect(
        sent
            .where(
              (request) => request.operationName == 'ConstellationFieldFetch',
            )
            .map((request) => request.variables['projection']),
        contains('FULL'),
      );
      await tester.tap(find.text(tag.name));
      await settleTagLensBody(tester);

      await tester.tap(find.text('Open tag view'));
      await settleTagLensBody(tester);
      await tester.tap(find.text('Find in tag'));
      await settleTagLensBody(tester);

      final results = find.byKey(
        const Key('constellation-tag-view-find-results'),
      );
      expect(results, findsOneWidget);
      const fieldNames = {
        'Ann',
        'Bob',
        'Cid',
        'Dan',
        'Ego',
        'Anna K.',
        'Boris',
      };
      final names = tester
          .widgetList<Text>(
            find.descendant(of: results, matching: find.byType(Text)),
          )
          .map((text) => text.data ?? text.textSpan?.toPlainText())
          .where(fieldNames.contains);

      expect(names, unorderedEquals(members));
    });
  }
}

class _FieldAccount implements ConstellationAccountPort {
  const _FieldAccount();

  @override
  Stream<String> get currentAccountChanges =>
      Stream.value(tagLensHarnessEgo.id);
}
