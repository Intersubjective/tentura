import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/forward/data/gql/_g/beacon_involvement_data.data.gql.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/candidate_involvement.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import '../auth/auth_test_helpers.dart';
import '../contacts/contacts_case_test.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';

final _beacon = Beacon.empty;

ForwardCandidate _candidateFromInvolvement(
  Profile profile,
  BeaconInvolvementData involvement,
) =>
    ForwardCandidate(
      profile: profile,
      involvement: ForwardCase.computeInvolvement(profile.id, involvement),
      myForwardNote: involvement.myForwardedRecipientNotes[profile.id],
      forwardEdgeId: involvement.myForwardedRecipientEdgeIds[profile.id],
      recipientReadAt: involvement.myForwardedRecipientReadAts[profile.id],
      hasOnwardChild:
          involvement.myForwardedRecipientHasOnwardChild[profile.id] ?? false,
      recipientDeclined:
          involvement.rejectedIds.contains(profile.id) ||
          (involvement.myForwardedRecipientRejected[profile.id] ?? false),
      recipientHasActiveHelpOffer:
          involvement.helpOfferedIds.contains(profile.id),
    );

GBeaconInvolvementDataData_beaconInvolvement _gqlInvolvement(
  void Function(GBeaconInvolvementDataData_beaconInvolvementBuilder b) updates,
) =>
    GBeaconInvolvementDataData_beaconInvolvement(updates);

void main() {
  group('ForwardRepository.mapBeaconInvolvement', () {
    test('maps myForwardedRecipients to notes, edge ids, readAt, and cancel flags',
        () {
      final gql = _gqlInvolvement(
        (b) => b
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'recipient-1'
                ..edgeId = 'edge-abc'
                ..note = 'Please help'
                ..readAt = '2025-06-01T12:00:00.000Z'
                ..hasOnwardChild = true
                ..recipientRejected = true,
            ),
          ]),
      );

      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: gql,
      );

      expect(
        involvement.myForwardedRecipientNotes,
        {'recipient-1': 'Please help'},
      );
      expect(
        involvement.myForwardedRecipientEdgeIds,
        {'recipient-1': 'edge-abc'},
      );
      expect(
        involvement.myForwardedRecipientReadAts['recipient-1'],
        DateTime.utc(2025, 6, 1, 12),
      );
      expect(
        involvement.myForwardedRecipientHasOnwardChild,
        {'recipient-1': true},
      );
      expect(
        involvement.myForwardedRecipientRejected,
        {'recipient-1': true},
      );
    });

    test('null GraphQL lists become empty sets', () {
      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: _gqlInvolvement((_) {}),
      );

      expect(involvement.forwardedToIds, isEmpty);
      expect(involvement.helpOfferedIds, isEmpty);
      expect(involvement.withdrawnIds, isEmpty);
      expect(involvement.rejectedIds, isEmpty);
      expect(involvement.watchingIds, isEmpty);
      expect(involvement.onwardForwarderIds, isEmpty);
      expect(involvement.myForwardedRecipientNotes, isEmpty);
      expect(involvement.myForwardedRecipientHasOnwardChild, isEmpty);
      expect(involvement.myForwardedRecipientRejected, isEmpty);
    });

    test('maps involvement id sets from GraphQL', () {
      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: _gqlInvolvement(
          (b) => b
            ..forwardedToIds = ListBuilder(['fwd'])
            ..helpOfferedIds = ListBuilder(['help'])
            ..withdrawnIds = ListBuilder(['wd'])
            ..rejectedIds = ListBuilder(['rej'])
            ..watchingIds = ListBuilder(['watch'])
            ..onwardForwarderIds = ListBuilder(['onward']),
        ),
      );

      expect(involvement.forwardedToIds, {'fwd'});
      expect(involvement.helpOfferedIds, {'help'});
      expect(involvement.withdrawnIds, {'wd'});
      expect(involvement.rejectedIds, {'rej'});
      expect(involvement.watchingIds, {'watch'});
      expect(involvement.onwardForwarderIds, {'onward'});
    });
  });

  group('GraphQL involvement → ForwardCandidate merge', () {
    test('forwardedByMe recipient carries note and edge id', () {
      const profile = Profile(id: 'recipient-1', displayName: 'R');
      final gql = _gqlInvolvement(
        (b) => b
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'recipient-1'
                ..edgeId = 'edge-1'
                ..note = 'Check this beacon'
                ..hasOnwardChild = false
                ..recipientRejected = false,
            ),
          ]),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'Check this beacon');
      expect(candidate.forwardEdgeId, 'edge-1');
    });

    test('helpOffered id set yields helpOffered candidate', () {
      const profile = Profile(id: 'helper', displayName: 'H');
      final gql = _gqlInvolvement(
        (b) => b..helpOfferedIds = ListBuilder(['helper']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.helpOffered);
      expect(candidate.myForwardNote, isNull);
    });

    test('rejected id set yields declined candidate', () {
      const profile = Profile(id: 'decliner', displayName: 'D');
      final gql = _gqlInvolvement(
        (b) => b..rejectedIds = ListBuilder(['decliner']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.declined);
    });

    test('forwardedToIds yields forwarded candidate', () {
      const profile = Profile(id: 'recipient', displayName: 'R');
      final gql = _gqlInvolvement(
        (b) => b..forwardedToIds = ListBuilder(['recipient']),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwarded);
    });

    test('myForwardedRecipients wins over forwardedToIds for same user', () {
      const profile = Profile(id: 'u1', displayName: 'U');
      final gql = _gqlInvolvement(
        (b) => b
          ..forwardedToIds = ListBuilder(['u1'])
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'u1'
                ..edgeId = 'edge-me'
                ..note = 'From me'
                ..hasOnwardChild = false
                ..recipientRejected = false,
            ),
          ]),
      );

      final candidate = _candidateFromInvolvement(
        profile,
        ForwardRepository.mapBeaconInvolvement(beacon: _beacon, inv: gql),
      );

      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'From me');
    });

    test('parses fixture JSON via fromJson', () {
      final built = _gqlInvolvement(
        (b) => b
          ..watchingIds = ListBuilder(['watcher'])
          ..myForwardedRecipients = ListBuilder([
            GBeaconInvolvementDataData_beaconInvolvement_myForwardedRecipients(
              (r) => r
                ..recipientId = 'watcher'
                ..edgeId = 'edge-w'
                ..note = 'Watching note'
                ..hasOnwardChild = false
                ..recipientRejected = false,
            ),
          ]),
      );
      final json = built.toJson();
      final parsed =
          GBeaconInvolvementDataData_beaconInvolvement.fromJson(json)!;

      final involvement = ForwardRepository.mapBeaconInvolvement(
        beacon: _beacon,
        inv: parsed,
      );
      const profile = Profile(id: 'watcher', displayName: 'W');
      final candidate = _candidateFromInvolvement(profile, involvement);

      // watching beats forwardedToIds, but myForwardedRecipients → forwardedByMe
      expect(candidate.involvement, CandidateInvolvement.forwardedByMe);
      expect(candidate.myForwardNote, 'Watching note');
    });

    test('maps hasOnwardChild from myForwardedRecipientHasOnwardChild', () {
      const profile = Profile(id: 'recipient-1', displayName: 'R');
      final involvement = (
        beacon: _beacon,
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{},
        withdrawnIds: <String>{},
        rejectedIds: <String>{},
        watchingIds: <String>{},
        onwardForwarderIds: <String>{},
        myForwardedRecipientNotes: <String, String>{'recipient-1': 'note'},
        myForwardedRecipientEdgeIds: <String, String>{'recipient-1': 'edge-1'},
        myForwardedRecipientReadAts: <String, DateTime?>{},
        myForwardedRecipientHasOnwardChild: <String, bool>{
          'recipient-1': true,
        },
        myForwardedRecipientRejected: <String, bool>{},
      );

      final candidate = _candidateFromInvolvement(profile, involvement);

      expect(candidate.hasOnwardChild, isTrue);
    });

    test('recipientDeclined from rejectedIds', () {
      const profile = Profile(id: 'decliner', displayName: 'D');
      final involvement = (
        beacon: _beacon,
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{},
        withdrawnIds: <String>{},
        rejectedIds: <String>{'decliner'},
        watchingIds: <String>{},
        onwardForwarderIds: <String>{},
        myForwardedRecipientNotes: <String, String>{},
        myForwardedRecipientEdgeIds: <String, String>{},
        myForwardedRecipientReadAts: <String, DateTime?>{},
        myForwardedRecipientHasOnwardChild: <String, bool>{},
        myForwardedRecipientRejected: <String, bool>{},
      );

      final candidate = _candidateFromInvolvement(profile, involvement);

      expect(candidate.recipientDeclined, isTrue);
    });

    test('recipientDeclined from myForwardedRecipientRejected', () {
      const profile = Profile(id: 'recipient-1', displayName: 'R');
      final involvement = (
        beacon: _beacon,
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{},
        withdrawnIds: <String>{},
        rejectedIds: <String>{},
        watchingIds: <String>{},
        onwardForwarderIds: <String>{},
        myForwardedRecipientNotes: <String, String>{'recipient-1': 'note'},
        myForwardedRecipientEdgeIds: <String, String>{'recipient-1': 'edge-1'},
        myForwardedRecipientReadAts: <String, DateTime?>{},
        myForwardedRecipientHasOnwardChild: <String, bool>{},
        myForwardedRecipientRejected: <String, bool>{'recipient-1': true},
      );

      final candidate = _candidateFromInvolvement(profile, involvement);

      expect(candidate.recipientDeclined, isTrue);
    });

    test('recipientHasActiveHelpOffer from helpOfferedIds', () {
      const profile = Profile(id: 'helper', displayName: 'H');
      final involvement = (
        beacon: _beacon,
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{'helper'},
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

      final candidate = _candidateFromInvolvement(profile, involvement);

      expect(candidate.recipientHasActiveHelpOffer, isTrue);
    });
  });

  group('ForwardCase.loadForwardCandidates viewer flags', () {
    late ContactNameStore store;

    setUp(() {
      store = ContactNameStore();
    });

    tearDown(() async {
      await store.dispose();
    });

    Future<ForwardCase> _caseFor({
      required BeaconInvolvementData involvement,
      required String viewerId,
    }) async {
      final authLocal = StreamingAuthLocal();
      final contactsCase = ContactsCase(
        FakeContactsRepository(),
        buildTestAuthCase(authLocal, EmptyAuthRemote()),
        store,
        buildTestRealtimeSync().case_,
        env: const Env(),
        logger: Logger('test'),
      );
      final forwardCase = ForwardCase(
        _InvolvementForwardRepository(involvement),
        authLocal,
        _FakeBeaconFactCardRepository(),
        _FakeProfileRepository(),
        contactsCase,
        noopBlockCase(),
        env: const Env(),
        logger: Logger('test'),
      );
      authLocal.emit(viewerId);
      await Future<void>.delayed(Duration.zero);
      return forwardCase;
    }

    test('viewerIsAuthor when viewer is beacon author', () async {
      const authorId = 'author-me';
      final involvement = (
        beacon: _beacon.copyWith(author: Profile(id: authorId)),
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
      final forwardCase = await _caseFor(
        involvement: involvement,
        viewerId: authorId,
      );

      final load = await forwardCase.loadForwardCandidates(beaconId: 'b1');

      expect(load.viewerIsAuthor, isTrue);
      expect(load.viewerHasActiveHelpOffer, isFalse);
    });

    test('viewerHasActiveHelpOffer when viewer is in helpOfferedIds', () async {
      const viewerId = 'viewer-help';
      final involvement = (
        beacon: _beacon.copyWith(author: Profile(id: 'author')),
        forwardedToIds: <String>{},
        helpOfferedIds: <String>{viewerId},
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
      final forwardCase = await _caseFor(
        involvement: involvement,
        viewerId: viewerId,
      );

      final load = await forwardCase.loadForwardCandidates(beaconId: 'b1');

      expect(load.viewerIsAuthor, isFalse);
      expect(load.viewerHasActiveHelpOffer, isTrue);
    });
  });
}

class _InvolvementForwardRepository implements ForwardRepository {
  _InvolvementForwardRepository(this.involvement);

  final BeaconInvolvementData involvement;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({String context = ''}) async =>
      const [];

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async =>
      involvement;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBeaconFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository implements ProfileRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
