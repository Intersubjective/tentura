import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_person_field_item.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_person_field_items_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_person_field_items_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_person_field_items_section.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');
final _loadedAt = DateTime.utc(2026, 11, 5, 12);

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

final class _FakeItemsPort implements ConstellationPersonFieldItemsPort {
  _FakeItemsPort(this.handler);

  final Future<ConstellationPersonFieldItemsPage> Function({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query,
    String? cursor,
  })
  handler;

  final calls = <({
    String personId,
    ConstellationPersonFieldBucket bucket,
    String query,
    String? cursor,
  })>[];

  @override
  Future<ConstellationPersonFieldItemsPage> fetch({
    required String personId,
    required ConstellationPersonFieldBucket bucket,
    String query = '',
    String? cursor,
  }) async {
    calls.add((
      personId: personId,
      bucket: bucket,
      query: query,
      cursor: cursor,
    ));
    return handler(
      personId: personId,
      bucket: bucket,
      query: query,
      cursor: cursor,
    );
  }
}

final class _RecordingHidePort implements ConstellationFieldHidePort {
  final hideCalls = <({int targetKind, String targetId})>[];
  final unhideCalls = <({int targetKind, String targetId})>[];

  @override
  Future<void> hide({required int targetKind, required String targetId}) async {
    hideCalls.add((targetKind: targetKind, targetId: targetId));
  }

  @override
  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) async {
    unhideCalls.add((targetKind: targetKind, targetId: targetId));
  }

  @override
  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({
    String? cursor,
  }) async =>
      const [];
}

final class _StubTargetedReadPort implements ConstellationTargetedReadPort {
  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async =>
      const [];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async =>
      const [];
}

ConstellationField _field() => ConstellationField(
  loadedAt: _loadedAt,
  context: '',
  peers: const [
    ConstellationPerson(id: 'ego', displayName: 'Ego'),
    ConstellationPerson(id: 'am', displayName: 'Alex'),
  ],
  edges: const [
    ConstellationTrustEdgeEntity(src: 'ego', dst: 'am', tier: 1),
  ],
  directContactIds: const ['am'],
  requests: [
    ConstellationRequest(
      id: 'req-active',
      authorId: 'am',
      title: 'Active boxes',
      status: 0,
      lastActivityAt: _loadedAt,
    ),
  ],
);

Future<ConstellationCubit> _cubit({
  required _FakeItemsPort itemsPort,
  _RecordingHidePort? hidePort,
}) async {
  final hide = hidePort ?? _RecordingHidePort();
  final fixture = ConstellationStoreFixture(
    _StubRepository(_field()),
    accountId: 'ego',
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: _ego,
    fieldHideCase: ConstellationFieldHideCase(
      hide,
      fixture.store,
      _StubTargetedReadPort(),
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    ),
    personFieldItemsCase: ConstellationPersonFieldItemsCase(
      itemsPort,
      env: const Env.fromEnvironment(),
      logger: Logger('test'),
    ),
  );
  await cubit.stream.firstWhere((s) => s.status is StateIsSuccess);
  return cubit;
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(child: child),
    );

void main() {
  group('Person Field items panel (#255 l9k5.10)', () {
    testWidgets('tabs load bucket-specific items with counts', (tester) async {
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async {
          return ConstellationPersonFieldItemsPage(
            items: [
              ConstellationPersonFieldItem(
                id: 'item-${bucket.wireValue}',
                kind: ConstellationFieldTargetKind.request,
                authorId: 'am',
                title: 'Title ${bucket.wireValue}',
                rootExcerpt: '',
                status: 0,
                hidden: bucket == ConstellationPersonFieldBucket.hidden,
                lastActivityAt: _loadedAt,
              ),
            ],
            counts: const ConstellationPersonFieldCounts(
              active: 1,
              closed: 2,
              hidden: 3,
            ),
          );
        },
      );
      final cubit = await _cubit(itemsPort: port);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Title active'), findsOneWidget);

      await tester.tap(find.byKey(const Key('constellation.person_items.tab.closed')));
      await tester.pumpAndSettle();
      expect(find.text('Title closed'), findsOneWidget);

      await tester.tap(find.byKey(const Key('constellation.person_items.tab.hidden')));
      await tester.pumpAndSettle();
      expect(find.text('Title hidden'), findsOneWidget);
    });

    testWidgets('search passes query to the server', (tester) async {
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async =>
            emptyConstellationPersonFieldItemsPage,
      );
      final cubit = await _cubit(itemsPort: port);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.constellationPersonItemsSearch)),
        'ladder',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        port.calls.any((c) => c.query == 'ladder' && c.bucket == ConstellationPersonFieldBucket.active),
        isTrue,
      );
    });

    testWidgets('Hide calls fieldHide and refreshes', (tester) async {
      final hidePort = _RecordingHidePort();
      var loads = 0;
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async {
          loads++;
          if (bucket == ConstellationPersonFieldBucket.active && loads == 1) {
            return ConstellationPersonFieldItemsPage(
              items: [
                ConstellationPersonFieldItem(
                  id: 'req-active',
                  kind: ConstellationFieldTargetKind.request,
                  authorId: 'am',
                  title: 'Hide me',
                  rootExcerpt: '',
                  status: 0,
                  hidden: false,
                  lastActivityAt: _loadedAt,
                ),
              ],
            );
          }
          return emptyConstellationPersonFieldItemsPage;
        },
      );
      final cubit = await _cubit(itemsPort: port, hidePort: hidePort);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hide from Field'));
      await tester.pumpAndSettle();

      expect(hidePort.hideCalls, hasLength(1));
      expect(hidePort.hideCalls.single.targetId, 'req-active');
    });

    testWidgets('Show again on Hidden tab calls fieldUnhide', (tester) async {
      final hidePort = _RecordingHidePort();
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async {
          if (bucket == ConstellationPersonFieldBucket.hidden) {
            return ConstellationPersonFieldItemsPage(
              items: [
                ConstellationPersonFieldItem(
                  id: 'req-hidden',
                  kind: ConstellationFieldTargetKind.request,
                  authorId: 'am',
                  title: 'Hidden one',
                  rootExcerpt: '',
                  status: 0,
                  hidden: true,
                  lastActivityAt: _loadedAt,
                ),
              ],
            );
          }
          return emptyConstellationPersonFieldItemsPage;
        },
      );
      final cubit = await _cubit(itemsPort: port, hidePort: hidePort);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('constellation.person_items.tab.hidden')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show again'));
      await tester.pumpAndSettle();

      expect(hidePort.unhideCalls, hasLength(1));
      expect(hidePort.unhideCalls.single.targetId, 'req-hidden');
    });

    testWidgets('Load more requests the next cursor page', (tester) async {
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async {
          if (cursor == null) {
            return ConstellationPersonFieldItemsPage(
              items: [
                ConstellationPersonFieldItem(
                  id: 'page-1',
                  kind: ConstellationFieldTargetKind.request,
                  authorId: 'am',
                  title: 'First page',
                  rootExcerpt: '',
                  status: 0,
                  hidden: false,
                  lastActivityAt: _loadedAt,
                ),
              ],
              nextCursor: 'cursor-2',
            );
          }
          return ConstellationPersonFieldItemsPage(
            items: [
              ConstellationPersonFieldItem(
                id: 'page-2',
                kind: ConstellationFieldTargetKind.request,
                authorId: 'am',
                title: 'Second page',
                rootExcerpt: '',
                status: 0,
                hidden: false,
                lastActivityAt: _loadedAt,
              ),
            ],
          );
        },
      );
      final cubit = await _cubit(itemsPort: port);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: ConstellationPersonFieldItemsSection(personId: 'am'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('First page'), findsOneWidget);
      await tester.tap(find.byKey(TestIds.key(TestIds.constellationPersonItemsLoadMore)));
      await tester.pumpAndSettle();

      expect(find.text('Second page'), findsOneWidget);
      expect(port.calls.any((c) => c.cursor == 'cursor-2'), isTrue);
    });

    testWidgets('RU 375×667 panel section does not overflow', (tester) async {
      await usePhoneSurface(tester);
      final port = _FakeItemsPort(
        ({
          required personId,
          required bucket,
          query = '',
          cursor,
        }) async =>
            ConstellationPersonFieldItemsPage(
              items: [
                ConstellationPersonFieldItem(
                  id: 'long',
                  kind: ConstellationFieldTargetKind.request,
                  authorId: 'am',
                  title: 'Очень длинное название запроса на помощь с переездом',
                  rootExcerpt: '',
                  status: 0,
                  hidden: false,
                  lastActivityAt: _loadedAt,
                ),
              ],
              counts: const ConstellationPersonFieldCounts(
                active: 9,
                closed: 8,
                hidden: 7,
              ),
            ),
      );
      final cubit = await _cubit(itemsPort: port);
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        _app(
          BlocProvider.value(
            value: cubit,
            child: const Scaffold(
              body: SingleChildScrollView(
                child: ConstellationPersonFieldItemsSection(personId: 'am'),
              ),
            ),
          ),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Скрыть'), findsOneWidget);
    });
  });
}
