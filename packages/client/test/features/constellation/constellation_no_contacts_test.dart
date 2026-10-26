// #252: a field with nobody on it but the viewer says what to do (invite
// someone) and why trust matters, instead of "No active requests".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_no_contacts.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

const _trustSentence =
    'People you trust, and who trust you back, widen whom you can see and '
    'send to.';

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

Future<ConstellationCubit> _loadCubit(ConstellationField field) async {
  final cubit = ConstellationCubit(
    case_: ConstellationStoreFixture(
      _StubRepository(field),
      accountId: 'ego',
    ).store,
    viewer: _ego,
  );
  await cubit.stream.firstWhere((state) => state.status is StateIsSuccess);
  return cubit;
}

ConstellationField _field({List<ConstellationPerson> peers = const []}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 22),
      context: '',
      peers: peers,
    );

Future<void> _pump(
  WidgetTester tester,
  ConstellationCubit cubit,
  Widget child,
) async {
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider<ConstellationCubit>.value(
          value: cubit,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('only the viewer on the field counts as no contacts', () {
    expect(constellationFieldHasNoContacts(_field(), 'ego'), isTrue);
    expect(
      constellationFieldHasNoContacts(
        _field(peers: const [ConstellationPerson(id: 'ego')]),
        'ego',
      ),
      isTrue,
    );
    expect(
      constellationFieldHasNoContacts(
        _field(peers: const [ConstellationPerson(id: 'a')]),
        'ego',
      ),
      isFalse,
    );
  });

  testWidgets('map banner: title, trust sentence and invite', (tester) async {
    final cubit = await _loadCubit(_field());
    addTearDown(cubit.close);
    var invited = false;
    await _pump(
      tester,
      cubit,
      ConstellationNoContactsBanner(onInvite: () => invited = true),
    );

    expect(find.byKey(ConstellationNoContactsBanner.bannerKey), findsOneWidget);
    expect(find.text('No one is on your Field yet'), findsOneWidget);
    expect(find.text(_trustSentence), findsOneWidget);
    await tester.tap(find.byKey(ConstellationNoContactsBanner.inviteKey));
    expect(invited, isTrue);
  });

  testWidgets('map banner stays away once someone is on the field', (
    tester,
  ) async {
    final cubit = await _loadCubit(
      _field(
        peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
      ),
    );
    addTearDown(cubit.close);
    await _pump(tester, cubit, const ConstellationNoContactsBanner());

    expect(find.byKey(ConstellationNoContactsBanner.bannerKey), findsNothing);
  });

  testWidgets('list view: empty field shows the no-contacts state', (
    tester,
  ) async {
    final cubit = await _loadCubit(_field());
    addTearDown(cubit.close);
    await _pump(tester, cubit, const ConstellationTextView());

    expect(
      find.byKey(ConstellationNoContactsEmptyState.emptyKey),
      findsOneWidget,
    );
    expect(find.text(_trustSentence), findsOneWidget);
    expect(find.text('Invite someone you know'), findsOneWidget);
  });

  testWidgets('list view: visible people without requests remain listed', (
    tester,
  ) async {
    final cubit = await _loadCubit(
      _field(
        peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
      ),
    );
    addTearDown(cubit.close);
    await _pump(tester, cubit, const ConstellationTextView());

    expect(
      find.byKey(ConstellationNoContactsEmptyState.emptyKey),
      findsNothing,
    );
    expect(find.byKey(const Key('constellation.text.empty')), findsNothing);
    expect(find.text('Ann'), findsOneWidget);
  });
}
