// Only HTTP and the native image picker are faked. The production Ferry
// client, BeaconRepository, use cases, cubits and Post composer stay in path.
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:ferry/ferry.dart'
    show Client, OperationRequest, OperationResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/build_client.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/post_publish_case.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_publish_repository.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/post_create_screen.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/forward_target_profile.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

import '../../support/phone_surface.dart';
import '../../support/post_draft_wire.dart';
import '../../support/test_forward_case.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart' show FakeBeaconImagePort, kTinyPng;

const _draftId = 'Bpostdraft001';
const _attachmentId = 'Adraftphoto01';
const _recipients = ['Urecipient001', 'Urecipient002'];
const _pause = Duration(milliseconds: 1650);

// A token fixture, rather than a cookie login: browser session auth uses
// window.fetch and deliberately does not pass through package:http mocks.
// Requests still traverse the production Ferry links and response mappers.
class _FerryRemote implements RemoteRequestClient {
  const _FerryRemote(this.client);
  final Client client;
  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => client.request(request);
  Future<void> close() => client.dispose();
}

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'Uviewer000001', displayName: 'Олег'),
  );
  @override
  Stream<ProfileState> get stream => const Stream.empty();
}

class _PresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};
  @override
  Stream<Map<String, UserPresenceStatus>> get stream => const Stream.empty();
}

class _Router extends Fake implements StackRouter {
  @override
  void pop<T extends Object?>([T? result]) {}

  @override
  String get currentUrl => '/post/new';
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
  @override
  Future<T?> popAndPush<T extends Object?, TO extends Object?>(
    PageRouteInfo route, {
    TO? result,
    OnNavigationFailure? onFailure,
  }) async => null;
  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async => null;
  @override
  void popUntilRouteWithName(String name, {bool scoped = true}) {}
  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {}
}

class _Images extends Fake implements ImageRepository {
  @override
  Future<List<ImagePicked>> pickMultipleImages() async => [
    ImagePicked(bytes: Uint8List.fromList(kTinyPng), fileName: 'photo.png'),
  ];
}

class _Clipboard extends Fake implements ClipboardImageRepository {}

class _Files extends FilePickerPlatform {
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => [_Document()];
}

final class _Document extends PlatformFile {
  @override
  String get name => 'notes.txt';
  @override
  Uri get uri => Uri.dataFromString('draft attachment');
  @override
  XFile get xFile => XFile.fromData(
    Uint8List.fromList(utf8.encode('draft attachment')),
    name: name,
  );
  @override
  Future<int> length() async => 16;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode('draft attachment'));
  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(readAsBytes());
}

typedef PostDraftComposerBody =
    Future<void> Function(
      BeaconCreateCubit cubit,
      ForwardCubit forward,
      PostDraftWire wire,
    );

Future<void> _withComposer(
  WidgetTester tester,
  PostDraftComposerBody body, {
  bool existingDraft = true,
  bool loadAfterMount = false,
}) async {
  await usePhoneSurface(tester);
  // Real async keeps the Ferry HTTP streams and the 1.5 s debounce in the
  // same clock. Every wait below is bounded, including the debounce checks.
  await tester.runAsync(
    () => http.runWithClient(
      () async {
        final wire = Zone.current[#postDraftWire] as PostDraftWire;
        final effects = FakeUiEffectPort();
        final sync = buildTestRealtimeSync();
        final remote = _FerryRemote(
          await buildClient(
            params: (
              apiEndpointUrl: 'https://draft.test/api/v1/graphql',
              apiEndpointUrlV2: 'https://draft.test/api/v2/graphql',
              userAgent: 'post-draft-test',
              requestTimeout: const Duration(seconds: 3),
            ),
            getToken: () async => 'test-token',
          ),
        );
        final beacons = BeaconRepository(remote, sync.port);
        final forwards = ForwardRepository(remote, beacons, sync.port);
        final forwardCase = buildTestForwardCase(forwards);
        final load = await forwardCase.loadForwardCandidates(
          beaconId: '',
          isPost: true,
        );
        final forward = ForwardCubit(
          beaconId: _draftId,
          embedded: true,
          forwardCase: forwardCase,
          effects: effects,
          debugSkipInitialLoad: true,
          debugInitialState: ForwardState(
            beaconId: _draftId,
            candidates: load.candidates,
            targetProfile: ForwardTargetProfile.post,
            candidatesLoad: const ForwardCandidatesReady(),
          ),
        );
        final cubit = BeaconCreateCubit(
          kind: BeaconKind.post,
          beaconCreateCase: BeaconCreateCase(beacons, FakeBeaconImagePort()),
          postPublishCase: PostPublishCase(PostPublishRepository(remote)),
          effects: effects,
        );
        GetIt.I
          ..registerSingleton<UiEffectPort>(effects)
          ..registerSingleton<ImageRepository>(_Images())
          ..registerSingleton<ClipboardImageRepository>(_Clipboard());
        if (existingDraft && !loadAfterMount) {
          await cubit.loadDraft(_draftId).timeout(const Duration(seconds: 3));
          // Fixture sanity: fail here only if the transport/mapper setup is broken.
          expect(cubit.state.draftId, _draftId);
          expect(cubit.state.description, 'hello');
          expect(effects.emitted.whereType<ShowError>(), isEmpty);
        }
        final router = _Router();
        try {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ru'),
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
                        BlocProvider<ProfileCubit>.value(
                          value: _ProfileCubit(),
                        ),
                        BlocProvider<PresenceCubit>.value(
                          value: _PresenceCubit(),
                        ),
                        BlocProvider<ScreenCubit>(
                          create: (_) => ScreenCubit.local(effects),
                        ),
                      ],
                      child: const PostCreateScreen(),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          if (existingDraft && loadAfterMount) {
            await cubit.loadDraft(_draftId).timeout(const Duration(seconds: 3));
            await tester.pump();
            expect(cubit.state.draftId, _draftId);
            expect(cubit.state.description, 'hello');
            expect(effects.emitted.whereType<ShowError>(), isEmpty);
          }
          await body(cubit, forward, wire).timeout(const Duration(seconds: 15));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await cubit.close();
          await forward.close();
          await forwards.dispose();
          await beacons.dispose();
          await sync.port.dispose();
          await remote.close();
          await GetIt.I.reset();
        }
      },
      () => MockClient(
        (request) =>
            (Zone.current[#postDraftWire] as PostDraftWire).respond(request),
      ),
    ),
  );
}

Future<void> withServerPostComposer(
  WidgetTester tester,
  PostDraftComposerBody body, {
  bool existingDraft = true,
  int policy = 1,
  int lifetimeHours = 72,
  bool restoreAttachments = false,
  bool loadAfterMount = false,
}) => runZoned(
  () => _withComposer(
    tester,
    body,
    existingDraft: existingDraft,
    loadAfterMount: loadAfterMount,
  ),
  zoneValues: {
    #postDraftWire: PostDraftWire()
      ..policy = policy
      ..lifetimeHours = lifetimeHours
      ..draftAttachments = restoreAttachments ? restoredPostAttachments() : [],
  },
);

Future<void> _pauseForSave(WidgetTester tester) async {
  await Future<void>.delayed(
    _pause,
  ).timeout(const Duration(milliseconds: 1900));
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 12,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

Future<void> _chooseLifetime(WidgetTester tester, int hours) async {
  final label = find.text(hours == 6 ? '6 часов' : '24 часа');
  await _reveal(tester, label);
  await tester.tap(label);
  await tester.pump();
  expect(
    tester
        .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
        .selected,
    {hours},
  );
}

Future<void> _toggleForwarding(WidgetTester tester) async {
  final toggle = find.byType(SwitchListTile);
  await _reveal(tester, toggle);
  final before = tester.widget<SwitchListTile>(toggle).value;
  await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
  await tester.pump();
  expect(tester.widget<SwitchListTile>(toggle).value, !before);
  await tester.pump();
}

Future<void> _pickPhoto(WidgetTester tester, {int expectedPreviews = 1}) async {
  final photo = find.byIcon(Icons.photo_outlined);
  await tester.ensureVisible(photo);
  await tester.tap(photo);
  // Allow picker and in-memory HTTP work, but stay below the text debounce.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await tester.pump();
  expect(
    find.byType(PendingAttachmentPreview),
    findsNWidgets(expectedPreviews),
  );
}

String? savedAttachmentId(RoomPendingUpload upload) => upload.attachmentId;

void _expectUpdate(
  PostDraftWire wire, {
  required String body,
  int policy = 1,
  int hours = 72,
  Duration? since,
}) {
  final updates = wire.calls('PostUpdateDraft');
  expect(
    updates,
    hasLength(1),
    reason: 'the composer must save the server Post draft',
  );
  if (since != null) {
    expect(
      (wire.receivedAt[updates.single]! - since).inMilliseconds,
      greaterThanOrEqualTo(1500),
      reason: 'the debounce cannot save early',
    );
  }
  final vars = updates.single.variables;
  // GraphQL variables may call the Post id `id` or `beaconId`; the API
  // argument is `id`, unlike the draft upload's `beaconId` argument.
  expect(vars['beaconId'] ?? vars['id'], _draftId);
  expect(vars['body'], body);
  expect(vars['forwardPolicy'], policy);
  expect(vars['lifetimeHours'], hours);
}

void main() {
  group('Post draft autosave through the real transport', () {
    testWidgets('typing saves only the final body after a 1.5 second pause', (
      tester,
    ) async {
      await withServerPostComposer(tester, (cubit, forward, wire) async {
        final field = find.byKey(PostCreateScreen.textFieldKey);
        for (final text in ['h', 'he']) {
          await tester.enterText(field, text);
          await Future<void>.delayed(const Duration(milliseconds: 70));
        }
        await tester.enterText(field, 'hello world');
        // Start at completion of the final text input, never before it or
        // before an artificial inter-keystroke delay.
        final lastInputAt = wire.clock.elapsed;
        await (() async {
          while (wire.clock.elapsed - lastInputAt <
              const Duration(milliseconds: 1500)) {
            expect(
              wire.calls('PostUpdateDraft'),
              isEmpty,
              reason:
                  'no save during the first 1.5 seconds after the final input',
            );
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
          _expectUpdate(wire, body: 'hello world', since: lastInputAt);
        })().timeout(const Duration(milliseconds: 1800));
        expect(wire.calls('BeaconCreate'), isEmpty);
      });
    });

    for (final open in [false, true]) {
      testWidgets(
        'changing forwarding to ${open ? 'open' : 'closed'} saves body and lifetime',
        (tester) async {
          await withServerPostComposer(tester, (cubit, forward, wire) async {
            await tester.enterText(
              find.byKey(PostCreateScreen.textFieldKey),
              'current body',
            );
            await _pauseForSave(tester);
            wire.sent.clear();
            await _toggleForwarding(tester);
            if (open) {
              await _pauseForSave(tester);
              _expectUpdate(wire, body: 'current body', policy: 0);
              wire.sent.clear();
              await _toggleForwarding(tester);
            }
            expect(wire.calls('PostUpdateDraft'), isEmpty);
            await _pauseForSave(tester);
            _expectUpdate(wire, body: 'current body', policy: open ? 1 : 0);
          });
        },
      );
    }

    for (final hours in [24, 6]) {
      testWidgets(
        'choosing $hours hours saves the draft lifetime with its current body',
        (tester) async {
          await withServerPostComposer(tester, (cubit, forward, wire) async {
            await tester.enterText(
              find.byKey(PostCreateScreen.textFieldKey),
              'current body',
            );
            await _pauseForSave(tester);
            wire.sent.clear();
            await _chooseLifetime(tester, hours);
            expect(wire.calls('PostUpdateDraft'), isEmpty);
            await _pauseForSave(tester);
            _expectUpdate(wire, body: 'current body', hours: hours);
          });
        },
      );
    }
  });

  group('Post draft attachments in the shared preview strip', () {
    for (final existing in [false, true]) {
      testWidgets(
        'picking a photo ${existing ? 'reuses the draft' : 'creates a Post draft first'} and uploads immediately',
        (tester) async {
          await withServerPostComposer(tester, (cubit, forward, wire) async {
            await _pickPhoto(tester);
            final item = tester
                .widget<PendingAttachmentPreview>(
                  find.byType(PendingAttachmentPreview),
                )
                .upload;
            expect(
              savedAttachmentId(item),
              _attachmentId,
              reason:
                  'the strip item must retain its returned server id before removal',
            );
            final adds = wire.calls('PostDraftAttachmentAdd');
            expect(
              adds,
              hasLength(1),
              reason:
                  'picked photos must reach the server before publish or the text debounce',
            );
            expect(
              adds.single.variables['draftBeaconId'] ??
                  adds.single.variables['beaconId'],
              _draftId,
            );
            expect(wire.calls('BeaconCreate'), hasLength(existing ? 0 : 1));
            if (!existing) {
              final create = wire.calls('BeaconCreate').single;
              expect(create.variables['kind'], 1);
              expect(create.variables['draft'], isTrue);
              expect(
                wire.sent.indexOf(create),
                lessThan(wire.sent.indexOf(adds.single)),
              );
            }
            expect(
              wire.multipartBodies.single,
              contains('filename="photo.png"'),
            );
            expect(
              wire.multipartBodies.single,
              contains(utf8.decode(kTinyPng, allowMalformed: true)),
            );
            expect(wire.calls('PostPublish'), isEmpty);
          }, existingDraft: existing);
        },
      );
    }

    testWidgets(
      'an uploaded photo keeps its server identity in the preview before removal',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          await _pickPhoto(tester);
          final preview = tester.widget<PendingAttachmentPreview>(
            find.byType(PendingAttachmentPreview),
          );
          expect(preview.upload.fileName, 'photo.png');
          expect(
            savedAttachmentId(preview.upload),
            _attachmentId,
            reason:
                'the pending attachment model must retain the server-returned identity',
          );
        });
      },
    );

    testWidgets(
      'picking a document uploads its bytes into the existing Post draft',
      (tester) async {
        final previous = FilePickerPlatform.instance;
        FilePickerPlatform.instance = _Files();
        addTearDown(() => FilePickerPlatform.instance = previous);
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          final files = find.byIcon(Icons.attach_file_rounded);
          await _reveal(tester, files);
          await tester.tap(files);
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
          expect(find.byType(PendingAttachmentPreview), findsOneWidget);
          expect(find.text('notes.txt'), findsOneWidget);
          final adds = wire.calls('PostDraftAttachmentAdd');
          expect(
            adds,
            hasLength(1),
            reason:
                'documents must be saved on the draft as soon as they are picked',
          );
          expect(
            adds.single.variables['draftBeaconId'] ??
                adds.single.variables['beaconId'],
            _draftId,
          );
          expect(
            savedAttachmentId(
              tester
                  .widget<PendingAttachmentPreview>(
                    find.byType(PendingAttachmentPreview),
                  )
                  .upload,
            ),
            _attachmentId,
            reason:
                'the document preview retains the saved attachment identity',
          );
          expect(wire.multipartBodies.single, contains('filename="notes.txt"'));
          expect(wire.multipartBodies.single, contains('draft attachment'));
          expect(wire.calls('BeaconCreate'), isEmpty);
          expect(wire.calls('PostPublish'), isEmpty);
        });
      },
    );

    testWidgets(
      'removing a picked photo removes its returned server attachment id',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          await _pickPhoto(tester);
          final preview = tester.widget<PendingAttachmentPreview>(
            find.byType(PendingAttachmentPreview),
          );
          expect(preview.onRemove, isNotNull);
          await _reveal(tester, find.byType(PendingAttachmentPreview));
          await tester.tap(
            find.descendant(
              of: find.byType(PendingAttachmentPreview),
              matching: find.byTooltip('Удалить'),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
          expect(find.byType(PendingAttachmentPreview), findsNothing);
          final removes = wire.calls('PostDraftAttachmentRemove');
          expect(
            removes,
            hasLength(1),
            reason:
                'removing the preview must remove the uploaded server file too',
          );
          expect(wire.addedIds, [_attachmentId]);
          expect(
            removes.single.variables['draftBeaconId'] ??
                removes.single.variables['beaconId'],
            _draftId,
          );
          expect(removes.single.variables['attachmentId'], _attachmentId);
        });
      },
    );
  });

  group('Opening and publishing a server Post draft', () {
    testWidgets(
      'loading a draft fills the Post text field from the server body',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          expect(
            tester
                .widget<TextField>(find.byKey(PostCreateScreen.textFieldKey))
                .controller!
                .text,
            'hello',
          );
          expect(wire.calls('PostPublish'), isEmpty);
        });
      },
    );

    testWidgets(
      'loading a closed forward policy turns off forwarding before publish',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          await _reveal(tester, find.byType(SwitchListTile));
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isFalse,
          );
          expect(wire.calls('PostPublish'), isEmpty);
        }, policy: 0);
      },
    );

    testWidgets(
      'loading a server draft restores both files in the existing preview strip',
      (tester) async {
        await withServerPostComposer(
          tester,
          (cubit, forward, wire) async {
            expect(wire.draftAttachments, hasLength(2));
            // The phone form is a lazy ListView: reveal the attachments'
            // section before counting its rendered previews.
            await _reveal(tester, find.byType(SegmentedButton<int>));
            expect(find.byType(PendingAttachmentPreview), findsNWidgets(2));
            expect(find.text('saved-1.txt'), findsOneWidget);
            expect(find.text('saved-2.txt'), findsOneWidget);
            await _pickPhoto(tester, expectedPreviews: 3);
            expect(
              find.byType(PendingAttachmentPreview),
              findsNWidgets(3),
              reason:
                  'picked and restored items use the same production preview strip',
            );
          },
          policy: 0,
          lifetimeHours: 6,
          restoreAttachments: true,
          loadAfterMount: true,
        );
      },
    );

    testWidgets(
      'loading a server draft selects its saved six hour lifetime before publish',
      (tester) async {
        await withServerPostComposer(
          tester,
          (cubit, forward, wire) async {
            await _reveal(tester, find.byType(SegmentedButton<int>));
            expect(
              tester
                  .widget<SegmentedButton<int>>(
                    find.byType(SegmentedButton<int>),
                  )
                  .selected,
              {6},
            );
            expect(wire.calls('PostPublish'), isEmpty);
          },
          policy: 0,
          lifetimeHours: 6,
          restoreAttachments: true,
          loadAfterMount: true,
        );
      },
    );

    testWidgets(
      'loading a complete server draft restores body files forwarding and lifetime together',
      (tester) async {
        await withServerPostComposer(
          tester,
          (cubit, forward, wire) async {
            final body = tester
                .widget<TextField>(find.byKey(PostCreateScreen.textFieldKey))
                .controller!
                .text;
            await _reveal(tester, find.byType(SegmentedButton<int>));
            final previews = tester
                .widgetList<PendingAttachmentPreview>(
                  find.byType(PendingAttachmentPreview),
                )
                .toList();
            final selected = tester
                .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
                .selected;
            await _reveal(tester, find.byType(SwitchListTile));
            expect(
              {
                'body': body,
                'files': [
                  for (final preview in previews) preview.upload.fileName,
                ],
                'canForward': tester
                    .widget<SwitchListTile>(find.byType(SwitchListTile))
                    .value,
                'lifetime': selected,
              },
              {
                'body': 'hello',
                'files': ['saved-1.txt', 'saved-2.txt'],
                'canForward': false,
                'lifetime': {6},
              },
            );
            expect(wire.calls('PostPublish'), isEmpty);
          },
          policy: 0,
          lifetimeHours: 6,
          restoreAttachments: true,
          loadAfterMount: true,
        );
      },
    );

    testWidgets(
      'make live publishes once without recipients using the chosen settings',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          await tester.enterText(
            find.byKey(PostCreateScreen.textFieldKey),
            'ready to publish',
          );
          await _chooseLifetime(tester, 6);
          await _toggleForwarding(tester);
          await _pauseForSave(tester);
          await cubit.makeLive(context: '').timeout(const Duration(seconds: 3));
          final publishes = wire.calls('PostPublish');
          expect(
            publishes,
            hasLength(1),
            reason:
                'Post makeLive must use postPublish rather than Request publication',
          );
          expect(
            publishes.single.variables['id'] ??
                publishes.single.variables['beaconId'],
            _draftId,
          );
          expect(publishes.single.variables['body'], 'ready to publish');
          expect(publishes.single.variables['recipientIds'], isEmpty);
          expect(publishes.single.variables['forwardPolicy'], 0);
          expect(publishes.single.variables['lifetimeHours'], 6);
          expect(cubit.state.isLive, isTrue);
          expect(wire.calls('ForwardBeacon'), isEmpty);
          await cubit.makeLive(context: '').timeout(const Duration(seconds: 3));
          expect(wire.calls('PostPublish'), hasLength(1));
        });
      },
    );

    testWidgets(
      'make live preserves the closed policy and six hour lifetime loaded from the server',
      (tester) async {
        await withServerPostComposer(
          tester,
          (cubit, forward, wire) async {
            // No text, toggle or picker edit is made after loadDraft. Publication
            // must use the server's saved values, not the form's defaults.
            await cubit
                .makeLive(context: '')
                .timeout(const Duration(seconds: 3));
            final publishes = wire.calls('PostPublish');
            expect(publishes, hasLength(1));
            final vars = publishes.single.variables;
            expect(vars['beaconId'] ?? vars['id'], 'Bpostdraft001');
            expect(vars['body'], 'hello');
            expect(vars['recipientIds'], isEmpty);
            expect(vars['forwardPolicy'], 0);
            expect(vars['lifetimeHours'], 6);
            expect(cubit.state.isLive, isTrue);
            expect(wire.calls('ForwardBeacon'), isEmpty);
          },
          policy: 0,
          lifetimeHours: 6,
          restoreAttachments: true,
          loadAfterMount: true,
        );
      },
    );

    testWidgets(
      'Send after make live forwards to both selected people without republishing',
      (tester) async {
        await withServerPostComposer(tester, (cubit, forward, wire) async {
          await tester.enterText(
            find.byKey(PostCreateScreen.textFieldKey),
            'ready to send',
          );
          await cubit.makeLive(context: '').timeout(const Duration(seconds: 3));
          expect(cubit.state.isLive, isTrue);
          final beforeSend = wire.calls('PostPublish').length;
          for (final id in _recipients) {
            expect(
              forward.toggleSelection(id),
              ForwardSelectionResult.selected,
            );
          }
          await tester.pump();
          await tester.tap(find.byKey(PostCreateScreen.nextButtonKey));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          final send = find.text('Отправить (2)');
          await tester.ensureVisible(send);
          await tester.tap(send);
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
          final deliveries = wire.calls('ForwardBeacon');
          expect(
            deliveries,
            hasLength(1),
            reason: 'a live Post must be sent with ForwardCubit.forward',
          );
          expect(deliveries.single.variables['beaconId'], _draftId);
          expect(
            deliveries.single.variables['recipientIds'],
            unorderedEquals(_recipients),
          );
          expect(
            wire.calls('PostPublish'),
            hasLength(1),
            reason: 'makeLive publishes once and Send only forwards',
          );
          expect(wire.calls('PostPublish'), hasLength(beforeSend));
          expect(
            forward.state.lastDeliveryOutcome?.deliveredRecipientIds,
            unorderedEquals(_recipients),
          );
        });
      },
    );
  });
}
