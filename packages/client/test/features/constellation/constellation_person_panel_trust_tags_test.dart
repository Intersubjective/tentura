import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/graph_trust_write_fixture.dart';

const _max = Profile(
  id: 'Umax',
  displayName: 'Max',
  myVote: 1,
  subjectExplicitlyTrustsViewer: true,
  isMutualFriend: true,
);

PersonAutoTagOf _tag(PersonAutoTagKind kind) => PersonAutoTagOf(
  kind: kind.smallintValue,
  n: 1,
  direction: 0,
);

final _toggle = find.byKey(TestIds.key(TestIds.graphPersonContextTrust));
final _mutualTag = find.descendant(
  of: find.byType(AutoTagChip),
  matching: find.text('Mutual contact'),
);

/// The same production person panel used by the Field, its real trust writer,
/// profile refresh and tag owner. The selected person never changes.
Future<({GraphTrustWriteFixture trust, FakePeopleTagsRepository tags})>
_openPanel(
  WidgetTester tester, {
  bool mutual = true,
  bool viewerTrusts = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final trust = GraphTrustWriteFixture();
  trust.likes.autoAck = true;
  final profile = _max.copyWith(
    myVote: viewerTrusts ? 1 : 0,
    subjectExplicitlyTrustsViewer: mutual,
    isMutualFriend: mutual && viewerTrusts,
  );
  trust.profiles.byId[_max.id] = profile;
  final tags = FakePeopleTagsRepository(
    autoByPerson: {
      _max.id: [
        if (viewerTrusts) _tag(PersonAutoTagKind.iTrust),
        if (mutual) _tag(PersonAutoTagKind.trustsMe),
        if (mutual && viewerTrusts) _tag(PersonAutoTagKind.mutualContact),
      ],
    },
  );
  final peopleTags = PeopleTagsCase(
    tags,
    RealtimeSyncCase(trust.realtimePort),
    env: const Env(),
    logger: Logger('PersonPanelTrustTagsTest'),
  );
  await peopleTags.load();
  GetIt.I.registerSingleton<PeopleTagsCase>(peopleTags);
  addTearDown(() async {
    await GetIt.I.unregister<PeopleTagsCase>();
    await peopleTags.dispose();
    await trust.dispose();
  });
  final context = trust.createCubit()
    ..selectProfile(profile, intentional: true);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider<GraphPersonContextCubit>.value(value: context),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
          ],
          child: Scaffold(
            body: GraphPersonContextPanel(
              profile: profile,
              focusedNode: UserNode(user: profile),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.widget<Switch>(_toggle).value, viewerTrusts);
  expect(_mutualTag, mutual && viewerTrusts ? findsOneWidget : findsNothing);
  return (trust: trust, tags: tags);
}

void _relationship(GraphTrustWriteFixture trust) =>
    trust.realtimePort.emitChange(
      const RealtimeEntityChange(
        kind: RealtimeEntityKind.relationship,
        aggregateId: 'Ume',
        actorUserId: 'Umax',
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
      ),
    );

void main() {
  group('Field person panel automatic trust tags', () {
    testWidgets('Mutual contact reappears after an own trust-back without '
        'reopening the panel', (tester) async {
      final h = await _openPanel(tester, viewerTrusts: false);
      h.tags.autoByPerson[_max.id] = [
        _tag(PersonAutoTagKind.iTrust),
        _tag(PersonAutoTagKind.trustsMe),
        _tag(PersonAutoTagKind.mutualContact),
      ];

      await tester.tap(_toggle);
      await tester.pumpAndSettle();

      expect(h.trust.likes.amounts, [1]);
      expect(tester.widget<Switch>(_toggle).value, isTrue);
      expect(_mutualTag, findsOneWidget);
    });

    testWidgets('Mutual contact disappears after confirming an own untrust '
        'without reopening the panel', (tester) async {
      final h = await _openPanel(tester);
      h.tags.autoByPerson[_max.id] = [_tag(PersonAutoTagKind.trustsMe)];

      await tester.tap(_toggle);
      await tester.pumpAndSettle();
      final l10n = L10n.of(tester.element(_toggle))!;
      await tester.tap(find.widgetWithText(TextButton, l10n.removeFromMyField));
      await tester.pumpAndSettle();

      expect(h.trust.likes.amounts, [0]);
      expect(tester.widget<Switch>(_toggle).value, isFalse);
      expect(_mutualTag, findsNothing);
    });

    testWidgets('Mutual contact disappears after the selected person remotely '
        'withdraws trust', (tester) async {
      final h = await _openPanel(tester);
      h.tags.autoByPerson[_max.id] = [_tag(PersonAutoTagKind.iTrust)];
      h.trust.profiles.byId[_max.id] = _max.copyWith(
        subjectExplicitlyTrustsViewer: false,
        isMutualFriend: false,
      );

      _relationship(h.trust);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(
        h.trust.contextCubit.state.selectedProfile!.isMutualFriend,
        isFalse,
        reason: 'the profile refresh has already observed the remote untrust',
      );
      expect(tester.widget<Switch>(_toggle).value, isTrue);
      expect(_mutualTag, findsNothing);
    });

    testWidgets('Mutual contact reappears after remote trust-back without '
        'reopening the panel', (tester) async {
      final h = await _openPanel(tester, mutual: false);
      h.tags.autoByPerson[_max.id] = [
        _tag(PersonAutoTagKind.iTrust),
        _tag(PersonAutoTagKind.trustsMe),
        _tag(PersonAutoTagKind.mutualContact),
      ];
      h.trust.profiles.byId[_max.id] = _max;

      _relationship(h.trust);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(
        h.trust.contextCubit.state.selectedProfile!.isMutualFriend,
        isTrue,
        reason: 'the profile refresh has already observed trust-back',
      );
      expect(_mutualTag, findsOneWidget);
    });
  });
}
