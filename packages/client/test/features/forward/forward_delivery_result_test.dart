import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_delivery_result.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../../support/test_realtime_sync.dart';

class _DeliveryForwardRepository implements ForwardRepository {
  _DeliveryForwardRepository({
    required this.involvement,
    this.candidates = const [],
    ForwardDeliveryResult? forwardResult,
  }) : _forwardResult = forwardResult;

  final List<Profile> candidates;
  final BeaconInvolvementData involvement;
  ForwardDeliveryResult? _forwardResult;

  int forwardBeaconCalls = 0;
  int fetchCandidatesCalls = 0;
  List<String>? lastRecipientIds;
  final _forwardChanges = StreamController<String>.broadcast();

  void setForwardResult(ForwardDeliveryResult result) => _forwardResult = result;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  void emitForwardChange(String beaconId) {
    if (!_forwardChanges.isClosed) {
      _forwardChanges.add(beaconId);
    }
  }

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async {
    fetchCandidatesCalls++;
    return candidates;
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => involvement;

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
    Map<String, ({String? tier, bool isExploration})>?
    recipientBandProvenance,
  }) async {
    forwardBeaconCalls++;
    lastRecipientIds = recipientIds;
    emitForwardChange(beaconId);
    return _forwardResult ??
        ForwardDeliveryResult(
          batchId: 'batch-$forwardBeaconCalls',
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

Beacon _openBeacon({String id = 'B1'}) => Beacon.empty.copyWith(
  id: id,
  status: BeaconStatus.open,
  author: const Profile(id: 'U-me'),
);

BeaconInvolvementData _involvement(Beacon beacon) => (
  beacon: beacon,
  forwardedToIds: <String>{},
  helpOfferedIds: <String>{},
  withdrawnIds: <String>{},
  rejectedIds: <String>{},
  watchingIds: <String>{},
  onwardForwarderIds: <String>{},
  myForwardedRecipientNotes: <String, String>{},
  myForwardedRecipientEdgeIds: <String, String>{},
  myForwardedRecipientReadAts: <String, DateTime?>{},
  myForwardedRecipientHasOnwardChild: <String, bool>{},
  myForwardedRecipientRejected: <String, bool>{},
);

Profile _profile({
  required String id,
  required String name,
  Availability availability = const Availability(),
}) => Profile(
  id: id,
  displayName: name,
  score: 1,
  rScore: 1,
  availability: availability,
);

Future<
  ({
    ForwardCase forwardCase,
    _DeliveryForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
>
_buildHarness({
  required BeaconInvolvementData involvement,
  List<Profile> candidates = const [],
  ForwardDeliveryResult? forwardResult,
}) async {
  final authLocal = StreamingAuthLocal('U-me');
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
  contactsRepo.fetchMineHandler = () async => {};
  final syncReady = contactsRepo.nextSync();
  authLocal.emit('U-me');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardRepo = _DeliveryForwardRepository(
    involvement: involvement,
    candidates: candidates,
    forwardResult: forwardResult,
  );
  final forwardCase = ForwardCase(
    forwardRepo,
    authLocal,
    _FakeBeaconFactCardRepository(),
    _FakeProfileRepository(),
    contactsCase,
    ControllableBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
  return (
    forwardCase: forwardCase,
    forwardRepo: forwardRepo,
    contactsCase: contactsCase,
    store: store,
  );
}

Future<void> _disposeHarness(
  ({
    ForwardCase forwardCase,
    _DeliveryForwardRepository forwardRepo,
    ContactsCase contactsCase,
    ContactNameStore store,
  })
  harness,
) async {
  await harness.forwardRepo.dispose();
  await harness.contactsCase.dispose();
  if (GetIt.I.isRegistered<ContactNameStore>()) {
    await GetIt.I.unregister<ContactNameStore>();
  }
  await harness.store.dispose();
}

ForwardCubit _cubit({
  required ForwardCase forwardCase,
  required FakeUiEffectPort effects,
  DateTime Function()? clock,
  ForwardTimerFactory? timerFactory,
  ForwardLifecycleListenerFactory? lifecycleListenerFactory,
  Set<String> initialSelectedIds = const {},
  bool embedded = false,
}) => ForwardCubit(
  beaconId: 'B1',
  forwardCase: forwardCase,
  effects: effects,
  clock: clock,
  timerFactory: timerFactory,
  lifecycleListenerFactory: lifecycleListenerFactory,
  initialSelectedIds: initialSelectedIds,
  embedded: embedded,
);

Future<void> _waitReady(ForwardCubit cubit) async {
  await cubit.stream.firstWhere((s) => s.candidatesLoad is ForwardCandidatesReady);
}

void main() {
  final todayUtc = DateTime.utc(2026, 8, 14);
  final pausedUntil = DateTime.utc(2026, 8, 20);
  DateTime clockNow = DateTime.utc(2026, 8, 14, 12);

  DateTime clock() => clockNow;

  test('missing dropped preselect does not emit availability delivery outcome', () async {
    final effects = FakeUiEffectPort();
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
      initialSelectedIds: {'U-missing'},
    );
    addTearDown(cubit.close);
    await cubit.stream.firstWhere(
      (s) => s.candidatesLoad is ForwardCandidatesEmpty,
    );

    final ok = await cubit.forward();
    expect(ok, isFalse);
    expect(harness.forwardRepo.forwardBeaconCalls, 0);
    expect(cubit.state.lastDeliveryOutcome, isNull);
    expect(effects.emitted.whereType<ShowMessage>(), isEmpty);
    expect(effects.emitted.whereType<ShowError>(), isEmpty);
  });

  test(
    'disappeared selected recipient hits hard validation not availability skip',
    () async {
      final effects = FakeUiEffectPort();
      final harness = await _buildHarness(
        involvement: _involvement(_openBeacon()),
        candidates: [_profile(id: 'U-alice', name: 'Alice')],
      );
      addTearDown(() => _disposeHarness(harness));

      final cubit = _cubit(
        forwardCase: harness.forwardCase,
        effects: effects,
        clock: clock,
      );
      addTearDown(cubit.close);
      await _waitReady(cubit);

      cubit.emit(
        cubit.state.copyWith(
          selectedIds: {'U-alice', 'U-disappeared'},
          beacon: _openBeacon(),
        ),
      );

      final ok = await cubit.forward();
      expect(ok, isFalse);
      expect(harness.forwardRepo.forwardBeaconCalls, 0);
      expect(cubit.state.lastDeliveryOutcome, isNull);
      expect(effects.emitted.whereType<ShowMessage>(), isEmpty);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    },
  );

  test('local availability strip avoids mutation and reports all skipped', () async {
    final effects = FakeUiEffectPort();
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(
          id: 'U-paused',
          name: 'Carol',
          availability: Availability(resumeOn: pausedUntil),
        ),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
      initialSelectedIds: {'U-paused'},
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-paused'},
        skippedPersonalNoteIds: {'U-paused'},
        beacon: _openBeacon(),
      ),
    );

    final ok = await cubit.forward();
    expect(ok, isTrue);
    expect(harness.forwardRepo.forwardBeaconCalls, 0);
    expect(cubit.state.lastDeliveryOutcome?.deliveredRecipientIds, isEmpty);
    expect(
      cubit.state.lastDeliveryOutcome?.availabilitySkippedRecipientIds,
      ['U-paused'],
    );
    expect(
      effects.emitted.whereType<ShowMessage>().single.message,
      isA<ForwardPartialDeliveryMessage>(),
    );
  });

  test('mixed delivery emits single location message with pause clause', () async {
    final effects = FakeUiEffectPort();
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(id: 'U-alice', name: 'Alice'),
        _profile(id: 'U-bob', name: 'Bob'),
        _profile(id: 'U-carol', name: 'Carol'),
      ],
      forwardResult: const ForwardDeliveryResult(
        batchId: 'batch-race',
        deliveredRecipientIds: ['U-alice'],
        availabilitySkippedRecipientIds: ['U-carol'],
      ),
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice', 'U-bob', 'U-carol'},
        skippedPersonalNoteIds: {'U-alice', 'U-bob', 'U-carol'},
        beacon: _openBeacon(),
      ),
    );

    await cubit.forward();

    expect(harness.forwardRepo.lastRecipientIds, ['U-alice', 'U-bob', 'U-carol']);
    expect(
      cubit.state.lastDeliveryOutcome?.deliveredRecipientIds,
      ['U-alice'],
    );
    expect(
      cubit.state.lastDeliveryOutcome?.availabilitySkippedRecipientIds,
      ['U-carol'],
    );
    expect(effects.emitted.whereType<ShowMessage>(), hasLength(1));
    expect(
      effects.emitted.whereType<ShowMessage>().single.message,
      isA<ForwardLocationMyWorkMessage>(),
    );
    expect(
      (effects.emitted.whereType<ShowMessage>().single.message
              as ForwardLocationMyWorkMessage)
          .toEn,
      'Request forwarded. It\'s in My Work. — Carol isn\'t taking new requests right now.',
    );
  });

  test('mixed local and server skips dedupe in original requested order', () async {
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(id: 'U-alice', name: 'Alice'),
        _profile(
          id: 'U-local',
          name: 'Local',
          availability: Availability(resumeOn: pausedUntil),
        ),
        _profile(id: 'U-server', name: 'Server'),
      ],
      forwardResult: const ForwardDeliveryResult(
        batchId: 'batch-mixed',
        deliveredRecipientIds: ['U-alice'],
        availabilitySkippedRecipientIds: ['U-server'],
      ),
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      clock: clock,
      initialSelectedIds: {'U-local'},
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice', 'U-server'},
        skippedPersonalNoteIds: {'U-alice', 'U-server'},
        beacon: _openBeacon(),
      ),
    );

    await cubit.forward();

    expect(harness.forwardRepo.lastRecipientIds, ['U-alice', 'U-server']);
    expect(
      cubit.state.lastDeliveryOutcome?.requestedRecipientIds,
      ['U-local', 'U-alice', 'U-server'],
    );
    expect(
      cubit.state.lastDeliveryOutcome?.availabilitySkippedRecipientIds,
      ['U-local', 'U-server'],
    );
  });

  test('full delivery keeps location copy for author', () async {
    final effects = FakeUiEffectPort();
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(id: 'U-alice', name: 'Alice'),
        _profile(id: 'U-bob', name: 'Bob'),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice', 'U-bob'},
        skippedPersonalNoteIds: {'U-alice', 'U-bob'},
        beacon: _openBeacon(),
      ),
    );

    await cubit.forward();

    final message = effects.emitted.whereType<ShowMessage>().single.message;
    expect(message, isA<ForwardLocationMyWorkMessage>());
    expect(
      (message as ForwardLocationMyWorkMessage).toEn,
      'Request forwarded. It\'s in My Work.',
    );
    expect(cubit.state.lastDeliveryOutcome?.deliveredCount, 2);
  });

  test('full delivery uses watching location when viewer is not author', () async {
    final effects = FakeUiEffectPort();
    final otherAuthorBeacon = Beacon.empty.copyWith(
      id: 'B1',
      status: BeaconStatus.open,
      author: const Profile(id: 'U-other'),
    );
    final harness = await _buildHarness(
      involvement: _involvement(otherAuthorBeacon),
      candidates: [_profile(id: 'U-alice', name: 'Alice')],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice'},
        skippedPersonalNoteIds: {'U-alice'},
        beacon: otherAuthorBeacon,
      ),
    );

    await cubit.forward();

    final message = effects.emitted.whereType<ShowMessage>().single.message;
    expect(message, isA<ForwardLocationMessage>());
    expect(
      (message as ForwardLocationMessage).toEn,
      'Request forwarded. It\'s in Watching.',
    );
  });

  test('help offer uses my work location without action', () async {
    final effects = FakeUiEffectPort();
    final beacon = _openBeacon();
    final harness = await _buildHarness(
      involvement: (
        beacon: beacon,
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{'U-me'},
        withdrawnIds: <String>{},
        rejectedIds: <String>{},
        watchingIds: <String>{},
        onwardForwarderIds: <String>{},
        myForwardedRecipientNotes: <String, String>{},
        myForwardedRecipientEdgeIds: <String, String>{},
        myForwardedRecipientReadAts: <String, DateTime?>{},
        myForwardedRecipientHasOnwardChild: <String, bool>{},
        myForwardedRecipientRejected: <String, bool>{},
      ),
      candidates: [_profile(id: 'U-alice', name: 'Alice')],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice'},
        skippedPersonalNoteIds: {'U-alice'},
        beacon: beacon,
      ),
    );

    await cubit.forward();

    final message = effects.emitted.whereType<ShowMessage>().single.message;
    expect(message, isA<ForwardLocationMyWorkMessage>());
    expect(message, isNot(isA<ForwardLocationMessage>()));
  });

  test('many skipped with one delivered uses location pause count copy', () async {
    final effects = FakeUiEffectPort();
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(id: 'U-alice', name: 'Alice'),
        _profile(
          id: 'U-bob',
          name: 'Bob',
          availability: Availability(resumeOn: pausedUntil),
        ),
        _profile(
          id: 'U-carol',
          name: 'Carol',
          availability: Availability(resumeOn: pausedUntil),
        ),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: effects,
      clock: clock,
      initialSelectedIds: {'U-bob', 'U-carol'},
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice'},
        skippedPersonalNoteIds: {'U-alice'},
        beacon: _openBeacon(),
      ),
    );

    await cubit.forward();

    expect(
      effects.emitted.whereType<ShowMessage>().single.message,
      isA<ForwardLocationMyWorkMessage>(),
    );
    expect(
      (effects.emitted.whereType<ShowMessage>().single.message
              as ForwardLocationMyWorkMessage)
          .toEn,
      'Request forwarded. It\'s in My Work. — 2 people aren\'t taking new requests right now.',
    );
    expect(harness.forwardRepo.lastRecipientIds, ['U-alice']);
  });

  test('own forward does not reload from repository change stream', () async {
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [_profile(id: 'U-alice', name: 'Alice')],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      clock: clock,
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    final callsBefore = harness.forwardRepo.fetchCandidatesCalls;
    cubit.emit(
      cubit.state.copyWith(
        selectedIds: {'U-alice'},
        beacon: _openBeacon(),
      ),
    );
    await cubit.forward();
    await Future<void>.delayed(Duration.zero);

    expect(harness.forwardRepo.fetchCandidatesCalls, callsBefore);
  });

  test('expiry timer reloads candidates at UTC resume boundary', () async {
    clockNow = DateTime.utc(2026, 8, 19, 23, 30);
    final resumeOn = DateTime.utc(2026, 8, 20);
    Timer? scheduledTimer;
    void Function()? timerCallback;
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(
          id: 'U-paused',
          name: 'Carol',
          availability: Availability(resumeOn: resumeOn),
        ),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      clock: clock,
      timerFactory: (duration, onFire) {
        timerCallback = onFire;
        scheduledTimer = Timer(duration, onFire);
        return scheduledTimer!;
      },
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    final callsBefore = harness.forwardRepo.fetchCandidatesCalls;
    timerCallback!();
    await cubit.stream.firstWhere(
      (s) => harness.forwardRepo.fetchCandidatesCalls > callsBefore,
    );
    expect(harness.forwardRepo.fetchCandidatesCalls, callsBefore + 1);
  });

  test('app lifecycle resume triggers availability reevaluation', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    VoidCallback? resumeHandler;
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [_profile(id: 'U-alice', name: 'Alice')],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      clock: clock,
      lifecycleListenerFactory: ({VoidCallback? onResume}) {
        resumeHandler = onResume;
        return AppLifecycleListener(onResume: onResume);
      },
    );
    addTearDown(cubit.close);
    await _waitReady(cubit);

    final callsBefore = harness.forwardRepo.fetchCandidatesCalls;
    resumeHandler!.call();
    await cubit.stream.firstWhere(
      (s) => harness.forwardRepo.fetchCandidatesCalls > callsBefore,
    );
    expect(harness.forwardRepo.fetchCandidatesCalls, callsBefore + 1);
  });

  test('close cancels expiry timer', () async {
    Timer? scheduledTimer;
    final harness = await _buildHarness(
      involvement: _involvement(_openBeacon()),
      candidates: [
        _profile(
          id: 'U-paused',
          name: 'Carol',
          availability: Availability(resumeOn: pausedUntil),
        ),
      ],
    );
    addTearDown(() => _disposeHarness(harness));

    final cubit = _cubit(
      forwardCase: harness.forwardCase,
      effects: FakeUiEffectPort(),
      clock: clock,
      timerFactory: (duration, onFire) {
        scheduledTimer = Timer(duration, onFire);
        return scheduledTimer!;
      },
    );
    await _waitReady(cubit);
    await cubit.close();

    expect(scheduledTimer!.isActive, isFalse);
  });
}
