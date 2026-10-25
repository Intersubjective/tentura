import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../support/test_realtime_sync.dart';

/// Logs every call; calls other than suggestion, tag-create and membership
/// reads fail loudly.
final class _FakeRepository implements PeopleTagsRepositoryPort {
  PersonTagSuggestionState state = const PersonTagSuggestionState(
    canSuggest: true,
    disabled: false,
  );

  int stateCalls = 0;
  final recorded = <String>[];
  final calls = <String>[];
  List<PersonTagMembers> memberList = [];
  List<String> participantsOfBeacon = [];
  final createdFromBeacon = <String?>[];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async {
    stateCalls++;
    calls.add('state');
    return state;
  }

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    recorded.add(outcome);
    calls.add('record:$outcome');
    return state;
  }

  @override
  Future<PersonTag> personTagCreate({
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,
    int? fromAutoKind,
    String? fromBeaconId,
  }) async {
    createdFromBeacon.add(fromBeaconId);
    calls.add('create');
    if (fromBeaconId != null) {
      memberList = [
        ...memberList,
        PersonTagMembers(tagId: 'Tnew', personIds: participantsOfBeacon),
      ];
    }
    return PersonTag(id: 'Tnew', name: name, glyph: 'N', color: 0, ord: 0);
  }

  @override
  Future<List<PersonTag>> personTags() async => const [];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async {
    calls.add('memberships');
    return memberList;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeRepository repository;
  late PeopleTagSuggestionCase suggestions;

  setUp(() {
    repository = _FakeRepository();
    suggestions = PeopleTagSuggestionCase(
      repository,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  group('"Tag them?" suggestion card', () {
    test('is shown for an event when the server allows suggestions', () async {
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('B1')),
        isTrue,
      );
    });

    test('is shown only once per event', () async {
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('B1')),
        isTrue,
      );
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('B1')),
        isFalse,
      );
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('B2')),
        isTrue,
      );
    });

    test('is not shown when the server says canSuggest is false', () async {
      repository.state = const PersonTagSuggestionState(
        canSuggest: false,
        disabled: false,
      );
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('B1')),
        isFalse,
      );
    });

    test('is shown once per event for every placement', () async {
      final events = {
        'closure': PeopleTagSuggestionEvent.closure,
        'accepted help': PeopleTagSuggestionEvent.acceptedHelp,
        'forward sent': PeopleTagSuggestionEvent.forwardSent,
        'new mutual trust': PeopleTagSuggestionEvent.mutualTrust,
      };
      for (final make in events.values) {
        expect(await suggestions.shouldShow(make('X1')), isTrue);
        expect(await suggestions.shouldShow(make('X1')), isFalse);
        expect(await suggestions.shouldShow(make('X2')), isTrue);
      }
    });

    test('placements do not silence each other for the same id', () async {
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('X1')),
        isTrue,
      );
      expect(
        await suggestions.shouldShow(
          PeopleTagSuggestionEvent.mutualTrust('X1'),
        ),
        isTrue,
      );
    });

    test('a full suggestion flow only talks to the tag repository', () async {
      final event = PeopleTagSuggestionEvent.acceptedHelp('O1');
      expect(await suggestions.shouldShow(event), isTrue);
      await suggestions.notNow(event);
      await suggestions.accepted(PeopleTagSuggestionEvent.closure('B1'));
      await suggestions.disable();
      expect(
        repository.calls,
        everyElement(
          anyOf('state', startsWith('record:')),
        ),
      );
    });

    test('Not now records skipped', () async {
      await suggestions.notNow(PeopleTagSuggestionEvent.closure('B1'));
      expect(repository.recorded, ['skipped']);
    });

    test('shows no card after the server state silences suggestions', () async {
      expect(
        await suggestions.shouldShow(
          PeopleTagSuggestionEvent.forwardSent('M1'),
        ),
        isTrue,
      );
      await suggestions.notNow(PeopleTagSuggestionEvent.forwardSent('M1'));
      repository.state = PersonTagSuggestionState(
        canSuggest: false,
        disabled: false,
        silencedUntil: DateTime.now().add(const Duration(days: 30)),
      );
      expect(
        await suggestions.shouldShow(
          PeopleTagSuggestionEvent.forwardSent('M2'),
        ),
        isFalse,
      );
    });

    test('records accepted and disabled outcomes', () async {
      await suggestions.accepted(PeopleTagSuggestionEvent.closure('B1'));
      await suggestions.disable();
      expect(repository.recorded, ['accepted', 'disabled']);
    });
  });

  group('"Tag from participants" on a Request', () {
    late PeopleTagsCase tags;

    setUp(() {
      final realtime = buildTestRealtimeSync();
      tags = PeopleTagsCase(
        repository,
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
    });

    test('is offered only to a member of a Request', () {
      bool offered({required bool member, required bool request}) =>
          tags.canTagFromParticipants(
            viewerIsMember: member,
            isRequest: request,
          );
      expect(offered(member: true, request: true), isTrue);
      expect(offered(member: false, request: true), isFalse);
    });

    test('is not offered on a Post even to a member', () {
      expect(
        tags.canTagFromParticipants(viewerIsMember: true, isRequest: false),
        isFalse,
      );
      expect(
        tags.canTagFromParticipants(viewerIsMember: false, isRequest: false),
        isFalse,
      );
    });

    test('creates the tag from the Request participants', () async {
      final tag = await tags.createTag(name: 'Crew', fromBeaconId: 'B1');
      expect(tag.name, 'Crew');
      expect(repository.createdFromBeacon, ['B1']);
    });

    test('puts the Request participants into the new tag', () async {
      repository.participantsOfBeacon = ['Uann', 'Ubob'];
      final tag = await tags.createTag(name: 'Crew', fromBeaconId: 'B1');
      expect(tags.peopleInTag(tag.id), {'Uann', 'Ubob'});
    });
  });
}
