import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../../support/test_realtime_sync.dart';
import '../auth/auth_test_helpers.dart';
import '../block/support/controllable_block_case.dart';
import '../contacts/contacts_case_test.dart';

class _OfferHelpRepository implements ForwardRepository {
  final calls =
      <
        ({
          String beaconId,
          String? message,
          List<String>? helpTypes,
          int? expectedOfferKind,
          bool notifyHelpOfferListeners,
        })
      >[];
  Future<bool> Function() response = () async => true;

  @override
  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    int? expectedOfferKind,
    bool notifyHelpOfferListeners = true,
  }) {
    calls.add((
      beaconId: beaconId,
      message: message,
      helpTypes: helpTypes,
      expectedOfferKind: expectedOfferKind,
      notifyHelpOfferListeners: notifyHelpOfferListeners,
    ));
    return response();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedFactCards implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedProfiles implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ForwardCase help offer delegation', () {
    late _OfferHelpRepository repository;
    late ForwardCase forwardCase;

    setUp(() {
      repository = _OfferHelpRepository();
      final authLocal = EmptyAuthLocal();
      final store = ContactNameStore();
      final realtime = buildTestRealtimeSync();
      final contactsCase = ContactsCase(
        FakeContactsRepository(),
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        store,
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      addTearDown(() async {
        await contactsCase.dispose();
        await realtime.port.dispose();
        await store.dispose();
      });
      forwardCase = ForwardCase(
        repository,
        authLocal,
        _UnusedFactCards(),
        _UnusedProfiles(),
        contactsCase,
        noopBlockCase(),
        env: const Env(),
        logger: Logger('test'),
      );
    });

    // Dynamic invocation keeps the tests executable before the method exists,
    // so the baseline fails on the missing behavior rather than failing to load.
    Future<bool> offerHelp({
      required String beaconId,
      String? message,
      List<String>? helpTypes,
      int? expectedOfferKind,
    }) async =>
        await (forwardCase as dynamic).offerHelp(
              beaconId: beaconId,
              message: message,
              helpTypes: helpTypes,
              expectedOfferKind: expectedOfferKind,
            )
            as bool;

    test(
      'forwards offer details once and returns repository success',
      () async {
        final helpTypes = ['transport', 'translation'];

        expect(
          await offerHelp(
            beaconId: 'request-a',
            message: 'I can help tomorrow',
            helpTypes: helpTypes,
            expectedOfferKind: 2,
          ),
          isTrue,
        );
        expect(repository.calls, hasLength(1));
      final call = repository.calls.single;
      expect(call.beaconId, 'request-a');
      expect(call.message, 'I can help tomorrow');
      expect(call.helpTypes, orderedEquals(helpTypes));
      expect(call.expectedOfferKind, 2);
      expect(call.notifyHelpOfferListeners, isTrue);
      },
    );

    test(
      'accepts omitted optional details and retains notification default',
      () async {
        expect(
          await (forwardCase as dynamic).offerHelp(beaconId: 'request-b'),
          isTrue,
        );
        expect(repository.calls, hasLength(1));
        expect(repository.calls.single, (
          beaconId: 'request-b',
          message: null,
          helpTypes: null,
          expectedOfferKind: null,
          notifyHelpOfferListeners: true,
        ));
      },
    );

    test('returns repository rejection without retrying', () async {
      repository.response = () async => false;

      expect(await offerHelp(beaconId: 'request-a'), isFalse);
      expect(repository.calls, hasLength(1));
    });

    test(
      'propagates the original repository failure without retrying',
      () async {
        final failure = StateError('offer kind changed');
        repository.response = () async => throw failure;

        await expectLater(
          offerHelp(beaconId: 'request-a', expectedOfferKind: 2),
          throwsA(same(failure)),
        );
        expect(repository.calls, hasLength(1));
      },
    );

    test('waits for the repository before completing the offer', () async {
      final gate = Completer<bool>();
      repository.response = () => gate.future;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete(false);
      });
      var completed = false;
      final result = offerHelp(beaconId: 'request-a').then((value) {
        completed = true;
        return value;
      });
      final expectation = expectLater(result, completion(isTrue));

      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, hasLength(1));
      expect(completed, isFalse);
      gate.complete(true);
      await expectation;
    });
  });
}
