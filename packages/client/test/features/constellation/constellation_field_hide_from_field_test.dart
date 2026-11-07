import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/data/repository/constellation_field_hide_repository.dart';
import 'package:tentura/features/constellation/domain/constellation_field_patches.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/port/constellation_field_hide_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_hide_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_item_actions.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_request_preview_sheet.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

final class _RecordingHidePort implements ConstellationFieldHidePort {
  final hideCalls = <({int targetKind, String targetId})>[];
  final unhideCalls = <({int targetKind, String targetId})>[];
  bool failHide = false;
  List<ConstellationFieldHiddenItem> hiddenItems = const [];

  @override
  Future<void> hide({required int targetKind, required String targetId}) async {
    hideCalls.add((targetKind: targetKind, targetId: targetId));
    if (failHide) {
      throw StateError('hide failed');
    }
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
  }) async => hiddenItems;
}

ConstellationField _singleRequestField({
  required String requestId,
  bool hasUnread = false,
}) {
  return ConstellationField(
    loadedAt: DateTime.utc(2026, 11, 4),
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
        hasUnread: hasUnread,
      ),
    ],
  );
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

final class _StubFieldRepo implements ConstellationRepositoryPort {
  _StubFieldRepo(this.field);
  final ConstellationField field;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;
}

final class _StubTargetedReadPort implements ConstellationTargetedReadPort {
  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async => const [];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async => const [];
}

Future<void> _pumpPreview(
  WidgetTester tester,
  ConstellationCubit cubit,
  ConstellationRequest request, {
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
          child: Scaffold(
            body: ConstellationRequestPreviewSheet(
              request: request,
              authorDisplayName: 'Alex',
              onClose: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Widget _themedApp({
  required Widget child,
  Locale locale = const Locale('en'),
  TargetPlatform platform = TargetPlatform.android,
}) {
  return MaterialApp(
    locale: locale,
    theme: TenturaTheme.light().copyWith(platform: platform),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: TenturaResponsiveScope(
      child: Scaffold(body: child),
    ),
  );
}

Future<void> _pumpList(WidgetTester tester, ConstellationCubit cubit) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  cubit.updateLabelBudgetContext(
    viewport: const Size(1200, 900),
    textScaleFactor: 1,
  );
  await tester.pumpPeopleTagsWidget(
    _themedApp(
      child: BlocProvider.value(
        value: cubit,
        child: const ConstellationTextView(),
      ),
    ),
  );
  cubit.setViewMode(ConstellationViewMode.text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

const _mapNodeKey = Key('field_hide.map_node');

Future<void> _secondaryTapAt(WidgetTester tester, Finder target) async {
  await tester.tap(
    target,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpMapChrome(
  WidgetTester tester,
  ConstellationCubit cubit, {
  required String beaconId,
  TargetPlatform platform = TargetPlatform.android,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpPeopleTagsWidget(
    _themedApp(
      platform: platform,
      locale: locale,
      child: BlocProvider<ConstellationCubit>.value(
        value: cubit,
        child: Center(
          child: ConstellationFieldBeaconMapChrome(
            targetKind: ConstellationFieldTargetKind.request,
            beaconId: beaconId,
            child: const SizedBox(
              key: _mapNodeKey,
              width: 48,
              height: 48,
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
      GetIt.I.registerSingleton<Logger>(Logger('field-hide-test'));
    }
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<Logger>()) {
      await GetIt.I.unregister<Logger>();
    }
  });

  group('Hide from Field (#255)', () {
    testWidgets('preview Hide removes map/list node and sends fieldHide; Undo '
        'restores and sends fieldUnhide', (tester) async {
      await usePhoneSurface(tester);

      const requestId = 'req-hide-1';
      final field = _singleRequestField(requestId: requestId);
      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(field: field, port: port);
      addTearDown(cubit.close);

      final request = cubit.state.field!.requests.single;
      await _pumpPreview(tester, cubit, request);

      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationHideFromField)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(port.hideCalls, hasLength(1));
      expect(port.hideCalls.single.targetId, requestId);
      expect(cubit.state.field!.requests, isEmpty);

      expect(find.text('Hidden from your Field.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(port.unhideCalls, hasLength(1));
      expect(cubit.state.field!.requests.single.id, requestId);
    });

    testWidgets('RU phone preview shows hide copy without overflow', (
      tester,
    ) async {
      await usePhoneSurface(tester);

      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-ru-1'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpPreview(
        tester,
        cubit,
        cubit.state.field!.requests.single,
        locale: const Locale('ru'),
      );
      await tester.pump();

      final hideLabel = find.text('Скрыть с «Поля»');
      expect(hideLabel, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'pointer hover does not show toolbar or shift map node layout',
      (
        tester,
      ) async {
        final port = _RecordingHidePort();
        final cubit = await _cubitWithHide(
          field: _singleRequestField(requestId: 'req-hover-1'),
          port: port,
        );
        addTearDown(cubit.close);

        await _pumpMapChrome(
          tester,
          cubit,
          platform: TargetPlatform.macOS,
          beaconId: 'req-hover-1',
        );

        final node = find.byKey(_mapNodeKey);
        final sizeBefore = tester.getSize(node);
        final topLeftBefore = tester.getTopLeft(node);

        final center = tester.getCenter(node);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: center);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(center);
        await tester.pump();

        expect(find.text('Hide from Field'), findsNothing);
        expect(find.text('Pin'), findsNothing);
        expect(tester.getSize(node), sizeBefore);
        expect(tester.getTopLeft(node), topLeftBefore);

        await gesture.removePointer();
        await tester.pump();
      },
    );

    testWidgets('RU phone secondary tap on map chrome opens hide menu', (
      tester,
    ) async {
      await usePhoneSurface(tester);

      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-ru-menu-1'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpMapChrome(
        tester,
        cubit,
        platform: TargetPlatform.macOS,
        beaconId: 'req-ru-menu-1',
        locale: const Locale('ru'),
      );

      await _secondaryTapAt(tester, find.byKey(_mapNodeKey));

      expect(find.text('Скрыть с «Поля»'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('secondary tap opens hide menu on map chrome', (tester) async {
      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-menu-1'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpMapChrome(
        tester,
        cubit,
        platform: TargetPlatform.macOS,
        beaconId: 'req-menu-1',
      );

      await _secondaryTapAt(tester, find.byKey(_mapNodeKey));

      expect(find.text('Hide from Field'), findsOneWidget);
    });

    testWidgets('list row overflow menu includes Hide', (tester) async {
      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-list-1'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpList(tester, cubit);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hide from Field'), findsOneWidget);
    });

    testWidgets('failed fieldHide restores the node and shows error snackbar', (
      tester,
    ) async {
      final port = _RecordingHidePort()..failHide = true;
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: 'req-fail-1'),
        port: port,
      );
      addTearDown(cubit.close);

      await _pumpPreview(tester, cubit, cubit.state.field!.requests.single);
      await tester.tap(
        find.byKey(TestIds.key(TestIds.constellationHideFromField)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(cubit.state.field!.requests.single.id, 'req-fail-1');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('hidden unread item draws no glow', (tester) async {
      const requestId = 'req-glow-1';
      final port = _RecordingHidePort();
      final cubit = await _cubitWithHide(
        field: _singleRequestField(requestId: requestId, hasUnread: true),
        port: port,
      );
      addTearDown(cubit.close);

      expect(
        cubit.unreadGlowGraphIds(isOnMap: (_) => true),
        contains('fr:$requestId'),
      );

      cubit.beginHideFromField(
        targetKind: ConstellationFieldTargetKind.request,
        beaconId: requestId,
      );
      expect(cubit.unreadGlowGraphIds(isOnMap: (_) => true), isEmpty);
    });
  });

  test('FieldHide repository sends wire mutation', () async {
    final sent = <WireSent>[];
    await withRemoteWire(
      {
        'FieldHide': {'fieldHide': true},
      },
      sent,
      (remote) async {
        final repo = ConstellationFieldHideRepository(remote);
        await repo.hide(targetKind: 0, targetId: 'Bwire001');
      },
    );
    expect(sent.single.operationName, 'FieldHide');
    expect(sent.single.variables['targetId'], 'Bwire001');
  });
}
