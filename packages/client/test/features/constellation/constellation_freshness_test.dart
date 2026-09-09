import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_snapshot_bar.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 8, 12, 30);

Beacon _beacon({
  required String id,
  BeaconStatus status = BeaconStatus.open,
}) {
  final now = DateTime.utc(2026, 9, 8);
  return Beacon(
    id: id,
    title: 'Need ride',
    createdAt: now,
    updatedAt: now,
    author: const Profile(id: 'author', displayName: 'Author'),
    status: status,
  );
}

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

ConstellationField _fieldForRequest(ConstellationRequest request) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      requests: [request],
      peers: [
        ConstellationPerson(
          id: request.authorId,
          displayName: 'Author',
        ),
      ],
    );

ConstellationRequest _request({
  required String id,
  int status = 0,
}) => ConstellationRequest(
  id: id,
  authorId: 'author',
  title: 'Need ride',
  status: status,
);

class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository({
    this.involvementByBeaconId = const {},
    this.involvementErrorByBeaconId = const {},
    this.offerHelpError,
    this.offerHelpResult = true,
  });

  final Map<String, BeaconInvolvementData> involvementByBeaconId;
  final Map<String, Object> involvementErrorByBeaconId;
  final Object? offerHelpError;
  final bool offerHelpResult;

  int? lastExpectedOfferKind;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async {
    final error = involvementErrorByBeaconId[beaconId];
    if (error != null) {
      throw error;
    }
    final involvement = involvementByBeaconId[beaconId];
    if (involvement == null) {
      throw StateError('missing involvement for $beaconId');
    }
    return involvement;
  }

  @override
  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    int? expectedOfferKind,
    bool notifyHelpOfferListeners = true,
  }) async {
    lastExpectedOfferKind = expectedOfferKind;
    if (offerHelpError != null) {
      throw offerHelpError!;
    }
    return offerHelpResult;
  }

  @override
  Stream<String> get forwardChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ConstellationCubit> _cubitWithField(
  ConstellationField field, {
  ForwardRepository? forwardRepository,
}) async {
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      _StubConstellationRepository(field),
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationFreshnessTest'),
    ),
    viewer: _ego,
    forwardRepository: forwardRepository ?? _FakeForwardRepository(),
    loadOnCreate: false,
  );
  await cubit.load();
  return cubit;
}

void main() {
  group('Constellation snapshot freshness', () {
    testWidgets('view mode switch does not change Loaded at timestamp', (
      tester,
    ) async {
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: const Scaffold(body: ConstellationSnapshotBar()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Loaded at'), findsOneWidget);
      final before = tester.widget<Text>(
        find.byKey(const Key('constellation.snapshot.loaded_at')),
      ).data;

      await tester.tap(find.text('Text'));
      await tester.pumpAndSettle();
      expect(cubit.state.viewMode, ConstellationViewMode.text);
      expect(cubit.state.loadedAt, _loadedAt);

      final after = tester.widget<Text>(
        find.byKey(const Key('constellation.snapshot.loaded_at')),
      ).data;
      expect(after, before);
    });

    test('selected-request refresh keeps field loadedAt unchanged', () async {
      final forwardRepo = _FakeForwardRepository(
        involvementByBeaconId: {
          'B1': _involvement(
            _beacon(id: 'B1', status: BeaconStatus.enoughHelp),
          ),
        },
      );
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1', status: 0)),
        forwardRepository: forwardRepo,
      );

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightReady>());
      expect(cubit.state.loadedAt, _loadedAt);
      expect(
        cubit.requestById('B1')?.status,
        BeaconStatus.enoughHelp.smallintValue,
      );
    });

    test('vanished request preflight explains instead of throwing', () async {
      final forwardRepo = _FakeForwardRepository(
        involvementErrorByBeaconId: {
          'B1': const BeaconFetchException('B1'),
        },
      );
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
        forwardRepository: forwardRepo,
      );

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightUnavailable>());
      expect(
        (preflight as ConstellationRequestPreflightUnavailable).message,
        contains('no longer available'),
      );
    });

    test('opted-out but still readable request is not refused client-side', () async {
      final forwardRepo = _FakeForwardRepository(
        involvementByBeaconId: {
          'B1': _involvement(_beacon(id: 'B1')),
        },
      );
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
        forwardRepository: forwardRepo,
      );

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightReady>());
    });

    test('offerKindChanged preserves draft and can be retried', () async {
      final forwardRepo = _FakeForwardRepository(
        involvementByBeaconId: {
          'B1': _involvement(_beacon(id: 'B1', status: BeaconStatus.open)),
        },
        offerHelpError: Exception('coordination code 1516'),
      );
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1', status: 0)),
        forwardRepository: forwardRepo,
      );

      final outcome = await cubit.submitValidatedOfferHelp(
        beaconId: 'B1',
        expectedOfferKind: 0,
        message: 'draft note',
      );
      expect(outcome, ConstellationOfferSubmitOutcome.offerKindChanged);
      expect(forwardRepo.lastExpectedOfferKind, 0);
    });

    test('authorization denied when request is closed', () async {
      final forwardRepo = _FakeForwardRepository(
        involvementByBeaconId: {
          'B1': _involvement(_beacon(id: 'B1', status: BeaconStatus.cancelled)),
        },
      );
      final cubit = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
        forwardRepository: forwardRepo,
      );

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightAuthorizationDenied>());
    });
  });
}

final class _StubConstellationRepository implements ConstellationRepositoryPort {
  _StubConstellationRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch() async => field;
}
