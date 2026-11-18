import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/exception.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';

class _LiveSyncForwardRepository implements ForwardRepository {
  _LiveSyncForwardRepository({
    this.candidates = const [],
  });

  List<Profile> candidates;
  Future<Iterable<Profile>> Function()? fetchCandidatesHandler;
  Future<Beacon> Function(String)? fetchBeaconHandler;
  int fetchForwardCandidatesCalls = 0;
  int forwardBeaconCalls = 0;
  Map<String, String>? lastPerRecipientNotes;

  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  void emitForwardCompleted(String beaconId) => _forwardChanges.add(beaconId);

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    fetchForwardCandidatesCalls++;
    final handler = fetchCandidatesHandler;
    return handler == null ? candidates : await handler();
  }

  @override
  Future<Beacon> fetchBeaconById(String beaconId) async {
    final handler = fetchBeaconHandler;
    return handler == null
        ? Beacon.empty.copyWith(id: beaconId, viewerCanForward: true)
        : await handler(beaconId);
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) => fetchInvolvementForBeacon(
    Beacon.empty.copyWith(id: beaconId, viewerCanForward: true),
  );

  @override
  Future<BeaconInvolvementData> fetchInvolvementForBeacon(
    Beacon beacon,
  ) async => (
    beacon: beacon,
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    declinedOfferIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );

  @override
  Future<ForwardDeliveryResult> forwardBeacon({
    required String beaconId,
    required List<String> recipientIds,
    String? note,
    Map<String, String>? perRecipientNotes,
    Map<String, List<String>>? recipientReasons,
    String? context,
    String? parentEdgeId,
    List<String>? attributionParentEdgeIds,
    Map<String, ({String? tier, bool isExploration})>? recipientBandProvenance,
  }) async {
    forwardBeaconCalls++;
    lastPerRecipientNotes = perRecipientNotes;
    if (!_forwardChanges.isClosed) {
      emitForwardCompleted(beaconId);
    }
    return ForwardDeliveryResult(
      batchId: 'edge-1',
      deliveredRecipientIds: recipientIds,
      availabilitySkippedRecipientIds: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    ForwardCase forwardCase,
    _LiveSyncForwardRepository forwardRepo,
    ContactsCase contactsCase,
    FakeContactsRepository contactsRepo,
    ContactNameStore store,
    ControllableBlockCase blockCase,
  })
>
_buildForwardCaseHarness() async {
  final authLocal = StreamingAuthLocal();
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  final contactsCase = ContactsCase(
    contactsRepo,
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    store,
    buildTestRealtimeSync().case_,
    env: const Env(),
    logger: Logger('test'),
  );
  final forwardRepo = _LiveSyncForwardRepository(
    candidates: const [
      Profile(id: 'u-bob', displayName: 'Robert', rScore: 1, score: 1),
    ],
  );
  final blockCase = ControllableBlockCase();
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(),
    contactsCase,
    blockCase,
    env: const Env(),
    logger: Logger('test'),
  );
  contactsRepo.fetchMineHandler = () async => {'u-bob': 'Gym Bob'};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('viewer');
  await syncReady;
  await Future<void>.delayed(Duration.zero);
  return (
    forwardCase: forwardCase,
    forwardRepo: forwardRepo,
    contactsCase: contactsCase,
    contactsRepo: contactsRepo,
    store: store,
    blockCase: blockCase,
  );
}

Matcher _readyWith(String candidateId) => isA<ForwardState>()
    .having(
      (state) => state.candidatesLoad,
      'load',
      isA<ForwardCandidatesReady>(),
    )
    .having((state) => state.candidates.map((c) => c.id), 'candidate IDs', [
      candidateId,
    ])
    .having((state) => state.status, 'status', isA<StateIsSuccess>());

final _permissionDenied = isA<ForwardCandidatesError>().having(
  (load) => load.error,
  'error',
  isA<ForwardPermissionDenied>(),
);

class _PendingCandidateFetch {
  final _started = Completer<void>();
  final _response = Completer<Iterable<Profile>>();
  final _returned = Completer<void>();

  Future<void> get started => _started.future;

  Future<Iterable<Profile>> fetch() async {
    _started.complete();
    try {
      return await _response.future;
    } finally {
      _returned.complete();
    }
  }

  Future<void> succeed(Profile candidate) {
    _response.complete([candidate]);
    return _settle();
  }

  Future<void> fail(Exception error) {
    _response.completeError(error);
    return _settle();
  }

  Future<void> _settle() async {
    await _returned.future;
    // After the fake returns or throws, let the use case and cubit consume
    // that result. Every other dependency in this harness resolves in memory.
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Forward picker uses the latest load', () {
    const alice = Profile(id: 'u-alice', displayName: 'Alice');
    const bob = Profile(id: 'u-bob', displayName: 'Bob');
    const carol = Profile(id: 'u-carol', displayName: 'Carol');
    const waitForResponse = Duration(seconds: 5);

    late _LiveSyncForwardRepository forwardRepo;
    late ControllableBlockCase blockCase;
    late FakeUiEffectPort effects;
    late NetworkReachability reachability;
    late ForwardCubit Function() openPicker;

    setUp(() async {
      final harness = await _buildForwardCaseHarness();
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.blockCase.dispose();
        await GetIt.I.unregister<ContactNameStore>();
        await harness.store.dispose();
      });
      forwardRepo = harness.forwardRepo;
      blockCase = harness.blockCase;
      effects = FakeUiEffectPort();
      reachability = NetworkReachability.forTesting();
      GetIt.I.registerSingleton<NetworkReachabilityPort>(reachability);
      addTearDown(() async {
        await GetIt.I.unregister<NetworkReachabilityPort>();
        await reachability.dispose();
      });
      openPicker = () {
        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: effects,
          checkForwardPermission: true,
        );
        addTearDown(cubit.close);
        return cubit;
      };
    });

    for (final trigger in ['a block change', 'a forwarding change']) {
      test(
        'permission denial from $trigger survives a late response',
        () async {
          final olderCandidates = _PendingCandidateFetch();
          forwardRepo.fetchCandidatesHandler = olderCandidates.fetch;
          final cubit = openPicker();
          await olderCandidates.started.timeout(waitForResponse);

          forwardRepo.fetchBeaconHandler = (id) async =>
              Beacon.empty.copyWith(id: id, viewerCanForward: false);
          final denial = cubit.stream.firstWhere(
            (state) => state.candidatesLoad is ForwardCandidatesError,
          );
          if (trigger == 'a block change') {
            blockCase.emitBlock();
          } else {
            forwardRepo.emitForwardCompleted(cubit.state.beaconId);
          }
          expect(
            (await denial.timeout(waitForResponse)).candidatesLoad,
            _permissionDenied,
          );

          final loadsAfterDenial = <ForwardCandidatesLoad>[];
          final subscription = cubit.stream.listen(
            (state) => loadsAfterDenial.add(state.candidatesLoad),
          );
          addTearDown(subscription.cancel);
          await olderCandidates.succeed(alice).timeout(waitForResponse);

          expect(cubit.state.candidatesLoad, _permissionDenied);
          expect(cubit.state.candidates, isEmpty);
          expect(cubit.state.status, isA<StateIsSuccess>());
          expect(loadsAfterDenial.where((load) => load.isLoaded), isEmpty);
        },
      );
    }

    final refreshTriggers =
        <
          ({
            String name,
            bool afterLoadError,
            Future<void>? Function(ForwardCubit) start,
          })
        >[
          (
            name: 'manual refresh',
            afterLoadError: false,
            start: (cubit) => cubit.reloadCandidates(),
          ),
          (
            name: 'block change',
            afterLoadError: false,
            start: (_) {
              blockCase.emitBlock();
              return null;
            },
          ),
          (
            name: 'forwarding change',
            afterLoadError: false,
            start: (cubit) {
              forwardRepo.emitForwardCompleted(cubit.state.beaconId);
              return null;
            },
          ),
          (
            name: 'retry',
            afterLoadError: true,
            start: (cubit) => cubit.retryLoadCandidates(),
          ),
          (
            name: 'reconnect',
            afterLoadError: true,
            start: (_) {
              reachability.reportSuccess();
              return null;
            },
          ),
        ];

    for (final trigger in refreshTriggers) {
      group(trigger.name, () {
        for (final outcome in ['success', 'failure']) {
          test(
            'a late $outcome leaves the latest recipients in place',
            () async {
              final initialError = Exception('Offline during first load');
              forwardRepo.candidates = [carol];
              if (trigger.afterLoadError) {
                forwardRepo.fetchCandidatesHandler = () async {
                  reachability.reportTransportFailure();
                  throw initialError;
                };
              }
              final cubit = openPicker();
              final initialState = await cubit.stream
                  .firstWhere((state) => state.status is StateIsSuccess)
                  .timeout(waitForResponse);
              if (trigger.afterLoadError) {
                expect(
                  initialState.candidatesLoad,
                  isA<ForwardCandidatesError>().having(
                    (load) => load.error,
                    'error',
                    same(initialError),
                  ),
                );
              } else {
                expect(initialState, _readyWith(carol.id));
              }

              final olderCandidates = _PendingCandidateFetch();
              forwardRepo.fetchCandidatesHandler = olderCandidates.fetch;
              final olderReload = trigger.start(cubit);
              await olderCandidates.started.timeout(waitForResponse);

              forwardRepo
                ..fetchCandidatesHandler = null
                ..candidates = [bob];
              await cubit.reloadCandidates().timeout(waitForResponse);
              expect(cubit.state, _readyWith(bob.id));

              if (outcome == 'success') {
                await olderCandidates.succeed(alice).timeout(waitForResponse);
              } else {
                await olderCandidates
                    .fail(Exception('Candidate fetch failed'))
                    .timeout(waitForResponse);
              }
              if (olderReload != null) {
                await olderReload.timeout(waitForResponse);
              }
              final stateAfterOlderReload = cubit.state;
              final staleErrors = effects.emitted
                  .whereType<ShowError>()
                  .toList();

              forwardRepo.candidates = [carol];
              await cubit.reloadCandidates().timeout(waitForResponse);
              expect(cubit.state, _readyWith(carol.id));

              expect(stateAfterOlderReload, _readyWith(bob.id));
              expect(staleErrors, isEmpty);
            },
          );
        }
      });
    }

    test(
      'an older denial cannot hide recipients after a permitted reload',
      () async {
        final checkingPermission = Completer<String>();
        final olderBeacon = Completer<Beacon>();
        forwardRepo.fetchBeaconHandler = (id) {
          checkingPermission.complete(id);
          return olderBeacon.future;
        };
        final cubit = openPicker();
        final beaconId = await checkingPermission.future.timeout(
          waitForResponse,
        );

        forwardRepo
          ..fetchBeaconHandler = null
          ..candidates = [bob];
        final ready = cubit.stream.firstWhere(
          (state) => state.candidatesLoad is ForwardCandidatesReady,
        );
        blockCase.emitBlock();
        expect(await ready.timeout(waitForResponse), _readyWith(bob.id));

        olderBeacon.complete(
          Beacon.empty.copyWith(id: beaconId, viewerCanForward: false),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, _readyWith(bob.id));
      },
    );
  });

  group('ForwardCubit live contact sync', () {
    test(
      'forwardChanges reloads candidates even when memo key unchanged',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        expect(cubit.state.candidates.single.profile.shownName, 'Gym Bob');
        expect(harness.forwardRepo.fetchForwardCandidatesCalls, 1);

        harness.contactsRepo.fetchMineHandler = () async => {
          'u-bob': 'Alias Bob',
        };
        harness.forwardRepo.emitForwardCompleted('b1');

        await cubit.stream.firstWhere(
          (s) => s.candidates.single.profile.shownName == 'Alias Bob',
        );
        expect(harness.forwardRepo.fetchForwardCandidatesCalls, 2);
      },
    );

    test(
      'contactChanges patches candidate names without full reload',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        final fetchCallsBefore =
            harness.forwardRepo.fetchForwardCandidatesCalls;

        await harness.contactsCase.rename(
          subjectId: 'u-bob',
          contactName: 'Renamed Bob',
        );

        await cubit.stream.firstWhere(
          (s) => s.candidates.single.profile.shownName == 'Renamed Bob',
        );
        expect(
          harness.forwardRepo.fetchForwardCandidatesCalls,
          fetchCallsBefore,
        );
      },
    );

    test(
      'forward stays on screen after send with delivery',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final effects = FakeUiEffectPort();
        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: effects,
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        final filterBefore = cubit.state.activeFilter;
        cubit.emit(
          cubit.state.copyWith(
            selectedIds: {'u-bob'},
            perRecipientNotes: {'u-bob': 'personal'},
            beacon:
                cubit.state.beacon ??
                Beacon.empty.copyWith(
                  id: 'b1',
                  status: BeaconStatus.open,
                  viewerCanForward: true,
                ),
          ),
        );

        await cubit.forward();

        expect(effects.emitted.whereType<ShowMessage>(), hasLength(1));
        final showMessage = effects.emitted.whereType<ShowMessage>().single;
        expect(showMessage.message, isA<ForwardLocationMessage>());
        expect(
          (showMessage.message as ForwardLocationMessage).toEn,
          "Request forwarded. It's in Following.",
        );
        expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(cubit.state.activeFilter, ForwardFilter.alreadyInvolved);
        expect(cubit.state.activeFilter, isNot(filterBefore));
        expect(cubit.state.lastDeliveredRecipientIds, ['u-bob']);
        expect(cubit.state.selectedIds, isEmpty);
        expect(cubit.state.perRecipientNotes, isEmpty);
        expect(cubit.state.perRecipientNotes, isEmpty);
        expect(cubit.state.note, isEmpty);
      },
    );

    test(
      'all-paused early return emits no NavigateBack and keeps activeFilter',
      () async {
        final pausedUntil = DateTime.utc(2026, 8, 20);
        final harness = await _buildForwardCaseHarness();
        harness.forwardRepo.candidates = [
          Profile(
            id: 'u-paused',
            displayName: 'Paused',
            rScore: 1,
            score: 1,
            availability: Availability(resumeOn: pausedUntil),
          ),
        ];
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final effects = FakeUiEffectPort();
        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: effects,
          clock: () => DateTime.utc(2026, 8, 14),
          initialSelectedIds: {'u-paused'},
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        final filterBefore = cubit.state.activeFilter;
        cubit.emit(
          cubit.state.copyWith(
            selectedIds: {'u-paused'},
            perRecipientNotes: {'u-paused': 'note'},
            beacon:
                cubit.state.beacon ??
                Beacon.empty.copyWith(
                  id: 'b1',
                  status: BeaconStatus.open,
                  viewerCanForward: true,
                ),
          ),
        );

        final ok = await cubit.forward();

        expect(ok, isTrue);
        expect(harness.forwardRepo.forwardBeaconCalls, 0);
        expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
        expect(cubit.state.activeFilter, filterBefore);
        expect(cubit.state.lastDeliveredRecipientIds, isEmpty);
      },
    );

    test(
      'unticked recipient personal note is omitted from forwardBeacon payload',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        cubit.emit(
          cubit.state.copyWith(
            selectedIds: {'u-bob'},
            perRecipientNotes: {
              'u-bob': 'send me',
              'u-alice': 'stay in draft',
            },
            beacon:
                cubit.state.beacon ??
                Beacon.empty.copyWith(
                  id: 'b1',
                  status: BeaconStatus.open,
                  viewerCanForward: true,
                ),
          ),
        );

        await cubit.forward();

        expect(harness.forwardRepo.forwardBeaconCalls, 1);
        expect(harness.forwardRepo.lastPerRecipientNotes, {
          'u-bob': 'send me',
        });
      },
    );

    test(
      'skipped personal note id is omitted from forwardBeacon perRecipientNotes',
      () async {
        final harness = await _buildForwardCaseHarness();
        addTearDown(() async {
          await harness.forwardRepo.dispose();
          await harness.contactsCase.dispose();
          if (GetIt.I.isRegistered<ContactNameStore>()) {
            await GetIt.I.unregister<ContactNameStore>();
          }
          await harness.store.dispose();
        });

        final cubit = ForwardCubit(
          beaconId: 'b1',
          forwardCase: harness.forwardCase,
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);

        await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
        cubit.emit(
          cubit.state.copyWith(
            selectedIds: {'u-bob'},
            perRecipientNotes: {'u-bob': 'leftover typed note'},
            beacon:
                cubit.state.beacon ??
                Beacon.empty.copyWith(
                  id: 'b1',
                  status: BeaconStatus.open,
                  viewerCanForward: true,
                ),
          ),
        );

        await cubit.forward();

        expect(harness.forwardRepo.forwardBeaconCalls, 1);
        expect(harness.forwardRepo.lastPerRecipientNotes, {
          'u-bob': 'leftover typed note',
        });
      },
    );

    test('blockChanges reloads candidates', () async {
      final harness = await _buildForwardCaseHarness();
      addTearDown(() async {
        await harness.forwardRepo.dispose();
        await harness.contactsCase.dispose();
        await harness.blockCase.dispose();
        if (GetIt.I.isRegistered<ContactNameStore>()) {
          await GetIt.I.unregister<ContactNameStore>();
        }
        await harness.store.dispose();
      });

      final cubit = ForwardCubit(
        beaconId: 'b1',
        forwardCase: harness.forwardCase,
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await cubit.stream.firstWhere((s) => s.candidates.isNotEmpty);
      expect(harness.forwardRepo.fetchForwardCandidatesCalls, 1);

      harness.blockCase.emitBlock();
      await Future<void>.delayed(Duration.zero);

      expect(harness.forwardRepo.fetchForwardCandidatesCalls, 2);
    });
  });
}
