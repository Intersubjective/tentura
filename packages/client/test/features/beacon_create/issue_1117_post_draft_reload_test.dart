import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/unsaved_changes_guard_impl.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/port/post_publish_port.dart';
import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon_create/data/service/post_create_composer_draft_store.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'Uviewer', displayName: 'Олег'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);

  @override
  bool get isClosed => false;

  @override
  Future<void> close() async {}
}

class _UrlRouter extends Fake implements StackRouter {
  _UrlRouter(this._url);

  final String _url;
  final marks = <String>[];

  @override
  String get currentUrl => _url;

  @override
  void markUrlStateForReplace() => marks.add('mark');

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

class _EmptyClipboard extends Fake implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

class _NoopPostPublishPort implements PostPublishPort {
  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {}

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
  }) async => PostPublishResult(beaconId: beaconId, rootMessageId: 'root-1');
}

const _longRuBody =
    'Длинный текст нового поста на русском, который не должен '
    'обрезаться при переносе строк на узком экране телефона.';

Future<void> _pumpPostCreate(
  WidgetTester tester, {
  required BeaconCreateCubit cubit,
  required _UrlRouter router,
  String draftId = '',
}) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(375, 667)),
        child: TenturaResponsiveScope(
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                  BlocProvider(
                    create: (_) => ForwardCubit(
                      beaconId: '',
                      embedded: true,
                      debugSkipInitialLoad: true,
                    ),
                  ),
                  BlocProvider<ProfileCubit>.value(
                    value: _ProfileCubit(),
                  ),
                ],
                child: PostCreateScreen(draftId: draftId),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    clearPostCreateComposerDraft();
    GetIt.I
      ..registerSingleton<UnsavedChangesGuardPort>(UnsavedChangesGuard())
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        _EmptyClipboard(),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
    clearPostCreateComposerDraft();
  });

  group('issue #1117 post draft reload', () {
    testWidgets(
      'typing persists to session storage and stamps draft_id in the URL',
      (tester) async {
        final reports = <Map<Object?, Object?>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          (call) async {
            if (call.method == 'routeInformationUpdated') {
              reports.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.navigation,
            null,
          ),
        );

        final write = FakeBeaconWritePort();
        final cubit = BeaconCreateCubit(
          kind: BeaconKind.post,
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          postPublishCase: PostPublishCase(_NoopPostPublishPort()),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        final router = _UrlRouter(kPathPostNew);

        await _pumpPostCreate(tester, cubit: cubit, router: router);
        await tester.enterText(
          find.byKey(PostCreateScreen.textFieldKey),
          _longRuBody,
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        final snap = readPostCreateComposerDraft();
        expect(snap?.body, _longRuBody);
        expect(cubit.state.draftId, isNotNull);

        final draftReports = reports
            .where((r) => r['uri'].toString().contains(kQueryBeaconDraftId))
            .toList();
        expect(draftReports, isNotEmpty);
        expect(find.text(_longRuBody), findsWidgets);

        final fieldSize = tester.getSize(
          find.byKey(PostCreateScreen.textFieldKey),
        );
        expect(fieldSize.width, lessThanOrEqualTo(375));
      },
    );

    testWidgets(
      'simulated reload restores long RU body from session storage',
      (tester) async {
        writePostCreateComposerDraft(
          draftId: 'server-beacon',
          body: _longRuBody,
        );

        final write = FakeBeaconWritePort(
          beacon: Beacon.empty.copyWith(
            id: 'server-beacon',
            status: BeaconStatus.draft,
            kind: BeaconKind.post,
          ),
        );
        final cubit = BeaconCreateCubit(
          kind: BeaconKind.post,
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          postPublishCase: PostPublishCase(_NoopPostPublishPort()),
          effects: FakeUiEffectPort(),
          draftBeaconIdToLoad: 'server-beacon',
        );
        addTearDown(cubit.close);
        final router = _UrlRouter(
          '$kPathPostNew?$kQueryBeaconDraftId=server-beacon',
        );

        await _pumpPostCreate(
          tester,
          cubit: cubit,
          router: router,
          draftId: 'server-beacon',
        );
        await tester.pumpAndSettle();

        expect(find.text(_longRuBody), findsWidgets);
        expect(cubit.hasUnpersistedEdits, isTrue);
      },
    );
  });
}
