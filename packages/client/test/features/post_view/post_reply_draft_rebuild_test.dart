import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/data/service/beacon_room_composer_draft_store.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart';
import '../beacon_threads/support/room_hint_wire_harness.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_screen_harness.dart';

const _postId = kRoomCubitFakeBeaconId;
const _rootId = 'Mpostroot001';
const _rootBody = 'Встреча в субботу';
const _draft = 'Draft reply 1105';
const _author = Profile(id: roomHintWireViewerId, displayName: 'Мария');
final _createdAt = DateTime.utc(2026, 10, 27);

class _PostRoom extends RoomOverRealHintWireRepository {
  _PostRoom(super._real);

  @override
  Future<List<RequestThread>> fetchThreads(String beaconId) async => [
    RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: _createdAt,
    ),
  ];
}

void main() {
  testWidgets('the same Post restores its unsent reply in a new screen', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    addTearDown(GetIt.I.reset);
    addTearDown(() => clearBeaconRoomComposerDraft(_postId));
    final server = RoomHintWireServer()
      ..messageRows = [
        roomHintWireMessageRow(
          id: _rootId,
          authorId: _author.id,
          authorTitle: _author.displayName,
          createdAt: _createdAt.toIso8601String(),
          body: _rootBody,
        ),
      ];
    final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
    addTearDown(() => tester.runAsync(wire.close));
    final room = _PostRoom(wire.repository);
    final beacon = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async {
        expect(id, _postId);
        return Beacon(
          id: id,
          kind: BeaconKind.post,
          createdAt: _createdAt,
          updatedAt: _createdAt,
          author: _author,
          postRootMessageId: _rootId,
        );
      };
    addTearDown(beacon.dispose);
    await registerBeaconViewHarnessGetIt(profile: _author, roomRepo: room);
    GetIt.I
      ..registerSingleton<BeaconRepository>(beacon)
      ..registerSingleton<ForwardRepository>(FakeBeaconViewForwardRepository())
      ..registerSingleton<PostsRepositoryPort>(FakeBeaconViewPostsRepository())
      ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
      ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync());

    final rootMessage = find.byWidgetPredicate(
      (widget) =>
          widget is PostRootPinCard && widget.rootMessage?.body == _rootBody,
      description: 'the Post header showing the message returned over GraphQL',
    );
    final input = find.byKey(TestIds.key(TestIds.roomMessageInput));
    final post = find.byType(PostViewScreen);
    Future<void> mountPost() async {
      await tester.pumpWidget(
        StackRouterScope(
          controller: BeaconViewHarnessRouter(),
          stateHash: 0,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: const Locale('ru'),
            home: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileCubit>.value(
                    value: GetIt.I<ProfileCubit>(),
                  ),
                  BlocProvider<PresenceCubit>(
                    create: (_) => RoomBodyHarnessPresenceCubit(),
                  ),
                  BlocProvider<ScreenCubit>(
                    create: (_) => ScreenCubit(GetIt.I<UiEffectPort>()),
                  ),
                ],
                child: const PostViewScope(id: _postId, myProfile: _author),
              ),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (rootMessage.evaluate().isNotEmpty && input.evaluate().isNotEmpty) {
          break;
        }
      }
      expect(
        rootMessage,
        findsOneWidget,
        reason: 'Room operations: ${server.queried}',
      );
      expect(input, findsOneWidget);
      expect(tester.widget<PostViewScreen>(post).id, _postId);
    }

    await mountPost();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    final firstScreen = tester.state(post);
    await tester.enterText(input, _draft);
    await tester.pump();
    expect(readBeaconRoomComposerDraft(_postId), _draft);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(firstScreen.mounted, isFalse);
    await mountPost();

    expect(tester.state(post), isNot(same(firstScreen)));
    expect(tester.widget<TextField>(input).controller!.text, _draft);
    expect(readBeaconRoomComposerDraft(_postId), _draft);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
