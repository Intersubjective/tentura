import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/phone_surface.dart';
import '../../support/people_tags_widget_harness.dart';

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationField _listField({
  required bool requestUnread,
  required bool postUnread,
}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 11, 5),
      context: '',
      peers: [
        const ConstellationPerson(id: 'author', displayName: 'Author'),
      ],
      edges: const [
        ConstellationTrustEdgeEntity(src: 'ego', dst: 'author', tier: 1),
      ],
      directContactIds: const ['author'],
      requests: [
        ConstellationRequest(
          id: 'req-a',
          authorId: 'author',
          title: 'Need a ladder',
          status: 0,
          hasUnread: requestUnread,
        ),
      ],
      posts: [
        ConstellationPost(
          id: 'post-a',
          authorId: 'author',
          rootExcerpt: 'Coffee meetup',
          lastActivityAt: DateTime.utc(2026, 11, 5),
          hasUnread: postUnread,
        ),
      ],
      anchorProjection: ConstellationAnchorProjection(
        revision: _revision(1),
        anchors: const [],
        pinnedPeers: const [],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );

final class _StubRepository implements ConstellationRepositoryPort {
  _StubRepository(this.field);

  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
}

Future<ConstellationCubit> _pumpList(
  WidgetTester tester, {
  required ConstellationField field,
  Locale locale = const Locale('en'),
  bool phone = false,
}) async {
  if (phone) {
    await usePhoneSurface(tester);
  }
  final fixture = ConstellationStoreFixture(
    _StubRepository(field),
    accountId: 'ego',
  );
  final cubit = fixture.createCubit(
    viewer: const Profile(id: 'ego', displayName: 'Viewer'),
  );
  await cubit.load();
  cubit.emit(cubit.state.copyWith(viewMode: ConstellationViewMode.text));

  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: BlocProvider<ConstellationCubit>.value(
        value: cubit,
        child: const Scaffold(body: ConstellationTextView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

FontWeight? _titleWeight(WidgetTester tester, String title) {
  final text = tester.widget<Text>(find.text(title));
  return text.style?.fontWeight;
}

void main() {
  testWidgets('unread Request row shows trailing dot and bold title', (
    tester,
  ) async {
    await _pumpList(
      tester,
      field: _listField(requestUnread: true, postUnread: false),
    );

    expect(
      find.byKey(const Key('constellation.text.unreadDot.req-a')),
      findsOneWidget,
    );
    expect(_titleWeight(tester, 'Need a ladder'), FontWeight.w600);
    expect(
      find.byKey(const Key('constellation.text.unreadDot.post-a')),
      findsNothing,
    );
  });

  testWidgets('unread Post row shows trailing dot and bold title', (
    tester,
  ) async {
    await _pumpList(
      tester,
      field: _listField(requestUnread: false, postUnread: true),
    );

    expect(
      find.byKey(const Key('constellation.text.unreadDot.post-a')),
      findsOneWidget,
    );
    expect(_titleWeight(tester, 'Coffee meetup'), FontWeight.w600);
    expect(
      find.byKey(const Key('constellation.text.unreadDot.req-a')),
      findsNothing,
    );
    expect(_titleWeight(tester, 'Need a ladder'), FontWeight.w400);
  });

  testWidgets('read rows show no dot and regular title weight', (tester) async {
    await _pumpList(
      tester,
      field: _listField(requestUnread: false, postUnread: false),
    );

    expect(find.byKey(const Key('constellation.text.unreadDot.req-a')), findsNothing);
    expect(find.byKey(const Key('constellation.text.unreadDot.post-a')), findsNothing);
    expect(_titleWeight(tester, 'Need a ladder'), FontWeight.w400);
    expect(_titleWeight(tester, 'Coffee meetup'), FontWeight.w400);
  });

  testWidgets('semantics label includes unread suffix for Request', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpList(
      tester,
      field: _listField(requestUnread: true, postUnread: false),
    );

    final l10n = lookupL10n(const Locale('en'));
    final node = tester.getSemantics(
      find.bySemanticsIdentifier(TestIds.constellationTextRequest('req-a')),
    );
    expect(
      node.getSemanticsData().label,
      startsWith(
        l10n.constellationFieldUnreadBeaconSemantics('Need a ladder'),
      ),
    );
    semantics.dispose();
  });

  testWidgets('375×667 RU: unread Post title stays bold without overflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpList(
      tester,
      field: _listField(requestUnread: false, postUnread: true).copyWith(
        posts: [
          ConstellationPost(
            id: 'post-a',
            authorId: 'author',
            rootExcerpt: 'Длинный текст поста для проверки переноса',
            lastActivityAt: DateTime.utc(2026, 11, 5),
            hasUnread: true,
          ),
        ],
      ),
      locale: const Locale('ru'),
      phone: true,
    );

    expect(
      find.byKey(const Key('constellation.text.unreadDot.post-a')),
      findsOneWidget,
    );
    expect(
      _titleWeight(tester, 'Длинный текст поста для проверки переноса'),
      FontWeight.w600,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
