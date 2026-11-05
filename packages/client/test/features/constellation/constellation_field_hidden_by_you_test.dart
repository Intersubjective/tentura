import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_hidden_sheet.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';

final class _RecordingHidePort implements ConstellationFieldHidePort {
  final unhideCalls = <({int targetKind, String targetId})>[];
  List<ConstellationFieldHiddenItem> hiddenItems = const [];

  @override
  Future<void> hide({required int targetKind, required String targetId}) async {}

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
      hiddenItems;
}

ConstellationField _singleRequestField({required String requestId}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 11, 5),
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
        id: requestId,
        authorId: 'am',
        title: 'Need help moving boxes',
        status: 0,
      ),
    ],
  );
}

final class _StubFieldRepo implements ConstellationRepositoryPort {
  _StubFieldRepo(this.field);
  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async =>
      field;
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

Future<ConstellationCubit> _cubitWithHide({
  required ConstellationField field,
  required _RecordingHidePort port,
}) async {
  final fixture = ConstellationStoreFixture(
    _StubFieldRepo(field),
    accountId: 'ego',
  );
  final hideCase = ConstellationFieldHideCase(
    port,
    fixture.store,
    _StubTargetedReadPort(),
    env: const Env.fromEnvironment(),
    logger: Logger('test'),
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: const Profile(id: 'ego', displayName: 'Ego'),
    fieldHideCase: hideCase,
  );
  await cubit.stream.firstWhere(
    (s) => s.status is StateIsSuccess && s.field != null,
  );
  return cubit;
}

Future<void> _pumpFilterBar(
  WidgetTester tester,
  ConstellationCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpPeopleTagsWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: BlocProvider.value(
          value: cubit,
          child: const Scaffold(
            body: SingleChildScrollView(
              child: ConstellationFilterBar(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('hidden-by-you-test'));
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<Logger>()) {
      await GetIt.I.unregister<Logger>();
    }
  });

  group('Hidden by you (#255 l9k5.7)', () {
    testWidgets('filter row absent when count is zero', (tester) async {
      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-0'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpFilterBar(tester, cubit);

      expect(find.text('Hidden by you (0)'), findsNothing);
      expect(
        find.byKey(TestIds.key(TestIds.constellationHiddenByYouRow)),
        findsNothing,
      );
    });

    testWidgets('filter row shows Hidden by you (3) when count is three', (
      tester,
    ) async {
      final port = _RecordingHidePort()
        ..hiddenItems = List.generate(
          3,
          (index) => ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.request,
            targetId: 'hid-$index',
            title: 'Hidden $index',
            authorId: 'am',
            hiddenAt: DateTime.utc(2026, 11, index + 1),
          ),
        );
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-3'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpFilterBar(tester, cubit);

      expect(find.text('Hidden by you (3)'), findsOneWidget);
    });

    testWidgets('hidden list renders items from fieldHiddenItems', (
      tester,
    ) async {
      final port = _RecordingHidePort()
        ..hiddenItems = [
          ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.request,
            targetId: 'hid-1',
            title: 'First hidden',
            authorId: 'am',
            hiddenAt: DateTime.utc(2026, 11, 1),
          ),
          ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.post,
            targetId: 'hid-2',
            title: 'Second hidden',
            authorId: 'am',
            hiddenAt: DateTime.utc(2026, 11, 2),
          ),
        ];
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-list'),
        port: port,
      );
      addTearDown(cubit.close);

      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: const Scaffold(
                body: ConstellationFieldHiddenSheetBody(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('First hidden'), findsOneWidget);
      expect(find.text('Second hidden'), findsOneWidget);
      expect(find.text('Alex'), findsNWidgets(2));
    });

    testWidgets('Show sends fieldUnhide, removes row, restores Field store', (
      tester,
    ) async {
      const requestId = 'req-show-1';
      final field = _singleRequestField(requestId: requestId);
      final port = _RecordingHidePort()
        ..hiddenItems = [
          ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.request,
            targetId: requestId,
            title: 'Need help moving boxes',
            authorId: 'am',
            hiddenAt: DateTime.utc(2026, 11, 3),
          ),
        ];
      final cubit = await _cubitWithHide(field: field, port: port);
      addTearDown(cubit.close);

      cubit.beginHideFromField(
        targetKind: ConstellationFieldTargetKind.request,
        beaconId: requestId,
      );
      expect(cubit.state.field!.requests, isEmpty);

      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: BlocProvider.value(
              value: cubit,
              child: const Scaffold(
                body: ConstellationFieldHiddenSheetBody(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(TestIds.key(TestIds.constellationHiddenByYouShow)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(port.unhideCalls, hasLength(1));
      expect(port.unhideCalls.single.targetId, requestId);
      expect(find.text('Need help moving boxes'), findsNothing);
      expect(cubit.state.field!.requests.single.id, requestId);
    });

    testWidgets('RU phone filter row has no overflow at 375x667', (
      tester,
    ) async {
      await usePhoneSurface(tester);
      final port = _RecordingHidePort()
        ..hiddenItems = List.generate(
          3,
          (index) => ConstellationFieldHiddenItem(
            targetKind: ConstellationFieldTargetKind.request,
            targetId: 'ru-hid-$index',
            title: 'Hidden $index',
            authorId: 'am',
            hiddenAt: DateTime.utc(2026, 11, index + 1),
          ),
        );
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-ru'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpFilterBar(tester, cubit, locale: const Locale('ru'));
      await tester.pump();

      expect(find.text('Скрыто вами (3)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
