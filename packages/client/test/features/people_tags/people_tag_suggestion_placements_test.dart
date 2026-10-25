import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_from_participants_button.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_suggestion_card.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _tagA = PersonTag(id: 'Ta', name: 'Crew', glyph: 'C', color: 0, ord: 0);

/// Counts calls on the attention surface; nothing in a suggestion flow may
/// reach it.
final class _RecordingAttention implements AttentionReconcilePort {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return null;
  }
}

final class _FakeRepository implements PeopleTagsRepositoryPort {
  PersonTagSuggestionState state = const PersonTagSuggestionState(
    canSuggest: true,
    disabled: false,
  );
  final recorded = <String>[];
  final appliedOps = <List<PersonTagMemberOp>>[];
  final createdFromBeacon = <String?>[];
  List<PersonTagMembers> memberList = [];
  List<String> participants = ['Uann', 'Ubob'];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async => state;

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    recorded.add(outcome);
    return state;
  }

  @override
  Future<List<PersonTag>> personTags() async => const [_tagA];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => memberList;

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) async => appliedOps.add(ops);

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
    memberList = [
      ...memberList,
      PersonTagMembers(tagId: 'Tnew', personIds: participants),
    ];
    return PersonTag(id: 'Tnew', name: name, glyph: 'N', color: 0, ord: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('who a "Tag them?" suggestion offers', () {
    test('closure offers the author the members who have no own tag', () {
      expect(
        PeopleTagSuggestionPlacements.closureCandidates(
          viewerId: 'Uauthor',
          authorId: 'Uauthor',
          memberIds: ['Uauthor', 'Uann', 'Ubob'],
          taggedIds: {'Ubob'},
        ),
        ['Uann'],
      );
    });

    test('closure offers nobody to a member who is not the author', () {
      expect(
        PeopleTagSuggestionPlacements.closureCandidates(
          viewerId: 'Uann',
          authorId: 'Uauthor',
          memberIds: ['Uauthor', 'Uann'],
          taggedIds: {},
        ),
        isEmpty,
      );
    });

    test('accepted help offers the helper to the author only', () {
      expect(
        PeopleTagSuggestionPlacements.acceptedHelpCandidate(
          viewerIsAuthor: true,
          helperId: 'Uann',
          taggedIds: {},
        ),
        'Uann',
      );
      expect(
        PeopleTagSuggestionPlacements.acceptedHelpCandidate(
          viewerIsAuthor: false,
          helperId: 'Uann',
          taggedIds: {},
        ),
        isNull,
      );
      expect(
        PeopleTagSuggestionPlacements.acceptedHelpCandidate(
          viewerIsAuthor: true,
          helperId: 'Uann',
          taggedIds: {'Uann'},
        ),
        isNull,
      );
    });

    test('a forward offers its recipients only from two recipients up', () {
      expect(
        PeopleTagSuggestionPlacements.forwardCandidates(['Uann']),
        isEmpty,
      );
      expect(
        PeopleTagSuggestionPlacements.forwardCandidates(['Uann', 'Ubob']),
        ['Uann', 'Ubob'],
      );
    });

    test(
      'mutual trust offers the person only when it has just become mutual',
      () {
        String? offer({required bool was, required bool isNow}) =>
            PeopleTagSuggestionPlacements.mutualTrustCandidate(
              personId: 'Uann',
              wasMutual: was,
              isMutual: isNow,
              taggedIds: {},
            );
        expect(offer(was: false, isNow: true), 'Uann');
        expect(offer(was: true, isNow: true), isNull);
        expect(offer(was: false, isNow: false), isNull);
      },
    );
  });

  group('suggestion card and Tag from participants widgets', () {
    late _FakeRepository repository;
    late _RecordingAttention attention;
    late FakeUiEffectPort effects;
    late TestRealtimeSyncPort realtimePort;
    late PeopleTagsCase peopleTags;

    setUp(() async {
      repository = _FakeRepository();
      attention = _RecordingAttention();
      effects = FakeUiEffectPort();
      final realtime = buildTestRealtimeSync();
      realtimePort = realtime.port;
      peopleTags = PeopleTagsCase(
        repository,
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );
      await peopleTags.load();
      GetIt.I
        ..registerSingleton<PeopleTagsCase>(peopleTags)
        ..registerSingleton<PeopleTagSuggestionCase>(
          PeopleTagSuggestionCase(
            repository,
            env: const Env(),
            logger: Logger('test'),
          ),
        )
        ..registerSingleton<AttentionReconcilePort>(attention)
        ..registerSingleton<UiEffectPort>(effects);
    });

    tearDown(() async {
      await GetIt.I.reset();
      await peopleTags.dispose();
      await realtimePort.dispose();
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    const cardKey = ValueKey('tag-suggestion-card');
    const notNowKey = ValueKey('tag-suggestion-not-now');
    const addKey = ValueKey('tag-suggestion-add');

    TagSuggestionCard card(String id) => TagSuggestionCard(
      event: PeopleTagSuggestionEvent.closure(id),
      personIds: const ['Uann', 'Ubob'],
    );

    testWidgets('the card is shown when suggestions are allowed', (
      tester,
    ) async {
      await pump(tester, card('B1'));
      expect(find.byKey(cardKey), findsOneWidget);
    });

    testWidgets('the card is hidden when the server forbids suggestions', (
      tester,
    ) async {
      repository.state = const PersonTagSuggestionState(
        canSuggest: false,
        disabled: false,
      );
      await pump(tester, card('B1'));
      expect(find.byKey(cardKey), findsNothing);
    });

    testWidgets('the same event does not show a second card', (tester) async {
      await pump(tester, Column(children: [card('B1'), card('B1')]));
      expect(find.byKey(cardKey), findsOneWidget);
    });

    testWidgets('Not now records skipped and removes the card', (tester) async {
      await pump(tester, card('B1'));
      await tester.tap(find.byKey(notNowKey));
      await tester.pumpAndSettle();
      expect(repository.recorded, ['skipped']);
      expect(find.byKey(cardKey), findsNothing);
    });

    testWidgets('adding to a picked tag records accepted', (tester) async {
      await pump(tester, card('B1'));
      await tester.tap(find.text('Crew'));
      await tester.pump();
      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();
      expect(repository.recorded, ['accepted']);
      expect(
        repository.appliedOps.single.map((o) => (o.tagId, o.personId, o.add)),
        unorderedEquals([('Ta', 'Uann', true), ('Ta', 'Ubob', true)]),
      );
    });

    testWidgets('a suggestion flow never touches attention or UI effects', (
      tester,
    ) async {
      await pump(tester, card('B1'));
      await tester.tap(find.byKey(notNowKey));
      await tester.pumpAndSettle();
      await pump(tester, card('B2'));
      await tester.tap(find.text('Crew'));
      await tester.pump();
      await tester.tap(find.byKey(addKey));
      await tester.pumpAndSettle();
      expect(attention.calls, 0);
      expect(effects.emitted, isEmpty);
    });

    const buttonKey = ValueKey('tag-from-participants');
    const nameField = ValueKey('tag-editor-name');
    const saveButton = ValueKey('tag-editor-save');

    testWidgets('Tag from participants is offered to a member of a Request', (
      tester,
    ) async {
      await pump(
        tester,
        const TagFromParticipantsButton(
          beaconId: 'B1',
          isRequest: true,
          viewerIsMember: true,
        ),
      );
      expect(find.byKey(buttonKey), findsOneWidget);
    });

    for (final (request, member) in [
      (true, false),
      (false, true),
      (false, false),
    ]) {
      testWidgets(
        'Tag from participants is hidden for request=$request member=$member',
        (tester) async {
          await pump(
            tester,
            TagFromParticipantsButton(
              beaconId: 'B1',
              isRequest: request,
              viewerIsMember: member,
            ),
          );
          expect(find.byKey(buttonKey), findsNothing);
        },
      );
    }

    testWidgets('using Tag from participants creates a tag from that Request', (
      tester,
    ) async {
      await pump(
        tester,
        const TagFromParticipantsButton(
          beaconId: 'B1',
          isRequest: true,
          viewerIsMember: true,
        ),
      );
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(nameField), 'Crew2');
      await tester.pump();
      await tester.tap(find.byKey(saveButton));
      await tester.pumpAndSettle();

      expect(repository.createdFromBeacon, ['B1']);
      expect(peopleTags.peopleInTag('Tnew'), {'Uann', 'Ubob'});
      expect(attention.calls, 0);
      expect(effects.emitted, isEmpty);
    });
  });
}
