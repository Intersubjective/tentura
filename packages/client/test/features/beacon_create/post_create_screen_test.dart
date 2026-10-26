// «Новый пост» is a two-step form, like a simplified Request form. Step one:
// ✕ + «Новый пост», the text field, «Фото» / «Файлы» / «Вставить изображение»
// and the «Можно пересылать» switch (on by default); «Далее: получатели»
// stays disabled until there is text or an attachment. Step two,
// «Получатели»: the recipient picker on the shared ForwardCubit, whose
// «Отправить (N)» publishes the Post once someone is chosen. Closing an
// untouched screen makes no server call, closing one with content asks
// «Удалить черновик?» first.
// UI copy is asserted verbatim in Russian.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
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
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/features/forward/ui/widget/per_recipient_note_input.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

const _viewer = Profile(id: 'Uviewer', displayName: 'Олег');

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

class _RecordingPostPublishPort implements PostPublishPort {
  final bodies = <String>[];
  final recipients = <Set<String>>[];
  final policies = <BeaconForwardPolicyValue>[];

  /// File name of the inline attachment per call (null when none).
  final inlineAttachments = <String?>[];

  /// Every call flattened to one comparable string, to prove retries are
  /// identical.
  final signatures = <String>[];

  /// Names uploaded into the root message after publish, in order.
  final uploads = <String>[];

  /// Errors thrown by successive `postPublish` calls (null = success).
  final publishErrors = <Exception?>[];

  /// File names whose next upload fails once.
  final failUploadOnce = <String>{};

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
    bodies.add(body);
    recipients.add(recipientIds.toSet());
    policies.add(forwardPolicy);
    inlineAttachments.add(attachment?.fileName);
    signatures.add(
      '$beaconId|$body|${(recipientIds.toList()..sort()).join(',')}|'
      '${forwardPolicy.name}|${attachment?.fileName}',
    );
    final index = signatures.length - 1;
    if (index < publishErrors.length && publishErrors[index] != null) {
      throw publishErrors[index]!;
    }
    return PostPublishResult(beaconId: beaconId, rootMessageId: 'root-1');
  }

  @override
  Future<void> addRootAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    uploads.add(upload.fileName);
    if (failUploadOnce.remove(upload.fileName)) {
      throw Exception('upload of ${upload.fileName} failed');
    }
  }
}

/// Clipboard that always holds one pasteable image, so a test can attach a
/// photo to the composer with Ctrl+V and no file picker. Successive pastes
/// yield `photo-1.png`, `photo-2.png`, …
class _PhotoClipboard extends Fake implements ClipboardImageRepository {
  int _pastes = 0;

  @override
  Future<ClipboardImageReadResult> readImage() async =>
      ClipboardImageReadResult.found(
        RoomPendingUpload(
          bytes: Uint8List.fromList(kTinyPng),
          fileName: 'photo-${++_pastes}.png',
          mimeType: 'image/png',
        ),
      );
}

/// Lets the screen's close control pop the pushed route, like the real stack.
class _NavRouter extends Fake implements StackRouter {
  late BuildContext host;
  int maybePopCalls = 0;

  /// Every other router call (push, replace, navigate…), as text.
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}:${invocation.positionalArguments}');
    return Future<dynamic>.value();
  }

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    maybePopCalls++;
    if (maybePopCalls > 3) return false;
    return Navigator.of(host).maybePop(result);
  }
}

class _Harness {
  _Harness({
    required this.write,
    required this.port,
    required this.cubit,
    required this.forward,
    required this.effects,
    required this.router,
  });

  final FakeBeaconWritePort write;
  final _RecordingPostPublishPort port;
  final BeaconCreateCubit cubit;
  final ForwardCubit forward;
  final FakeUiEffectPort effects;
  final _NavRouter router;

  /// Where the screen sent the user, as text: pushed effects and router calls.
  String get navigations => [
    for (final e in effects.emitted.whereType<NavigatePush>()) e.path,
    ...router.calls,
  ].join(' ');
}

Future<_Harness> _pumpPostCreate(
  WidgetTester tester, {
  Set<String> recipients = const {},
  void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
}) async {
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
    ..registerSingleton<ClipboardImageRepository>(_PhotoClipboard());

  final write = FakeBeaconWritePort();
  final port = _RecordingPostPublishPort();
  final cubit = BeaconCreateCubit(
    kind: BeaconKind.post,
    beaconCreateCase: fakeBeaconCreateCase(write: write),
    postPublishCase: PostPublishCase(port),
    effects: effects,
  );
  addTearDown(cubit.close);
  final forward = ForwardCubit(
    beaconId: '',
    embedded: true,
    effects: effects,
    debugSkipInitialLoad: true,
    debugInitialState: ForwardState(
      selectedIds: recipients,
      candidatesLoad: const ForwardCandidatesReady(),
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
      home: Builder(
        builder: (homeContext) => TextButton(
          onPressed: () {
            Navigator.of(homeContext).push<void>(
              MaterialPageRoute<void>(
                builder: (routeContext) {
                  router.host = routeContext;
                  return RouterScope(
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
                            BlocProvider<PresenceCubit>.value(
                              value: _PresenceCubit(),
                            ),
                            BlocProvider<ScreenCubit>(
                              create: (_) => ScreenCubit(effects),
                            ),
                            BlocProvider<BeaconCreateCubit>.value(
                              value: cubit,
                            ),
                            BlocProvider<ForwardCubit>.value(value: forward),
                          ],
                          child: PostCreateScreen(
                            onRecipientsChanged: onRecipientsChanged,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
          child: const Text('open-post-create'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-post-create'));
  await _settle(tester);
  return _Harness(
    write: write,
    port: port,
    cubit: cubit,
    forward: forward,
    effects: effects,
    router: router,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _textField => find.byKey(PostCreateScreen.textFieldKey);

Finder get _nextButton => find.byKey(PostCreateScreen.nextButtonKey);

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_nextButton).onPressed != null;

/// «Отправить (N)» on the recipients step.
Finder _sendButton(int count) => find.text('Отправить ($count)');

/// Attaches the clipboard photo to the Post with Ctrl+V in the text field.
Future<void> _pastePhoto(
  WidgetTester tester, {
  int expectedPreviews = 1,
}) async {
  await tester.tap(_textField);
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _settle(tester);
  expect(
    find.descendant(
      of: find.byType(PendingAttachmentPreview),
      matching: find.byType(Image),
    ),
    findsNWidgets(expectedPreviews),
    reason: 'the pasted photo is a pending attachment',
  );
}

/// «Далее: получатели».
Future<void> _goToRecipients(WidgetTester tester) async {
  await tester.tap(_nextButton);
  await _settle(tester);
  expect(find.byType(ForwardRecipientPicker), findsOneWidget);
}

/// Steps to «Получатели» and presses «Отправить ([count])».
Future<void> _send(WidgetTester tester, {required int count}) async {
  await _goToRecipients(tester);
  await tester.tap(_sendButton(count));
  await _settle(tester);
}

/// Gives the screen time to persist a server draft for freshly added content.
Future<void> _letDraftSave(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
}

Finder get _closeControl => find.descendant(
  of: find.byType(TenturaTopBar),
  matching: find.byIcon(Icons.close),
);

void main() {
  testWidgets('closing returns current recipients to the map composer', (
    tester,
  ) async {
    Set<String>? returned;
    await _pumpPostCreate(
      tester,
      recipients: {'Umaria'},
      onRecipientsChanged: (ids, notes) => returned = ids,
    );
    await tester.tap(_closeControl);
    await _settle(tester);
    expect(returned, {'Umaria'});
    expect(find.byType(PostCreateScreen), findsNothing);
  });

  group('the Post step', () {
    testWidgets(
      'shows the title, the text field, attachment actions and «Далее»',
      (tester) async {
        await _pumpPostCreate(tester);

        expect(find.text('Новый пост'), findsOneWidget);
        expect(_textField, findsOneWidget);
        expect(find.text('О чём ваш пост?'), findsOneWidget);
        expect(find.text('Фото'), findsOneWidget);
        expect(find.text('Файлы'), findsOneWidget);
        expect(find.text('Вставить изображение'), findsOneWidget);
        expect(find.text('Далее: получатели'), findsOneWidget);
        expect(
          find.byType(ForwardRecipientPicker),
          findsNothing,
          reason: 'recipients come after the Post is written',
        );
      },
    );

    testWidgets('«Можно пересылать» is on by default', (tester) async {
      await _pumpPostCreate(tester);

      final toggle = find.ancestor(
        of: find.text('Можно пересылать'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('«Далее» is disabled while nothing is typed', (tester) async {
      await _pumpPostCreate(tester, recipients: {'Umaria'});

      expect(_nextEnabled(tester), isFalse);
    });

    testWidgets('«Далее» stays disabled for whitespace-only text', (
      tester,
    ) async {
      await _pumpPostCreate(tester);

      await tester.enterText(_textField, '   ');
      await _settle(tester);

      expect(_nextEnabled(tester), isFalse);
    });

    testWidgets('«Далее» is enabled with text', (tester) async {
      await _pumpPostCreate(tester);

      await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
      await _settle(tester);

      expect(_nextEnabled(tester), isTrue);
    });

    testWidgets('«Далее» is enabled with only a photo, which can be removed', (
      tester,
    ) async {
      await _pumpPostCreate(tester);

      await _pastePhoto(tester);
      expect(_nextEnabled(tester), isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(PendingAttachmentPreview),
          matching: find.byIcon(Icons.close),
        ),
      );
      await _settle(tester);

      expect(find.byType(PendingAttachmentPreview), findsNothing);
      expect(_nextEnabled(tester), isFalse);
    });
  });

  group('the recipients step', () {
    testWidgets(
      'opens the embedded picker on the same ForwardCubit, and ← brings the '
      'Post back as written',
      (tester) async {
        final h = await _pumpPostCreate(tester);
        await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
        await _settle(tester);

        await _goToRecipients(tester);

        expect(find.text('Получатели'), findsOneWidget);
        final picker = tester.widget<ForwardRecipientPicker>(
          find.byType(ForwardRecipientPicker),
        );
        expect(picker.embedded, isTrue);
        expect(picker.promptUncoveredNotes, isFalse);
        expect(_textField, findsNothing);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await _settle(tester);

        expect(find.text('Новый пост'), findsOneWidget);
        expect(
          tester.widget<TextField>(_textField).controller!.text,
          'Кто в субботу на велопрогулку?',
        );
        expect(h.port.bodies, isEmpty);
      },
    );

    testWidgets('cannot send before anyone is chosen', (tester) async {
      final h = await _pumpPostCreate(tester);
      await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
      await _settle(tester);

      await _goToRecipients(tester);

      // #720: the disabled button keeps its action label; the hint to pick
      // someone is a line beside it, not the button's label.
      expect(find.text('Выберите хотя бы одного получателя'), findsOneWidget);
      expect(find.text('Отправить (0)'), findsOneWidget);
      await tester.tap(find.text('Отправить (0)'));
      await _settle(tester);
      expect(h.port.bodies, isEmpty);
    });

    testWidgets('«Отправить» publishes the Post once to the chosen people', (
      tester,
    ) async {
      final h = await _pumpPostCreate(tester, recipients: {'Umaria', 'Uoleg'});
      await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
      await _settle(tester);

      await _send(tester, count: 2);

      expect(h.port.bodies, ['Кто в субботу на велопрогулку?']);
      expect(h.port.recipients.single, {'Umaria', 'Uoleg'});
      expect(h.port.policies.single, BeaconForwardPolicyValue.open);
      expect(
        find.text('Отправить без общей заметки'),
        findsNothing,
        reason: 'a Post is not asked for a forward note',
      );
    });

    testWidgets('a photo-only Post publishes the photo', (tester) async {
      final h = await _pumpPostCreate(tester, recipients: {'Umaria'});

      await _pastePhoto(tester);
      await _send(tester, count: 1);

      expect(h.port.bodies, hasLength(1));
      expect(h.port.bodies.single.trim(), isEmpty);
      expect(h.port.inlineAttachments, ['photo-1.png']);
      expect(h.port.recipients.single, {'Umaria'});
    });

    testWidgets('switching «Можно пересылать» off publishes a closed Post', (
      tester,
    ) async {
      final h = await _pumpPostCreate(tester, recipients: {'Umaria'});

      await tester.tap(find.text('Можно пересылать'));
      await _settle(tester);
      await tester.enterText(_textField, 'Только для вас');
      await _settle(tester);
      await _send(tester, count: 1);

      expect(h.port.policies.single, BeaconForwardPolicyValue.closed);
    });
    // #607 (#439): the author writes their own Post, so the per-person note
    // field reads as an optional note, not «Заметка для Клары».
    testWidgets(
      'the per-person note hint is an optional note, not «Заметка для»',
      (
        tester,
      ) async {
        final h = await _pumpPostCreate(tester);
        await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
        await _settle(tester);
        await _goToRecipients(tester);

        h.forward.emit(
          h.forward.state.copyWith(
            candidates: const [
              ForwardCandidate(
                profile: Profile(
                  id: 'u1',
                  displayName: 'Клара',
                  rScore: 1,
                  score: 70,
                ),
              ),
            ],
            selectedIds: const {'u1'},
          ),
        );
        await _settle(tester);

        final hints = [
          for (final field in tester.widgetList<TextField>(
            find.descendant(
              of: find.byType(PerRecipientNoteInput),
              matching: find.byType(TextField),
            ),
          ))
            field.decoration?.hintText,
        ];
        // Precondition: Клара has the per-person note field under her row.
        expect(hints, isNotEmpty);
        expect(
          hints,
          everyElement('Добавьте заметку для этого человека (необязательно)'),
        );
        expect(find.textContaining('Заметка для'), findsNothing);
      },
    );
  });

  group('closing', () {
    testWidgets('an untouched screen closes silently with no server call', (
      tester,
    ) async {
      final h = await _pumpPostCreate(tester);

      await tester.tap(_closeControl);
      await tester.pump();
      // A fully opened default-theme route needs 450 ms to finish popping.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Удалить черновик?'), findsNothing);
      expect(find.byType(PostCreateScreen), findsNothing);
      expect(h.write.createdFields, isEmpty);
      expect(h.write.deletedIds, isEmpty);
    });

    testWidgets(
      'with text typed it asks «Удалить черновик?» and keeps the screen on cancel',
      (tester) async {
        final h = await _pumpPostCreate(tester, recipients: {'Umaria'});
        await tester.enterText(_textField, 'Черновик поста');
        await _letDraftSave(tester);

        await tester.tap(_closeControl);
        await _settle(tester);

        expect(find.text('Удалить черновик?'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Отмена'),
          ),
        );
        await _settle(tester);

        expect(find.byType(PostCreateScreen), findsOneWidget);
        expect(h.write.deletedIds, isEmpty);
      },
    );

    testWidgets(
      'confirming discards the draft the screen created for the typed text',
      (tester) async {
        final h = await _pumpPostCreate(tester, recipients: {'Umaria'});
        await tester.enterText(_textField, 'Черновик поста');
        await _letDraftSave(tester);

        await tester.tap(_closeControl);
        await _settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Удалить'),
          ),
        );
        await _settle(tester);

        expect(h.write.createdFields, hasLength(1));
        expect(h.write.createdFields.single.kind, BeaconKind.post);
        expect(h.write.deletedIds, ['server-beacon']);
        expect(h.port.bodies, isEmpty, reason: 'nothing was published');
      },
    );

    testWidgets(
      'with only an attachment it still asks before discarding and deletes on confirm',
      (tester) async {
        final h = await _pumpPostCreate(tester, recipients: {'Umaria'});
        await _pastePhoto(tester);
        await _letDraftSave(tester);

        await tester.tap(_closeControl);
        await _settle(tester);
        expect(find.text('Удалить черновик?'), findsOneWidget);
        expect(h.write.deletedIds, isEmpty);

        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Удалить'),
          ),
        );
        await _settle(tester);

        expect(h.write.createdFields, hasLength(1));
        expect(h.write.deletedIds, ['server-beacon']);
      },
    );

    testWidgets('✕ on the recipients step asks too', (tester) async {
      await _pumpPostCreate(tester, recipients: {'Umaria'});
      await tester.enterText(_textField, 'Черновик поста');
      await _settle(tester);
      await _goToRecipients(tester);

      await tester.tap(_closeControl);
      await _settle(tester);

      expect(find.text('Удалить черновик?'), findsOneWidget);
    });
  });

  group('overflow', () {
    testWidgets('«Нужна помощь? Создать запрос ›» leads to the Request form', (
      tester,
    ) async {
      final h = await _pumpPostCreate(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(TenturaTopBar),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await _settle(tester);
      expect(find.text('Нужна помощь? Создать запрос ›'), findsOneWidget);

      await tester.tap(find.text('Нужна помощь? Создать запрос ›'));
      await _settle(tester);

      expect(
        h.navigations,
        anyOf(contains(kPathBeaconNew), contains('BeaconCreateRoute')),
      );
    });
  });

  group('recovering from a failed send', () {
    Future<void> sendWithPhotos(
      WidgetTester tester, {
      required int photos,
      required int recipients,
    }) async {
      await tester.enterText(_textField, 'Кто в субботу на велопрогулку?');
      for (var i = 0; i < photos; i++) {
        await _pastePhoto(tester, expectedPreviews: i + 1);
      }
      await _send(tester, count: recipients);
    }

    String postText(WidgetTester tester) =>
        tester.widget<TextField>(_textField).controller!.text;

    Future<void> backToPost(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
    }

    testWidgets(
      'after a network error the user can press «Отправить» again with the '
      'same content',
      (tester) async {
        final h = await _pumpPostCreate(
          tester,
          recipients: {'Umaria', 'Uoleg'},
        );
        h.port.publishErrors.add(Exception('network down'));

        await sendWithPhotos(tester, photos: 2, recipients: 2);

        expect(h.port.signatures, hasLength(1));
        expect(h.effects.emitted.whereType<ShowError>(), isNotEmpty);
        expect(find.byType(PostCreateScreen), findsOneWidget);
        expect(h.port.uploads, isEmpty);

        await tester.tap(_sendButton(2));
        await _settle(tester);

        expect(h.port.signatures, hasLength(2));
        expect(h.port.signatures[1], h.port.signatures[0]);
        expect(h.port.uploads, ['photo-2.png']);
        expect(
          h.write.createdFields,
          hasLength(1),
          reason: 'same draft reused',
        );
        expect(h.write.deletedIds, isEmpty);
      },
    );

    testWidgets('the Post keeps its text after a failed send', (tester) async {
      final h = await _pumpPostCreate(tester, recipients: {'Umaria'});
      h.port.publishErrors.add(Exception('network down'));

      await sendWithPhotos(tester, photos: 1, recipients: 1);
      await backToPost(tester);

      expect(postText(tester), 'Кто в субботу на велопрогулку?');
      expect(find.byType(PendingAttachmentPreview), findsOneWidget);
    });

    testWidgets('after a failed photo upload «Отправить» retries only that '
        'photo', (tester) async {
      final h = await _pumpPostCreate(tester, recipients: {'Umaria'});
      h.port.failUploadOnce.add('photo-2.png');

      await sendWithPhotos(tester, photos: 2, recipients: 1);

      expect(h.port.signatures, hasLength(1));
      expect(h.port.inlineAttachments, ['photo-1.png']);
      expect(h.port.uploads, ['photo-2.png']);
      expect(h.effects.emitted.whereType<ShowError>(), isNotEmpty);

      await tester.tap(_sendButton(1));
      await _settle(tester);

      expect(
        h.port.signatures,
        hasLength(1),
        reason: 'postPublish is not re-sent',
      );
      expect(h.port.uploads, ['photo-2.png', 'photo-2.png']);
    });
  });

  group('route', () {
    test('lives at /post/new and carries the forward-to user in the query', () {
      expect(kPathPostNew, '/post/new');
      expect(
        PostCreateRoute(forwardToUserId: 'Umaria').rawQueryParams.values,
        contains('Umaria'),
      );
    });
  });
}
