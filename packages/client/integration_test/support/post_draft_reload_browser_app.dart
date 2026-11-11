// Test-only entrypoint for the Playwright document-reload journey. Only the
// token/profile/realtime fixtures are doubled. Ferry, HTTP, draft mapping,
// BeaconCreateCubit, file_picker and PostCreateScreen are production code.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_publish_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

import '../../test/support/test_realtime_sync.dart';
import '../../test/ui/effect/fake_ui_effect_port.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.toString());
    FlutterError.presentError(details);
  };
  final origin = Uri.base.origin;
  final remote = _Remote(
    await buildClient(
      params: (
        apiEndpointUrl: '$origin/api/v1/graphql',
        apiEndpointUrlV2: '$origin/api/v2/graphql',
        userAgent: 'post-draft-browser-test',
        requestTimeout: const Duration(seconds: 5),
      ),
      getToken: () async => 'author-test-token',
    ),
  );
  final sync = buildTestRealtimeSync();
  final beacons = BeaconRepository(remote, sync.port);
  final images = ImageRepository();
  final effects = FakeUiEffectPort();
  GetIt.I
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<ImageRepository>(images)
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final draftId = Uri.base.queryParameters['draft_id'] ?? '';
  final cubit = BeaconCreateCubit(
    kind: BeaconKind.post,
    beaconCreateCase: BeaconCreateCase(beacons, images),
    postPublishCase: PostPublishCase(PostPublishRepository(remote)),
    draftBeaconIdToLoad: draftId.isEmpty ? null : draftId,
    effects: effects,
  );
  final forward = ForwardCubit(
    beaconId: draftId,
    embedded: true,
    debugSkipInitialLoad: true,
    effects: effects,
  );
  final router = _Router();
  runApp(
    MaterialApp(
      locale: const Locale('ru'),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: TenturaResponsiveScope(
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
                BlocProvider<ForwardCubit>.value(value: forward),
                BlocProvider<ProfileCubit>.value(value: _Profile()),
                BlocProvider<PresenceCubit>.value(value: _Presence()),
                BlocProvider<ScreenCubit>(
                  create: (_) => ScreenCubit.local(effects),
                ),
              ],
              child: PostCreateScreen(draftId: draftId),
            ),
          ),
        ),
      ),
    ),
  );

  // Read-only inspection of the actual rendered production widgets. The
  // Playwright test changes values only via browser typing, clicks and file
  // selection; this hook never seeds or changes composer state.
  globalContext['postDraftComposerSnapshot'] = (() {
    final result = <String, Object?>{
      'files': <String>[],
      'draftId': cubit.state.draftId,
      'errors': errors,
    };
    void visit(Element element) {
      final widget = element.widget;
      if (widget is TextField && widget.key == PostCreateScreen.textFieldKey) {
        result['body'] = widget.controller!.text;
      } else if (widget is PendingAttachmentPreview) {
        (result['files']! as List<String>).add(widget.upload.fileName);
      } else if (widget is SwitchListTile) {
        result['canForward'] = widget.value;
      } else if (widget is SegmentedButton<int>) {
        result['lifetimeHours'] = widget.selected.single;
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return jsonEncode(result).toJS;
  }).toJS;
}

class _Remote implements RemoteRequestClient {
  const _Remote(this.client);
  final Client client;
  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => client.request(request);
}

class _Profile extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'Uviewer000001', displayName: 'Олег'),
  );
  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _Presence extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};
  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Router extends Fake implements StackRouter {
  @override
  String get currentUrl => Uri.base.toString();
  @override
  void markUrlStateForReplace() {}
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}
