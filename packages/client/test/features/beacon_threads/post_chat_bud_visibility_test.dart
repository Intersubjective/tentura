import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_page.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/beacon_create_case_factory.dart';
import '../../support/fake_app_navigator.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

const _sourceId = 'Mpostsource01';
const _childId = 'Bchild000001';
const _title = 'Встреча соседей';
const _sourceText = 'Кто возьмёт ключи?';
const _actor = 'Омар';
const _budNotice = Key('Room.BudNotice');
const _deadline = Duration(seconds: 5);
const _post = RoomCapabilities.post();

Map<String, dynamic> _row(String id, int minute, {String body = ''}) =>
    roomHintWireMessageRow(
      id: id,
      authorId: 'Uhelper000001',
      authorTitle: _actor,
      createdAt: DateTime.utc(2026, 10, 21, 9, minute).toIso8601String(),
      body: body,
    );

Future<void> _openPostChat(
  WidgetTester tester, {
  required List<Map<String, dynamic>> messages,
  required Locale locale,
}) async {
  await usePhoneSurface(tester);
  final server = RoomHintWireServer()..messageRows = messages;
  final wire = (await tester.runAsync(
    () => RoomHintWire.start(server).timeout(_deadline),
  ))!;
  addTearDown(() => tester.runAsync(wire.close));
  final repository = RoomOverRealHintWireRepository(wire.repository);
  addTearDown(repository.dispose);
  final room = (await tester.runAsync(() async {
    final room = RoomCubit(
      beaconId: kRoomCubitFakeBeaconId,
      beaconRoomCase: roomCubitMakeCase(repository),
      coordinationItemRoomSync: CoordinationItemRoomSync(),
      presenceRepository: roomCubitFakePresenceRepository(),
      effects: FakeUiEffectPort(),
      capabilities: _post,
    );
    addTearDown(() => tester.runAsync(room.close));
    await awaitRoomCubitLoad(room).timeout(_deadline);
    room.syncBeaconStatus(BeaconStatus.open);
    return room;
  }))!;

  expect(server.queried, contains('RoomMessageList'));
  expect(room.state.firstLoadDone, isTrue);
  expect(room.state.loadError, isNull);

  const viewer = Profile(id: roomHintWireViewerId, displayName: 'Я');
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: room),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(viewer),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconRoomBody(enableComposer: false, capabilities: _post),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    find.byWidgetPredicate(
      (widget) => widget is RoomMessageTile && widget.message.id == _sourceId,
    ),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}

void main() {
  late FakeAppNavigator navigator;
  late FakeBeaconHierarchyRepositoryPort hierarchy;
  late List<BeaconHierarchyChildGroup> hierarchyReads;

  setUp(() async {
    await GetIt.I.reset();
    addTearDown(GetIt.I.reset);
    registerRoomCubitProfileCubit(roomHintWireViewerId);
    navigator = registerFakeAppNavigator();
    hierarchyReads = [];
    hierarchy =
        FakeBeaconHierarchyRepositoryPort(
            fetchChildrenHandler: ({required group, after}) async {
              hierarchyReads.add(group);
              return const BeaconHierarchyPage(summaries: []);
            },
          )
          ..childPreviews[_childId] = BeaconHierarchySummary(
            beaconId: _childId,
            title: _title,
            owner: const BeaconHierarchyOwnerSummary(
              id: 'Uhelper000001',
              displayName: _actor,
            ),
            status: BeaconStatus.open,
            publishedAt: DateTime.utc(2026, 10, 21),
            isTombstone: false,
          );
    final beacons = FakeBeaconWritePort();
    GetIt.I
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository())
      ..registerSingleton<BeaconHierarchyCase>(
        buildBeaconHierarchyCaseForTest(
          hierarchy,
          createCase: buildBeaconCreateCase(beacons: beacons),
          beacons: beacons,
          commandStore: InMemoryBeaconChildCommandStore(),
        ),
      );
  });

  Map<String, dynamic> source() =>
      _row(_sourceId, 0, body: _sourceText)
        ..['promotedChildBeaconId'] = _childId;

  for (final (count, locale) in [
    (0, const Locale('en')),
    (2, const Locale('ru')),
  ]) {
    testWidgets(
      'Post Chat offers one link from a server bud notice with ${count == 0 ? 'no invites' : 'invites on a Russian phone'}',
      (tester) async {
        await _openPostChat(
          tester,
          locale: locale,
          messages: [
            _row(_sourceId, 0, body: _sourceText),
            _row('Mbudnotice01', 1)..addAll({
              'systemMessageKind': BeaconRoomSystemMessageKind.childCreated,
              'systemPayloadJson': jsonEncode({
                'version': 1,
                'kind': 'childCreated',
                'childBeaconId': _childId,
                'sourceMessageId': _sourceId,
                'title': _title,
                'invitedCount': count,
              }),
            }),
          ],
        );

        final notice = find.byKey(_budNotice);
        final l10n = lookupL10n(locale);
        final text = count == 0
            ? l10n.roomBudNoticeNoInvites(_actor, _title)
            : l10n.roomBudNotice(_actor, _title, count);
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: notice, matching: find.text(text)),
          findsOneWidget,
        );
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
        expect(
          navigator.named('openBeacon').map((intent) => intent.args['id']),
          [_childId],
        );
        expect(tester.takeException(), isNull);
        expect(
          (
            find.byType(BeaconChildPromotionFooter).evaluate().length,
            hierarchy.fetchChildPreviewCallCount,
            hierarchyReads.length,
          ),
          (0, 0, 0),
          reason:
              'the notice is the only child link and needs no hierarchy lookups',
        );
      },
    );
  }

  testWidgets(
    'Post Chat does not turn a source message into a child link without a bud notice',
    (
      tester,
    ) async {
      await _openPostChat(
        tester,
        locale: const Locale('ru'),
        messages: [source()],
      );

      expect(find.byKey(_budNotice), findsNothing);
      expect(
        (
          find.text(_title).evaluate().length,
          find.byType(BeaconChildPromotionFooter).evaluate().length,
          hierarchy.fetchChildPreviewCallCount,
          hierarchyReads.length,
        ),
        (0, 0, 0, 0),
        reason:
            'omitting the bud notice also omits its child link and hierarchy lookups',
      );
    },
  );
}
