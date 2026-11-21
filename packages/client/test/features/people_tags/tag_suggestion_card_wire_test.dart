import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_suggestion_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/remote_wire_harness.dart';

void main() {
  testWidgets(
    'the tag suggestion card shows and records dismissal using only its repository',
    (tester) async {
      final sent = <WireSent>[];
      await withRemoteWire(
        const {
          'PersonTagSuggestionState': {
            '__typename': 'query_root',
            'personTagSuggestionState': {
              '__typename': 'v2_PersonTagSuggestionState',
              'canSuggest': true,
              'disabled': false,
              'silencedUntil': null,
            },
          },
          'PersonTagSuggestionRecord': {
            '__typename': 'mutation_root',
            'personTagSuggestionRecord': {
              '__typename': 'v2_PersonTagSuggestionState',
              'canSuggest': false,
              'disabled': false,
              'silencedUntil': '2026-11-22T12:00:00Z',
            },
          },
        },
        sent,
        (remote) async {
          final repository = PeopleTagsRepository(remote);
          late final PeopleTagSuggestionCase suggestions;
          expect(
            () => suggestions =
                Function.apply(PeopleTagSuggestionCase.new, [
                      repository,
                    ])
                    as PeopleTagSuggestionCase,
            returnsNormally,
            reason: 'PeopleTagSuggestionCase must accept just its repository',
          );
          final rig = await PeopleTagsTestRig.create(
            FakePeopleTagsRepository(),
          );
          addTearDown(rig.dispose);
          GetIt.I
            ..registerSingleton<PeopleTagsCase>(rig.peopleTags)
            ..registerSingleton<PeopleTagSuggestionCase>(suggestions);
          addTearDown(GetIt.I.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: TenturaTheme.light(),
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: TagSuggestionCard(
                  event: PeopleTagSuggestionEvent.closure('Bclosure00001'),
                  personIds: const ['Uann00000001'],
                  names: 'Ann',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final title = find.text('Tag Ann?');
          expect(title, findsOneWidget);
          expect(sent.map((call) => call.operationName), [
            'PersonTagSuggestionState',
          ]);

          await tester.tap(
            find.byKey(const ValueKey('tag-suggestion-not-now')),
          );
          await tester.pumpAndSettle();

          expect(title, findsNothing);
          expect(sent.map((call) => call.operationName), [
            'PersonTagSuggestionState',
            'PersonTagSuggestionRecord',
          ]);
          expect(sent.last.variables['outcome'], 'skipped');
          expect(sent.last.variables['clientOpId'], isNotEmpty);
        },
      );
    },
  );
}
