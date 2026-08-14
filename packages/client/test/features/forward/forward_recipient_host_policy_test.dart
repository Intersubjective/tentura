import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/capability/projection_tier.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/lineage_suggestion_group.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/model/forward_recipient_row_host.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_row.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

final _todayUtc = DateTime.utc(2026, 8, 14);
final _resumeOn = DateTime.utc(2026, 8, 18);
final _resumeBoundary = DateTime.utc(2026, 8, 14);

ForwardCandidate _candidate({
  required String id,
  CandidateInvolvement involvement = CandidateInvolvement.unseen,
  Availability availability = const Availability(),
  bool reachable = true,
  UserPresenceStatus? presenceStatus,
  DateTime? presenceLastSeenAt,
  String? myForwardNote,
}) => ForwardCandidate(
  profile: Profile(
    id: id,
    displayName: id,
    score: reachable ? 10 : 0,
    rScore: reachable ? 1 : 0,
    presenceStatus: presenceStatus,
    presenceLastSeenAt: presenceLastSeenAt,
    availability: availability,
  ),
  involvement: involvement,
  myForwardNote: myForwardNote,
);

ForwardRecipientLine2 _line({
  required ForwardCandidate candidate,
  ForwardRecipientRowHost host = ForwardRecipientRowHost.pickerStandard,
  String? tierEvidenceLabel,
  bool showPresenceLine = true,
  DateTime? todayUtc,
}) {
  final l10n = lookupL10n(const Locale('en'));
  return computeForwardRecipientLine2(
    candidate: candidate,
    host: host,
    todayUtc: todayUtc ?? _todayUtc,
    l10n: l10n,
    locale: const Locale('en'),
    tierEvidenceLabel: tierEvidenceLabel,
    showPresenceLine: showPresenceLine,
  );
}

Future<void> _pumpRecipientRow(
  WidgetTester tester, {
  required ForwardCandidate candidate,
  required bool isSelected,
  required VoidCallback? onToggle,
  DateTime? todayUtc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: BlocProvider<ProfileCubit>.value(
        value: _MockProfileCubit(),
        child: Scaffold(
          body: ForwardRecipientRow(
            host: ForwardRecipientRowHost.pickerStandard,
            candidate: candidate,
            isSelected: isSelected,
            onToggle: onToggle,
            todayUtc: todayUtc ?? _todayUtc,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapRowCheckbox(
  WidgetTester tester,
  String candidateId,
) async {
  final rowBox = tester.getRect(
    find.byKey(TestIds.key(TestIds.forwardRecipient(candidateId))),
  );
  await tester.tapAt(Offset(rowBox.right - 22, rowBox.center.dy));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  group('ForwardRecipientRowHost', () {
    test('lineagePreview does not show availability', () {
      final candidate = _candidate(
        id: 'paused',
        availability: Availability(
          resumeOn: _resumeOn,
        ),
      );
      final line = _line(
        candidate: candidate,
        host: ForwardRecipientRowHost.lineagePreview,
      );
      expect(line.presenceOrAvailabilityUsesStatusText, isFalse);
      expect(line.presenceOrAvailabilityLine, isNull);
      expect(line.relationLabel, isNotNull);
    });

    for (final host in [
      ForwardRecipientRowHost.pickerStandard,
      ForwardRecipientRowHost.pickerLineage,
      ForwardRecipientRowHost.pickerBand,
      ForwardRecipientRowHost.pickerSearch,
    ]) {
      test('$host shows paused availability for unseen', () {
        final line = _line(
          candidate: _candidate(
            id: 'p',
            availability: Availability(resumeOn: _resumeOn),
          ),
          host: host,
        );
        expect(line.presenceOrAvailabilityUsesStatusText, isTrue);
        expect(
          line.presenceOrAvailabilityLine,
          contains('Not taking new requests until'),
        );
        expect(line.relationLabel, isNull);
      });
    }
  });

  group('row precedence', () {
    test('tier evidence replaces full line', () {
      final line = _line(
        candidate: _candidate(id: 'u'),
        tierEvidenceLabel: 'Band evidence',
      );
      expect(line.tierEvidenceLabel, 'Band evidence');
      expect(line.relationLabel, isNull);
      expect(line.presenceOrAvailabilityLine, isNull);
    });

    test('hidden presence suppresses presence but keeps relation', () {
      final line = _line(candidate: _candidate(id: 'u'));
      expect(line.presenceOrAvailabilityLine, isNull);
      expect(line.relationLabel, isNotNull);
    });

    test('not reachable wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          reachable: false,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(line.relationLabel, lookupL10n(const Locale('en')).notReachable);
      expect(line.presenceOrAvailabilityLine, isNull);
    });

    test('author label wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          involvement: CandidateInvolvement.author,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(
        line.relationLabel,
        lookupL10n(const Locale('en')).forwardAuthor,
      );
      expect(line.presenceOrAvailabilityLine, isNull);
    });

    test('declined label wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          involvement: CandidateInvolvement.declined,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(
        line.relationLabel,
        lookupL10n(const Locale('en')).forwardDeclined,
      );
    });

    test('helpOffered label wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          involvement: CandidateInvolvement.helpOffered,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(
        line.relationLabel,
        lookupL10n(const Locale('en')).forwardHelpOffered,
      );
    });

    test('withdrawn label wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          involvement: CandidateInvolvement.withdrawn,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(
        line.relationLabel,
        lookupL10n(const Locale('en')).forwardWithdrawn,
      );
    });

    test('forwardedByMe label wins over pause', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          involvement: CandidateInvolvement.forwardedByMe,
          availability: Availability(resumeOn: _resumeOn),
        ),
      );
      expect(
        line.relationLabel,
        lookupL10n(const Locale('en')).forwardedByMe,
      );
    });

    test('limited replaces presence and keeps relation', () {
      final line = _line(
        candidate: _candidate(
          id: 'u',
          presenceStatus: UserPresenceStatus.online,
          availability: const Availability(isLimited: true),
        ),
      );
      expect(
        line.presenceOrAvailabilityLine,
        lookupL10n(const Locale('en')).availabilityLimitedTitle,
      );
      expect(line.relationLabel, isNotNull);
    });

    test('showPresenceLine false suppresses line (band exploration)', () {
      final line = _line(
        candidate: _candidate(id: 'u'),
        showPresenceLine: false,
      );
      expect(line.suppressed, isTrue);
    });
  });

  group('selection policy', () {
    test('paused unseen cannot be newly selected', () {
      final candidate = _candidate(
        id: 'p',
        availability: Availability(resumeOn: _resumeOn),
      );
      expect(candidate.canForwardToOn(_todayUtc), isFalse);
      expect(
        forwardRecipientCheckboxEnabled(
          candidate: candidate,
          todayUtc: _todayUtc,
          isSelected: false,
        ),
        isFalse,
      );
    });

    test('selected paused row can deselect', () {
      final candidate = _candidate(
        id: 'p',
        availability: Availability(resumeOn: _resumeOn),
      );
      expect(
        forwardRecipientCheckboxEnabled(
          candidate: candidate,
          todayUtc: _todayUtc,
          isSelected: true,
        ),
        isTrue,
      );
    });

    test('open unseen can be selected', () {
      final candidate = _candidate(id: 'o');
      expect(candidate.canForwardToOn(_todayUtc), isTrue);
      expect(
        forwardRecipientCheckboxEnabled(
          candidate: candidate,
          todayUtc: _todayUtc,
          isSelected: false,
        ),
        isTrue,
      );
    });
  });

  group('UTC resume boundary', () {
    final boundaryCandidate = _candidate(
      id: 'boundary',
      availability: Availability(resumeOn: _resumeBoundary),
    );
    final dayBeforeResume = DateTime.utc(2026, 8, 13);

    test('relation tone uses injected todayUtc on resume boundary', () {
      expect(
        forwardRecipientRelationTone(
          boundaryCandidate,
          todayUtc: dayBeforeResume,
        ),
        TenturaTone.neutral,
      );
      expect(
        forwardRecipientRelationTone(
          boundaryCandidate,
          todayUtc: _resumeBoundary,
        ),
        TenturaTone.good,
      );
    });

    test('checkbox policy flips on resume day without using process clock', () {
      expect(
        forwardRecipientCheckboxEnabled(
          candidate: boundaryCandidate,
          todayUtc: dayBeforeResume,
          isSelected: false,
        ),
        isFalse,
      );
      expect(
        forwardRecipientCheckboxEnabled(
          candidate: boundaryCandidate,
          todayUtc: _resumeBoundary,
          isSelected: false,
        ),
        isTrue,
      );
    });

    test('line policy shows pause before resume day and relation after', () {
      final pausedLine = _line(
        candidate: boundaryCandidate,
        todayUtc: dayBeforeResume,
      );
      expect(
        pausedLine.presenceOrAvailabilityLine,
        contains('Not taking new requests until'),
      );
      expect(pausedLine.relationLabel, isNull);

      final resumedLine = _line(
        candidate: boundaryCandidate,
        todayUtc: _resumeBoundary,
      );
      expect(
        resumedLine.presenceOrAvailabilityLine,
        isNot(contains('Not taking new requests until')),
      );
      expect(resumedLine.relationLabel, isNotNull);
      expect(resumedLine.relationTone, TenturaTone.good);
    });
  });

  group('paused row interaction', () {
    const pausedId = 'paused-user';

    testWidgets('selected paused row tap invokes onToggle exactly once', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRecipientRow(
        tester,
        candidate: _candidate(
          id: pausedId,
          availability: Availability(resumeOn: _resumeOn),
        ),
        isSelected: true,
        onToggle: () => taps++,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipient(pausedId))),
      );
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('unselected paused row tap invokes no callback', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRecipientRow(
        tester,
        candidate: _candidate(
          id: pausedId,
          availability: Availability(resumeOn: _resumeOn),
        ),
        isSelected: false,
        onToggle: () => taps++,
      );

      await tester.tap(
        find.byKey(TestIds.key(TestIds.forwardRecipient(pausedId))),
      );
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('unselected paused checkbox tap invokes no callback', (
      tester,
    ) async {
      var taps = 0;
      await _pumpRecipientRow(
        tester,
        candidate: _candidate(
          id: pausedId,
          availability: Availability(resumeOn: _resumeOn),
        ),
        isSelected: false,
        onToggle: () => taps++,
      );

      await _tapRowCheckbox(tester, pausedId);
      await tester.pump();

      expect(taps, 0);
    });
  });

  group('widget hosts', () {
    testWidgets('pickerStandard shows paused label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: BlocProvider<ProfileCubit>.value(
            value: _MockProfileCubit(),
            child: Scaffold(
              body: ForwardRecipientRow(
                host: ForwardRecipientRowHost.pickerStandard,
                candidate: _candidate(
                  id: 'Paused User',
                  availability: Availability(resumeOn: _resumeOn),
                ),
                isSelected: false,
                onToggle: () {},
                todayUtc: _todayUtc,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Not taking new requests until'),
        findsOneWidget,
      );
    });

    testWidgets('lineagePreview hides availability', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: TenturaTheme.light(),
          home: BlocProvider<ProfileCubit>.value(
            value: _MockProfileCubit(),
            child: Scaffold(
              body: ForwardRecipientRow(
                host: ForwardRecipientRowHost.lineagePreview,
                candidate: _candidate(
                  id: 'Paused User',
                  availability: Availability(resumeOn: _resumeOn),
                ),
                isSelected: false,
                onToggle: null,
                todayUtc: _todayUtc,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Not taking new requests until'),
        findsNothing,
      );
    });
  });

  group('ForwardCase band exclusion', () {
    late ContactNameStore store;

    tearDown(() async {
      if (GetIt.I.isRegistered<ContactNameStore>()) {
        await GetIt.I.unregister<ContactNameStore>();
      }
      if (GetIt.I.isRegistered<CapabilityRepositoryPort>()) {
        await GetIt.I.unregister<CapabilityRepositoryPort>();
      }
    });

    test('removes paused candidates preserving band order', () async {
      final band = [
        ForwardBandRow(userId: 'open', rank: 0, rowTier: ProjectionTier.ownOutcome),
        ForwardBandRow(userId: 'paused', rank: 1, rowTier: ProjectionTier.ownOutcome),
        ForwardBandRow(userId: 'ghost', rank: 2, rowTier: ProjectionTier.ownOutcome),
      ];
      final candidates = [
        Profile(
          id: 'open',
          displayName: 'Open',
          score: 10,
          rScore: 1,
        ),
        Profile(
          id: 'paused',
          displayName: 'Paused',
          score: 20,
          rScore: 1,
          availability: Availability(resumeOn: _resumeOn),
        ),
      ];
      final harness = await _buildForwardCaseHarness(
        band: band,
        candidates: candidates,
      );
      store = harness.store;

      final load = await harness.forwardCase.loadForwardCandidates(
        beaconId: 'beacon-1',
      );

      expect(load.band.map((r) => r.userId).toList(), ['open', 'ghost']);
      expect(load.band.map((r) => r.rank).toList(), [0, 2]);
    });
  });
}

class _BandFilterForwardRepository implements ForwardRepository {
  _BandFilterForwardRepository(this.candidates);

  final List<Profile> candidates;
  final _forwardChanges = StreamController<String>.broadcast();

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => candidates;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(id: beaconId),
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
  );

  @override
  Future<LineageForwardSuggestions> fetchLineageForwardSuggestions({
    required String beaconId,
  }) async => const LineageForwardSuggestions(
    sourceBeaconId: '',
    rootBeaconId: '',
    suggestedNote: '',
    suggestions: [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() => _forwardChanges.close();
}

class _FakeCapabilityBandRepo implements CapabilityRepositoryPort {
  _FakeCapabilityBandRepo(this.band);

  final List<ForwardBandRow> band;

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) async => band;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileRepoForBand implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<
  ({
    ForwardCase forwardCase,
    ContactNameStore store,
  })
>
_buildForwardCaseHarness({
  required List<ForwardBandRow> band,
  required List<Profile> candidates,
}) async {
  final authLocal = StreamingAuthLocal('viewer');
  final contactsRepo = FakeContactsRepository();
  final store = ContactNameStore();
  GetIt.I.registerSingleton<ContactNameStore>(store);
  GetIt.I.registerSingleton<CapabilityRepositoryPort>(
    _FakeCapabilityBandRepo(band),
  );
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
  authLocal.emit('viewer');
  await syncReady;
  await Future<void>.delayed(Duration.zero);

  final forwardCase = ForwardCase(
    _BandFilterForwardRepository(candidates),
    authLocal,
    _FakeFactCards(),
    _ProfileRepoForBand(),
    contactsCase,
    noopBlockCase(),
    env: const Env(),
    logger: Logger('test'),
  );
  return (forwardCase: forwardCase, store: store);
}
