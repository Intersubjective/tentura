import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/constellation_people.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/features/graph/domain/use_case/graph_trust_write_case.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

/// #253: the list shows the map's people (not only Request authors), direct
/// contacts first, Posts as secondary rows, and a name search that filters
/// the list; on the map the search selects and centres a person.

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 10, 22, 12);

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

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

/// Viewer trusts Quiet (nothing to show), Olga (one-way: a contact node) and
/// Ann (a Request and a Post); Bob is an indirect author through Ann.
ConstellationField _field() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'quiet', displayName: 'Quiet Ёлкин'),
    ConstellationPerson(
      id: 'olga',
      displayName: 'Olga',
      visible: false,
      contactOnly: true,
    ),
    ConstellationPerson(id: 'ann', displayName: 'Ann', handle: 'annie'),
    ConstellationPerson(id: 'bob', displayName: 'Bob'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'quiet', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'olga', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'ann', tier: 1),
    ConstellationTrustEdgeEntity(src: 'ann', dst: 'bob', tier: 1),
  ],
  requests: const [
    ConstellationRequest(
      id: 'req-ann',
      authorId: 'ann',
      title: 'Tools',
      status: 0,
    ),
    ConstellationRequest(
      id: 'req-bob',
      authorId: 'bob',
      title: 'Ride',
      status: 0,
    ),
  ],
  posts: [
    ConstellationPost(
      id: 'post-ann',
      authorId: 'ann',
      rootExcerpt: 'Who has a ladder?',
      lastActivityAt: _loadedAt.subtract(const Duration(hours: 1)),
    ),
  ],
  directContactIds: const ['ann', 'olga', 'quiet'],
);

Future<ConstellationCubit> _loadCubit() async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(_field()),
      accountId: 'ego',
    ).store,
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  cubit.updateLabelBudgetContext(
    viewport: const Size(1200, 900),
    textScaleFactor: 1,
  );
  return cubit;
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: child),
);

Future<void> _pumpList(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      BlocProvider<ConstellationCubit>.value(
        value: cubit,
        child: const Scaffold(body: ConstellationTextView()),
      ),
    ),
  );
  cubit.setViewMode(ConstellationViewMode.text);
  await tester.pumpAndSettle();
}

Future<void> _pumpMap(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      MultiBlocProvider(
        providers: [
          BlocProvider<ConstellationCubit>.value(value: cubit),
          BlocProvider<GraphPersonContextCubit>(
            create: (_) => _StubContextCubit(),
          ),
          BlocProvider<ScreenCubit>(
            create: (_) => ScreenCubit(FakeUiEffectPort()),
          ),
        ],
        child: Builder(
          builder: (context) => Scaffold(
            appBar: TenturaTopBar.of(
              context,
              title: const SizedBox.shrink(),
              row: ConstellationAppBarRow(
                legendExpanded: false,
                onToggleLegend: () {},
              ),
            ),
            body: ConstellationBody(
              legendExpanded: false,
              onToggleLegend: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _personGroup(String id) =>
    find.byKey(Key('constellation.text.person.$id'));

void main() {
  group('field people', () {
    test('are the map population: viewer first, then by name', () async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);

      final people = cubit.fieldPeople;

      expect(people.first.isViewer, isTrue);
      expect(people.skip(1).map((p) => p.id), ['ann', 'bob', 'olga', 'quiet']);
      expect(
        people.map((p) => p.id).toSet(),
        cubit.state.composition!.eligiblePersonIds,
      );
      final byId = {for (final p in people) p.id: p};
      expect(byId['quiet']!.isDirectContact, isTrue);
      expect(byId['olga']!.contactOnly, isTrue);
      expect(byId['bob']!.isDirectContact, isFalse);
    });

    test('name search ignores case and «ё», matches handles and every '
        'word', () {
      const person = ConstellationFieldPerson(
        id: 'q',
        name: 'Quiet Ёлкин',
        handle: 'quietly',
      );

      expect(constellationPersonMatches(person, ''), isTrue);
      expect(constellationPersonMatches(person, 'елкин'), isTrue);
      expect(constellationPersonMatches(person, 'QUIET ёл'), isTrue);
      expect(constellationPersonMatches(person, '@quietly'), isTrue);
      expect(constellationPersonMatches(person, 'quiet bob'), isFalse);
    });
  });

  group('list', () {
    testWidgets('lists everyone on the field, direct contacts first', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpList(tester, cubit);

      for (final id in ['ann', 'olga', 'quiet', 'bob']) {
        expect(_personGroup(id), findsOneWidget, reason: id);
      }
      final directHeader = tester.getTopLeft(
        find.byKey(const Key('constellation.text.section.direct')),
      );
      final othersHeader = tester.getTopLeft(
        find.byKey(const Key('constellation.text.section.others')),
      );
      expect(directHeader.dy, lessThan(othersHeader.dy));
      expect(
        tester.getTopLeft(_personGroup('quiet')).dy,
        lessThan(othersHeader.dy),
      );
      expect(
        tester.getTopLeft(_personGroup('bob')).dy,
        greaterThan(othersHeader.dy),
      );
    });

    testWidgets('a contact node says why nothing of theirs is shown', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpList(tester, cubit);

      expect(
        find.byKey(const Key('constellation.text.contact_only.olga')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('constellation.text.contact_only.quiet')),
        findsNothing,
      );
    });

    testWidgets('a Post is a secondary row that opens its preview', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpList(tester, cubit);

      final post = find.byKey(const Key('constellation.text.post.post-ann'));
      expect(
        find.descendant(of: _personGroup('ann'), matching: post),
        findsOneWidget,
      );
      await tester.tap(post);
      await tester.pumpAndSettle();
      expect(cubit.state.selectedRequestId, 'post-ann');
    });

    testWidgets('tapping a person selects them', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpList(tester, cubit);

      await tester.tap(
        find.byKey(const Key('constellation.text.person_row.quiet')),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, 'quiet');
    });

    testWidgets('the search filters people and says when nobody matches', (
      tester,
    ) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpList(tester, cubit);
      final search = find.descendant(
        of: find.byKey(const Key('constellation.text.search')),
        matching: find.byType(TextField),
      );

      await tester.enterText(search, 'елк');
      await tester.pumpAndSettle();
      expect(_personGroup('quiet'), findsOneWidget);
      for (final id in ['ann', 'olga', 'bob']) {
        expect(_personGroup(id), findsNothing, reason: id);
      }

      await tester.enterText(search, 'nobody here');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.text.search.no_match')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('constellation.text.search.clear')),
      );
      await tester.pumpAndSettle();
      expect(_personGroup('bob'), findsOneWidget);
    });
  });

  group('map search', () {
    testWidgets('choosing a person selects them', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpMap(tester, cubit);

      await tester.tap(find.byKey(const Key('constellation.app_bar.search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'qui');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('constellation.search.person.ann')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('constellation.search.person.quiet')),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.selectedPersonId, 'quiet');
    });

    testWidgets('the search button is on the map only', (tester) async {
      final cubit = await _loadCubit();
      addTearDown(cubit.close);
      await _pumpMap(tester, cubit);
      final button = find.byKey(const Key('constellation.app_bar.search'));

      expect(button.hitTestable(), findsOneWidget);
      cubit.setViewMode(ConstellationViewMode.text);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsNothing);
    });
  });
}
