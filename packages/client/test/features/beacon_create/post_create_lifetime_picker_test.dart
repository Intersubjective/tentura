// The Post composer lets the author pick how long the Post stays open:
// «6 часов» … «3 дня» (default «3 дня»). The choice is sent to
// `postPublish` as `lifetime`. A hint — «Потом пост уйдёт в архив. Продлить
// нельзя, сократить можно.» — sits directly above the «Можно пересылать»
// switch.
// UI copy is asserted verbatim in Russian.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _viewer = Profile(id: 'Uviewer', displayName: 'Олег');

const _hint = 'Потом пост уйдёт в архив. Продлить нельзя, сократить можно.';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _LifetimeRecordingPort implements PostPublishPort {
  /// `lifetime` of every `postPublish` call, in order.
  final lifetimes = <Duration?>[];

  @override
  Future<PostPublishResult> postPublish({
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    required BeaconForwardPolicyValue forwardPolicy,
    Duration? lifetime,
    RoomPendingUpload? attachment,
  }) async {
    lifetimes.add(lifetime);
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-1');
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {}
}

class _NavRouter extends Fake implements StackRouter {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<dynamic>.value();

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_LifetimeRecordingPort> _pumpPostCreate(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final effects = FakeUiEffectPort();
  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);
  getIt
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ProfileCubit>(_ProfileCubit())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

  final port = _LifetimeRecordingPort();
  final cubit = BeaconCreateCubit(
    kind: BeaconKind.post,
    beaconCreateCase: fakeBeaconCreateCase(write: FakeBeaconWritePort()),
    postPublishCase: PostPublishCase(port),
    effects: effects,
  );
  addTearDown(cubit.close);
  final forward = ForwardCubit(
    beaconId: '',
    embedded: true,
    effects: effects,
    debugSkipInitialLoad: true,
    debugInitialState: const ForwardState(
      beaconId: '',
      selectedIds: {'Umaria'},
      candidatesLoad: ForwardCandidatesReady(),
    ),
  );
  addTearDown(forward.close);

  final router = _NavRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(
                  value: GetIt.I<ProfileCubit>(),
                ),
                BlocProvider<PresenceCubit>.value(value: _PresenceCubit()),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit(effects),
                ),
                BlocProvider<BeaconCreateCubit>.value(value: cubit),
                BlocProvider<ForwardCubit>.value(value: forward),
              ],
              child: const PostCreateScreen(),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return port;
}

/// Writes the Post, goes to the recipients step and presses «Отправить (1)».
Future<void> _writeAndSend(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(PostCreateScreen.textFieldKey),
    'Кто в субботу на велопрогулку?',
  );
  await _settle(tester);
  await tester.tap(find.byKey(PostCreateScreen.nextButtonKey));
  await _settle(tester);
  await tester.tap(find.text('Отправить (1)'));
  await _settle(tester);
}

void main() {
  group('Post lifetime picker', () {
    testWidgets('publishes with a 72 hour lifetime by default', (tester) async {
      final port = await _pumpPostCreate(tester);

      await _writeAndSend(tester);

      expect(port.lifetimes, [const Duration(hours: 72)]);
    });

    testWidgets('choosing «6 часов» publishes with a 6 hour lifetime', (
      tester,
    ) async {
      final port = await _pumpPostCreate(tester);

      await tester.tap(find.text('6 часов'));
      await _settle(tester);
      await _writeAndSend(tester);

      expect(port.lifetimes, [const Duration(hours: 6)]);
    });

    testWidgets('explains that the Post then goes to the archive', (
      tester,
    ) async {
      await _pumpPostCreate(tester);

      expect(find.text(_hint), findsOneWidget);
    });

    testWidgets('the picker is a segmented button above its hint', (
      tester,
    ) async {
      await _pumpPostCreate(tester);

      final picker = find.byWidgetPredicate((w) => w is SegmentedButton);
      expect(picker, findsOneWidget);
      expect(
        find.descendant(of: picker, matching: find.text('6 часов')),
        findsOneWidget,
      );
      expect(find.text(_hint), findsOneWidget);
      expect(
        tester.getBottomLeft(picker).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text(_hint)).dy),
      );
    });

    testWidgets('the hint sits directly above the «Можно пересылать» switch', (
      tester,
    ) async {
      await _pumpPostCreate(tester);

      final hint = find.text(_hint);
      final tile = find.ancestor(
        of: find.text('Можно пересылать'),
        matching: find.byType(SwitchListTile),
      );
      expect(hint, findsOneWidget);
      final gap = tester.getTopLeft(tile).dy - tester.getBottomLeft(hint).dy;
      expect(gap, greaterThanOrEqualTo(0), reason: 'the hint is above');
      expect(
        gap,
        lessThanOrEqualTo(16),
        reason: 'no other control sits between the hint and the switch',
      );
    });
  });
}
