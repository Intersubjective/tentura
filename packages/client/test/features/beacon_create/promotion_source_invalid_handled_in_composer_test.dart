// When the server refuses a promotion source (code 1311) the composer keeps
// working, tells the user in their language, and nothing reaches the global
// error handlers.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura_root/domain/entity/beacon_creation_context.dart';

import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/remote_wire_harness.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';
import 'post_bud_fakes.dart';

class _UnusedNavigator extends Mock implements AppNavigator {}

const _code = 1311;
const _parentId = 'parent-1';
const _promoted = BeaconCreationContextPromotedChild(
  parentBeaconId: _parentId,
  sourceMessageId: 'msg-1',
);

/// What the server answers when the composer opens from a room message.
const _sourceResponses = <String, Map<String, dynamic>>{
  'BeaconPromotionSource': {
    '__typename': 'query_root',
    'beaconPromotionSource': {
      '__typename': 'v2_BeaconPromotionSource',
      'sourceBeaconId': _parentId,
      'sourceMessageId': 'msg-1',
      'textPreview': 'Need a ladder',
      'author': {
        '__typename': 'v2_BeaconHierarchyOwner',
        'id': 'author-1',
        'displayName': 'Alice',
        'avatarImageId': null,
      },
    },
  },
};

Iterable<Object> _shownErrors(FakeUiEffectPort effects) => [
  for (final e in effects.emitted)
    if (e is ShowError) e.error,
];

BeaconCreateCubit _childCubit({
  required BeaconHierarchyRepository hierarchy,
  required FakeBeaconWritePort write,
  required FakeUiEffectPort effects,
}) {
  final createCase = BeaconCreateCase(write, FakeBeaconImagePort());
  return BeaconCreateCubit(
    beaconCreateCase: createCase,
    hierarchyCase: buildBeaconHierarchyCaseForTest(
      hierarchy,
      createCase: createCase,
      beacons: write,
      commandStore: InMemoryBeaconChildCommandStore(),
    ),
    messagePrefillCase: MessagePrefillCase(FakeBeaconHierarchyRepositoryPort()),
    postBuddingEnabled: false,
    childCreationContext: _promoted,
    effects: effects,
  );
}

/// In-memory drafts, but publishing goes through the real repository.
class _WirePublishWritePort extends FakeBeaconWritePort {
  _WirePublishWritePort(this._real);

  final BeaconRepository _real;

  @override
  Future<void> publishDraft(String id) => _real.publishDraft(id);
}

void main() {
  late FakeUiEffectPort effects;

  setUp(() {
    effects = FakeUiEffectPort();
    GetIt.I
      ..registerSingleton<AppNavigator>(_UnusedNavigator())
      ..registerSingleton<Logger>(Logger('PromotionSourceInvalidTest'));
  });
  tearDown(GetIt.I.reset);

  group('child draft save refused by the server', () {
    test('shows the typed error and leaves the composer usable', () async {
      final write = FakeBeaconWritePort();
      await withRemoteWire(
        _sourceResponses,
        <WireSent>[],
        (remote) async {
          final cubit = _childCubit(
            hierarchy: BeaconHierarchyRepository(remote),
            write: write,
            effects: effects,
          );
          addTearDown(cubit.close);
          await cubit.stream.firstWhere((s) => s.clientCommandId != null);
          cubit
            ..setTitle('Need a ladder')
            ..setDescription('For Saturday.');

          final id = await cubit.ensureDraft(
            context: 'ctx',
            showMessage: false,
          );

          expect(id, isNull);
          expect(
            _shownErrors(effects),
            [isA<BeaconPromotionSourceInvalidException>()],
          );
          expect(cubit.state.status, isA<StateIsSuccess>());
        },
        errors: {'BeaconChildCreate': wireCodeError(_code)},
      );
    });
  });

  group('child draft publish refused by the server', () {
    test('shows the typed error, not a promotion conflict, and keeps the '
        'draft id', () async {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      await withRemoteWire(
        const {},
        <WireSent>[],
        (remote) async {
          // Publishing goes over the real wire; the draft itself already
          // exists, created by the in-memory write port.
          final write = _WirePublishWritePort(
            BeaconRepository(remote, realtime.port),
          );
          final created = FakeBeaconHierarchyRepositoryPort();
          final createCase = BeaconCreateCase(write, FakeBeaconImagePort());
          final cubit = BeaconCreateCubit(
            beaconCreateCase: createCase,
            hierarchyCase: buildBeaconHierarchyCaseForTest(
              created,
              createCase: createCase,
              beacons: write,
              commandStore: InMemoryBeaconChildCommandStore(),
            ),
            postBuddingEnabled: false,
            childCreationContext: _promoted,
            effects: effects,
          );
          addTearDown(cubit.close);
          await cubit.stream.firstWhere((s) => s.clientCommandId != null);
          cubit
            ..setTitle('Need a ladder')
            ..setDescription('For Saturday.');
          final draftId = await cubit.ensureDraft(
            context: 'ctx',
            showMessage: false,
          );
          expect(draftId, isNotEmpty);
          effects.clear();

          await cubit.makeLive(context: 'ctx');

          expect(_shownErrors(effects), [
            isA<BeaconPromotionSourceInvalidException>(),
          ]);
          expect(
            _shownErrors(effects),
            isNot(contains(isA<BeaconChildPromotionConflict>())),
          );
          expect(cubit.state.draftId, draftId);
          expect(cubit.state.status, isA<StateIsSuccess>());
          expect(cubit.state.childPromotionConflict, isFalse);
        },
        errors: {'BeaconPublish': wireCodeError(_code)},
      );
    });
  });

  group('post bud refused by the server', () {
    test('returns null with the typed error and a usable composer', () async {
      await withRemoteWire(
        const {
          'PostBudInviteCandidates': {
            '__typename': 'query_root',
            'postBudInviteCandidates': <Object>[],
          },
        },
        <WireSent>[],
        (remote) async {
          final h = BudHarness();
          final createCase = h.createCase;
          final cubit = BeaconCreateCubit(
            beaconCreateCase: createCase,
            hierarchyCase: buildBeaconHierarchyCaseForTest(
              h.hierarchy,
              createCase: createCase,
              beacons: h.write,
              commandStore: InMemoryBeaconChildCommandStore(),
            ),
            messagePrefillCase: h.prefillCase,
            postBudCase: PostBudCase(
              PostBudRepository(remote),
              OpIdService(),
              env: const Env(),
              logger: Logger('post-bud-test'),
            ),
            childCreationContext: kBudContext,
            effects: effects,
          );
          addTearDown(cubit.close);
          await cubit.stream.firstWhere((s) => s.postBud != null);
          // Let the bud form's own Post reads settle.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          cubit
            ..setTitle('Need a ladder')
            ..setDescription('For Saturday.');

          final forward = await BudForward.start(h);
          addTearDown(forward.dispose);
          final invite = await forward.inviteCubit();
          addTearDown(invite.close);

          final result = await cubit.submitBud(
            context: '',
            forwardCubit: invite,
          );

          expect(result, isNull);
          expect(
            _shownErrors(effects),
            [isA<BeaconPromotionSourceInvalidException>()],
          );
          expect(cubit.state.status, isA<StateIsSuccess>());
        },
        errors: {'PostBudFromPost': wireCodeError(_code)},
      );
    });
  });
}
