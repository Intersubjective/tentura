// «Create from this Request» with facts to bring (fact continuity plan D14,
// §6.4). The editor opens on a local copy; the ticked fact ids live in the
// create cubit (route wiring: fork_facts_route_reaches_create_cubit_test)
// and travel with the lazy lineage fork the cubit runs
// at the copy's first save.
//
// The fork goes through the production BeaconCreateCase and BeaconRepository
// over the real Ferry link chain; only HTTP is faked (remote_wire_harness),
// so the assertions read the BeaconFork variables as sent on the wire. Only
// beacon reads are stubbed (they are not under test).
//
// `forkFactIds` does not exist yet on the cubit, so it is passed through
// `Function.apply`: each test fails on its own instead of the file failing
// to compile.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';

import '../../support/beacon_create_case_factory.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _forkedId = 'Bforked000001';

final _source = Beacon.empty.copyWith(
  id: 'Bsource00001',
  title: 'Fix the north fence',
  description: 'Posts are loose near the gate.',
  status: BeaconStatus.open,
);

/// The real repository; beacon reads answer from memory so the test only
/// depends on the fork's wire shape.
class _WireBeaconRepository extends BeaconRepository {
  _WireBeaconRepository(RemoteApiService remote)
    : super(remote, TestRealtimeSyncPort());

  @override
  Future<Beacon> fetchBeaconById(String id) async => id == _source.id
      ? _source
      : _source.copyWith(
          id: id,
          status: BeaconStatus.draft,
          lineageParentBeaconId: _source.id,
        );
}

/// Opens the copy editor the way the create screen does for
/// `fork_from=<source>` (+ `fork_plan`, `fork_facts`).
BeaconCreateCubit _openCopy(
  BeaconCreateCase createCase, {
  List<String>? forkFactIds,
  List<PlanStepTime>? planStepTimes,
}) {
  final cubit =
      Function.apply(BeaconCreateCubit.new, const [], {
            #beaconCreateCase: createCase,
            #effects: FakeUiEffectPort(),
            #forkSourceIdToLoad: _source.id,
            #forkPlanStepTimes: planStepTimes,
            #forkTitle: (String t) => 'Copy of $t',
            #forkFactIds: ?forkFactIds,
          })
          as BeaconCreateCubit;
  addTearDown(cubit.close);
  return cubit;
}

Future<void> _waitLoaded(BeaconCreateCubit cubit) async {
  if (cubit.state.title.isEmpty || cubit.state.isLoading) {
    await cubit.stream
        .firstWhere((s) => s.title.isNotEmpty && !s.isLoading)
        .timeout(const Duration(seconds: 2));
  }
  cubit.setAutosaveContext('');
}

/// Edits the copy so autosave runs the lazy fork, and returns the variables
/// of the BeaconFork operation it sent.
Future<Map<String, dynamic>> _forkVariables({
  List<String>? forkFactIds,
  List<PlanStepTime>? planStepTimes,
}) async {
  final sent = <WireSent>[];
  await withRemoteWire(
    {
      'BeaconFork': {
        '__typename': 'mutation_root',
        'beaconFork': {'__typename': 'v2_Beacon', 'id': _forkedId},
      },
    },
    sent,
    (remote) async {
      final cubit = _openCopy(
        buildBeaconCreateCase(beacons: _WireBeaconRepository(remote)),
        forkFactIds: forkFactIds,
        planStepTimes: planStepTimes,
      );
      await _waitLoaded(cubit);
      cubit.setDescription('Bring a hammer too.');
      // The follow-up draft save is not answered here; only the fork matters.
      try {
        await cubit.flushAutosave().timeout(const Duration(seconds: 5));
      } on Object catch (_) {}
    },
  );
  final forks = [
    for (final s in sent)
      if (s.operationName == 'BeaconFork') s.variables,
  ];
  expect(forks, hasLength(1), reason: 'the first edit forks exactly once');
  return forks.single;
}

void main() {
  group('the lazy fork carries the ticked facts to the server', () {
    test('BeaconFork sends exactly the ticked ids as factIds', () async {
      final vars = await _forkVariables(forkFactIds: const ['Fkey', 'Fshed']);

      expect(vars['id'], _source.id);
      expect(vars['factIds'], ['Fkey', 'Fshed']);
      // No plan was chosen: the plan arguments stay absent.
      expect(vars.containsKey('copyPlan'), isFalse);
      expect(vars.containsKey('planStepTimes'), isFalse);
    });

    test('ticked facts leave the plan arguments unchanged', () async {
      final times = [
        PlanStepTime(
          sourceStepId: 'PS1',
          startAt: DateTime.utc(2026, 12, 1, 9),
          endAt: DateTime.utc(2026, 12, 1, 10),
        ),
        const PlanStepTime(sourceStepId: 'PS2'),
      ];
      final withFacts = await _forkVariables(
        forkFactIds: const ['Fkey'],
        planStepTimes: times,
      );

      expect(withFacts['factIds'], ['Fkey']);
      expect(withFacts['copyPlan'], isTrue);
      expect(withFacts['planStepTimes'], [
        {
          'sourceStepId': 'PS1',
          'startAt': '2026-12-01T09:00:00.000Z',
          'endAt': '2026-12-01T10:00:00.000Z',
        },
        {'sourceStepId': 'PS2'},
      ]);
    });

    test('with nothing ticked BeaconFork sends no factIds', () async {
      final vars = await _forkVariables(forkFactIds: const []);

      expect(vars['id'], _source.id);
      expect(vars.containsKey('factIds'), isFalse);
    });
  });
}
