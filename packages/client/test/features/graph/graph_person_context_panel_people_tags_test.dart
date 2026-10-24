import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/components/person_tag_chip.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura_root/domain/entity/person_auto_tag_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/person_tags_block.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/trust_toggle_line.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _profile = Profile(
  id: 'U-peer',
  displayName: 'Peer',
  score: 1,
  rScore: 1,
);

const _neighbours = PersonTag(
  id: 'Ta',
  name: 'Neighbours',
  glyph: 'N',
  color: 0,
  ord: 0,
);

class _StubContextCubit extends Cubit<GraphPersonContextState>
    implements GraphPersonContextCubit {
  _StubContextCubit() : super(const GraphPersonContextState());

  @override
  Stream<LazyWriteNotice> get lazyWriteNotices => const Stream.empty();

  @override
  Future<void> retryTrust([GraphTrustRevert? revert]) async {}

  @override
  final void Function(Profile profile)? onProfilePatched = null;

  @override
  void selectProfile(Profile profile, {required bool intentional}) {}

  @override
  void dismiss() {}

  @override
  Future<void> trustSelected() async {}

  @override
  Future<void> untrustSelected() async {}

  @override
  void clearSelection() {}
}

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(
      FakePeopleTagsRepository(
        tagList: [_neighbours],
        memberList: const [
          PersonTagMembers(tagId: 'Ta', personIds: ['U-peer']),
        ],
        autoByPerson: {
          'U-peer': [
            PersonAutoTagOf(
              kind: PersonAutoTagKind.mutualContact.smallintValue,
              n: 1,
              direction: 0,
            ),
          ],
        },
      ),
    );
    GetIt.I.registerSingleton<PeopleTagsCase>(rig.peopleTags);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// [peopleTagsEnabled] null leaves the panel's own default (the gate).
  Future<void> pumpPanel(
    WidgetTester tester, {
    bool? peopleTagsEnabled,
  }) async {
    const size = Size(900, 700);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ctx = _StubContextCubit();
    addTearDown(ctx.close);
    const focusedNode = UserNode(user: _profile);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<GraphPersonContextCubit>.value(value: ctx),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(FakeUiEffectPort()),
                ),
              ],
              child: Scaffold(
                body: peopleTagsEnabled == null
                    ? const GraphPersonContextPanel(
                        profile: _profile,
                        focusedNode: focusedNode,
                      )
                    : GraphPersonContextPanel(
                        profile: _profile,
                        focusedNode: focusedNode,
                        peopleTagsEnabled: peopleTagsEnabled,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('person tags in the graph person panel', () {
    testWidgets('shows own tags with × and automatic tags without ×, and '
        'says only the viewer sees tags', (tester) async {
      await pumpPanel(tester, peopleTagsEnabled: true);

      expect(find.text('Your tags'), findsOneWidget);
      expect(find.text('Neighbours'), findsOneWidget);
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Mutual contact'), findsOneWidget);
      expect(find.text('+ Tag'), findsOneWidget);
      expect(find.textContaining('Only you see'), findsOneWidget);
      // One ×: the own tag's. The auto tag has none.
      expect(
        find.descendant(
          of: find.byType(PersonTagsBlock),
          matching: find.byIcon(Icons.close),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AutoTagChip),
          matching: find.byIcon(Icons.close),
        ),
        findsNothing,
      );
    });

    testWidgets('the × removes the tag from the person', (tester) async {
      await pumpPanel(tester, peopleTagsEnabled: true);

      await tester.tap(
        find.descendant(
          of: find.byType(PersonTagChip),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PersonTagChip), findsNothing);
      expect(
        rig.repository.appliedOps.single.map(
          (o) => (o.tagId, o.personId, o.add),
        ),
        [('Ta', 'U-peer', false)],
      );
    });

    testWidgets('sits below the trust toggle and above the actions', (
      tester,
    ) async {
      await pumpPanel(tester, peopleTagsEnabled: true);
      final l10n = lookupL10n(const Locale('en'));

      final blockTop = tester.getTopLeft(find.byType(PersonTagsBlock)).dy;
      final trustBottom = tester.getBottomLeft(find.byType(TrustToggleLine)).dy;
      final actionTop = tester.getTopLeft(find.text(l10n.profile)).dy;
      expect(blockTop, greaterThanOrEqualTo(trustBottom));
      expect(blockTop, lessThan(actionTop));
    });

    testWidgets('is absent when the feature is switched off', (tester) async {
      await pumpPanel(tester, peopleTagsEnabled: false);

      expect(find.byType(PersonTagsBlock), findsNothing);
      expect(find.text('Your tags'), findsNothing);
      expect(find.text('Automatic'), findsNothing);
    });

    testWidgets('is absent by default while the feature gate is off', (
      tester,
    ) async {
      await pumpPanel(tester);

      expect(find.byType(PersonTagsBlock), findsNothing);
      expect(find.text('Your tags'), findsNothing);
    });
  });
}
