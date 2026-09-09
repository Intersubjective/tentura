import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 9, 8, 12, 30);

ConstellationField _fieldForRequests(List<ConstellationRequest> requests) =>
    ConstellationField(
      loadedAt: _loadedAt,
      context: '',
      requests: requests,
      peers: [
        for (final request in requests)
          ConstellationPerson(id: request.authorId, displayName: 'Author'),
      ],
    );

ConstellationField _fieldForRequest(ConstellationRequest request) =>
    _fieldForRequests([request]);

ConstellationRequest _request({
  required String id,
  int status = 0,
}) => ConstellationRequest(
  id: id,
  authorId: 'author',
  title: 'Need ride',
  status: status,
);

// The preflight refresh (`ConstellationCubit.preflightRequestAction`) must
// stay on this content-wall-gated `_case.load()` path (never an
// involvement-gated one — see the cubit's doc comment on that method), so
// these tests simulate a server-side change between the initial field load
// and the preflight refresh by mutating what this stub's `fetch()` returns.
final class _StubConstellationRepository implements ConstellationRepositoryPort {
  _StubConstellationRepository(this.field);

  ConstellationField field;

  @override
  Future<ConstellationField> fetch() async => field;
}

class _FakeForwardRepository implements ForwardRepository {
  _FakeForwardRepository({
    this.offerHelpError,
    this.offerHelpResult = true,
  });

  final Object? offerHelpError;
  final bool offerHelpResult;

  int? lastExpectedOfferKind;

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

Future<(ConstellationCubit, _StubConstellationRepository)> _cubitWithField(
  ConstellationField field, {
  ForwardRepository? forwardRepository,
}) async {
  final repo = _StubConstellationRepository(field);
  final cubit = ConstellationCubit(
    case_: ConstellationFieldCase(
      repo,
      env: const Env.fromEnvironment(),
      logger: Logger('ConstellationFreshnessTest'),
    ),
    viewer: _ego,
    forwardRepository: forwardRepository ?? _FakeForwardRepository(),
    loadOnCreate: false,
  );
  await cubit.load();
  return (cubit, repo);
}

void main() {
  group('Constellation snapshot freshness', () {
    test('setViewMode does not change loadedAt', () async {
      final (cubit, _) = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
      );

      final before = cubit.state.loadedAt;
      cubit.setViewMode(ConstellationViewMode.text);
      expect(cubit.state.viewMode, ConstellationViewMode.text);
      expect(cubit.state.loadedAt, before);
      expect(cubit.state.loadedAt, _loadedAt);

      cubit.setViewMode(ConstellationViewMode.map);
      expect(cubit.state.loadedAt, before);
    });

    test('selected-request refresh keeps field loadedAt unchanged', () async {
      final (cubit, repo) = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1', status: 0)),
      );
      repo.field = _fieldForRequest(
        _request(id: 'B1', status: BeaconStatus.enoughHelp.smallintValue),
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
      final (cubit, repo) = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
      );
      repo.field = _fieldForRequests(const []);

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightUnavailable>());
      expect(
        (preflight as ConstellationRequestPreflightUnavailable).message,
        contains('no longer in the field snapshot'),
      );
    });

    test('opted-out but still readable request is not refused client-side', () async {
      final (cubit, repo) = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
      );
      // Discoverability opting out again does not revoke a read already
      // granted (R7) — the request stays in the content-wall-gated field
      // fetch, so the preflight must still succeed.
      repo.field = _fieldForRequest(_request(id: 'B1'));

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightReady>());
    });

    test('offerKindChanged preserves draft and can be retried', () async {
      final forwardRepo = _FakeForwardRepository(
        offerHelpError: Exception('coordination code 1516'),
      );
      final (cubit, _) = await _cubitWithField(
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
      final (cubit, repo) = await _cubitWithField(
        _fieldForRequest(_request(id: 'B1')),
      );
      repo.field = _fieldForRequest(
        _request(id: 'B1', status: BeaconStatus.cancelled.smallintValue),
      );

      final preflight = await cubit.preflightRequestAction('B1');
      expect(preflight, isA<ConstellationRequestPreflightAuthorizationDenied>());
    });
  });
}
