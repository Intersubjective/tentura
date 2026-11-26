@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/features/constellation/data/repository/constellation_field_search_repository.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_search_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_composer_cubit.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_app_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/phantoms/data/repository/person_note_repository.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/port/person_note_repository_port.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_context_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/constellation_composer_screen_harness.dart';
import '../../support/constellation_store_fixture.dart';
import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/phone_surface.dart';
import '../../support/test_realtime_sync.dart';
import '../constellation/fixtures/constellation_reference_fixture.dart';
import 'fixtures/private_avatar_wire.dart';

const _en = Locale('en');
const _ru = Locale('ru');
const _privateWord = 'phantom|фантом';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (id, name, description) in const [
    (accountHolderId, 'Anna', 'a person with an account'),
    (accountlessId, accountlessName, 'an existing person without an account'),
  ]) {
    testWidgets(
      'the panel for $description shows the uploaded photo on the panel and Field',
      (
        tester,
      ) async {
        final wire = PrivateAvatarWire(pauseUploadResponse: true);
        await _withField(tester, wire, _ru, (field) async {
          final panel = await _openPanel(tester, id, name);
          final remove = _photoControl(panel, _ru, _PhotoAction.remove);
          expect(
            remove,
            findsNothing,
            reason: 'There is no private photo to remove',
          );
          if (id == accountHolderId) {
            expect(_publicPhoto(panel, wire, id), findsOneWidget);
          } else {
            expect(_in(_node(id), find.text(accountlessEmoji)), findsOneWidget);
            _expectMappedAccountlessFlag(wire, field.cubit, false);
          }

          // Pause the actual HTTP reply so the picker result alone cannot
          // satisfy the assertion that a server photo is shown.
          try {
            final add = _expectPhotoControl(
              tester,
              panel,
              _ru,
              _PhotoAction.add,
            );
            await _press(tester, add);
            for (var i = 0; i < 10 && wire.uploads.isEmpty; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            _expectUpload(wire, id);
            expect(
              wire.createdIds,
              isEmpty,
              reason: 'The selected entry already exists',
            );
            expect(wire.downloads, isEmpty);
          } finally {
            wire.releaseUploadResponse();
          }
          await _settle(tester);
          _expectPrivatePhoto(panel, wire, id);
          _expectPrivatePhoto(_node(id), wire, id);
          _expectPhotoControl(tester, panel, _ru, _PhotoAction.remove);
          _expectPhotoControl(tester, panel, _ru, _PhotoAction.change);
          _expectPublicCopy(panel);
          if (id == accountHolderId) {
            expect(_publicPhoto(panel, wire, id), findsNothing);
            expect(_publicPhoto(_node(id), wire, id), findsNothing);
          } else {
            expect(_in(panel, find.text(accountlessEmoji)), findsNothing);
            expect(_in(_node(id), find.text(accountlessEmoji)), findsNothing);
            await field.notifyPersonChange(id, RealtimeOperation.update);
            _expectMappedAccountlessFlag(wire, field.cubit, true);
            _expectPrivatePhoto(_node(id), wire, id);
          }
        });
      },
    );
  }

  for (final withInvite in [false, true]) {
    testWidgets(
      'adding a person ${withInvite ? 'with' : 'without'} an invite uploads a picked photo after creation',
      (tester) async {
        final wire = PrivateAvatarWire();
        final locale = withInvite ? _en : _ru;
        final l10n = lookupL10n(locale);
        final clipboardWrites = _recordClipboard(tester);
        await _withField(tester, wire, locale, (field) async {
          if (!withInvite) {
            await _openAddPerson(tester, locale, name: 'Mira');
            await _tap(tester, find.text(l10n.personCreateSave));
            expect(wire.createdIds, hasLength(1));
            expect(wire.uploads, isEmpty);
            expect(wire.picks, 0);
            await field.notifyPersonChange(
              wire.createdIds.single,
              RealtimeOperation.insert,
            );
            expect(_node(wire.createdIds.single), findsOneWidget);
          }
          final sheet = await _openAddPerson(tester, locale, name: 'Sam');
          await _tapPhoto(tester, sheet, locale, _PhotoAction.add);
          expect(wire.picks, 1);
          expect(wire.uploads, isEmpty, reason: 'The person is still unsaved');
          for (final action in [_PhotoAction.change, _PhotoAction.remove]) {
            if (locale == _ru) {
              expect(_photoControl(sheet, _en, action), findsNothing);
            }
            // Some sheet presentations offer actions on the draft photo.
            if (_photoControl(sheet, locale, action).evaluate().isNotEmpty) {
              _expectPhotoControl(tester, sheet, locale, action);
            }
          }
          _expectPublicCopy(sheet);
          await _tap(
            tester,
            find.text(
              withInvite ? l10n.personCreateCopyInvite : l10n.personCreateSave,
            ),
          );

          final id = wire.createdIds.last;
          final create = wire.calls.lastWhere(
            (call) => call.field == 'phantomCreate',
          );
          expect(create.variables['name'], 'Sam');
          _expectUpload(wire, id);
          expect(
            wire.calls.indexOf(create),
            lessThan(wire.calls.indexOf(wire.uploads.single)),
          );
          if (withInvite) {
            final invite = wire.calls.singleWhere(
              (call) => call.field == 'phantomInviteEnsure',
            );
            expect(invite.variables['id'], id);
            expect(clipboardWrites.single, contains('/invite/$invitedCode'));
            // Copy leaves the sheet open so the same link can be shared again.
            Navigator.of(tester.element(find.byType(ConstellationBody))).pop();
            await _settle(tester);
          } else {
            expect(
              wire.calls.where((call) => call.field == 'phantomInviteEnsure'),
              isEmpty,
            );
          }
          await field.notifyPersonChange(id, RealtimeOperation.insert);
          _expectPrivatePhoto(_node(id), wire, id);
        });
      },
    );
  }

  testWidgets(
    'a newly loaded Field uses saved private photos and preserves public photos',
    (
      tester,
    ) async {
      final wire = PrivateAvatarWire(
        savedAvatars: [accountHolderId, accountlessId],
      );
      await _withField(tester, wire, _en, (field) async {
        final unchanged = _node(otherAccountHolderId);
        expect(
          _publicPhoto(unchanged, wire, otherAccountHolderId),
          findsOneWidget,
        );
        expect(wire.picks, 0);
        expect(wire.uploads, isEmpty);
        _expectMappedAccountlessFlag(wire, field.cubit, true);
        expect(
          [
            for (final id in [accountHolderId, accountlessId])
              _privatePhoto(_node(id), wire, id).evaluate().length,
          ],
          [1, 1],
          reason: 'Both photos are restored from the server on first load',
        );
        expect(
          _publicPhoto(_node(accountHolderId), wire, accountHolderId),
          findsNothing,
        );
        expect(
          _in(_node(accountlessId), find.text(accountlessEmoji)),
          findsNothing,
        );
        for (final id in [accountHolderId, accountlessId]) {
          _expectPrivateDownload(wire, id);
        }
        expect(
          wire.returnedAvatarFlags,
          contains(
            allOf(
              containsPair(accountHolderId, true),
              containsPair(otherAccountHolderId, false),
            ),
          ),
          reason:
              'The production query selects the saved-photo flag for both peers',
        );
      });
    },
  );

  testWidgets('the Field List shows the same private photos as the map', (
    tester,
  ) async {
    final wire = PrivateAvatarWire(
      savedAvatars: [accountHolderId, accountlessId],
    );
    await _withField(tester, wire, _en, (_) async {
      await _tap(tester, find.byIcon(Icons.view_list_outlined));
      final anna = find.byKey(
        const ValueKey('constellation.text.person_row.$accountHolderId'),
      );
      final amira = find.byKey(
        const ValueKey('constellation.text.phantom.$accountlessId'),
      );
      expect(_in(anna, find.text('Anna')), findsOneWidget);
      expect(_in(amira, find.text(accountlessName)), findsOneWidget);
      expect(
        [
          _privatePhoto(anna, wire, accountHolderId).evaluate().length,
          _privatePhoto(amira, wire, accountlessId).evaluate().length,
        ],
        [1, 1],
        reason: 'The rows for both people show their private photos',
      );
      expect(_publicPhoto(anna, wire, accountHolderId), findsNothing);
    });
  });

  for (final (id, name, description, rowKey) in const [
    (
      accountHolderId,
      'Anna',
      'a person with an account',
      'constellation.field_search.person.$accountHolderId',
    ),
    (
      accountlessId,
      accountlessName,
      'a person without an account',
      'constellation.field_search.phantom.$accountlessId',
    ),
  ]) {
    testWidgets('Field name search shows the private photo for $description', (
      tester,
    ) async {
      final wire = PrivateAvatarWire(savedAvatars: [id]);
      await _withField(tester, wire, _en, (_) async {
        await _tap(
          tester,
          find.byKey(const Key('constellation.app_bar.search')),
        );
        await tester.enterText(find.byType(TextField).last, name);
        await tester.pump(const Duration(milliseconds: 400));
        await _settle(tester);

        // Accountless name matches come from the loaded Field snapshot.
        final row = find.byKey(ValueKey(rowKey));
        expect(
          _in(row, find.text(name)),
          findsOneWidget,
          reason: 'The name search already shows a result for $name',
        );
        expect(
          _privatePhoto(row, wire, id),
          findsOneWidget,
          reason: 'The search result for $name shows their saved private photo',
        );
        expect(_publicPhoto(row, wire, id), findsNothing);
      });
    });
  }

  for (final (id, name, emoji, fallback) in const [
    (accountHolderId, 'Anna', null, 'public photo'),
    (accountlessId, accountlessName, accountlessEmoji, 'emoji'),
    (accountlessId, accountlessName, null, 'default placeholder'),
  ]) {
    testWidgets(
      'removing a private photo restores the $fallback on the panel and map',
      (
        tester,
      ) async {
        final wire = PrivateAvatarWire(savedAvatars: [id], emoji: emoji);
        await _withField(tester, wire, _ru, (_) async {
          final panel = await _openPanel(tester, id, name);
          final remove = _photoControl(panel, _ru, _PhotoAction.remove);
          expect(
            remove,
            findsOneWidget,
            reason: 'A saved private photo can be removed',
          );
          _expectPrivatePhoto(panel, wire, id);
          _expectPhotoControl(tester, panel, _ru, _PhotoAction.change);
          _expectPublicCopy(panel);

          await _tapPhoto(tester, panel, _ru, _PhotoAction.remove);
          // If the panel asks for confirmation, use the dialog's remove action.
          final dialog = find.byType(AlertDialog);
          if (dialog.evaluate().isNotEmpty) {
            _expectPublicCopy(dialog);
            final l10n = lookupL10n(_ru);
            final ok = MaterialLocalizations.of(tester.element(dialog));
            final confirmation = _in(
              dialog,
              find.textContaining(
                RegExp(
                  [
                    _photoLabel(_ru, _PhotoAction.remove).pattern,
                    for (final label in [
                      l10n.buttonDelete,
                      l10n.buttonRemove,
                      ok.okButtonLabel,
                    ])
                      '^${RegExp.escape(label)}\$',
                  ].join('|'),
                  caseSensitive: false,
                ),
              ),
            );
            await _tap(tester, confirmation);
          }

          _expectPhotoControl(tester, panel, _ru, _PhotoAction.add);
          expect(_photoControl(panel, _ru, _PhotoAction.remove), findsNothing);
          for (final surface in [panel, _node(id)]) {
            expect(_privatePhoto(surface, wire, id), findsNothing);
            if (id == accountHolderId) {
              expect(_publicPhoto(surface, wire, id), findsOneWidget);
            } else if (emoji != null) {
              expect(_in(surface, find.text(emoji)), findsOneWidget);
            } else {
              expect(
                _in(surface, find.byIcon(Icons.person_outline)),
                findsWidgets,
              );
            }
          }
          _expectPublicCopy(panel);
        });
      },
    );
  }
}

Finder _node(String id) => find.byKey(
  TestIds.key(TestIds.graphNode(id.startsWith('PH') ? 'fh:$id' : id)),
);

Finder _in(Finder scope, Finder match) =>
    find.descendant(of: scope, matching: match);

Future<Finder> _openPanel(WidgetTester tester, String id, String name) async {
  await _tap(tester, _node(id));
  final panel = id == accountHolderId
      ? find.byType(GraphPersonContextPanel)
      : find.byType(PhantomContextPanel);
  expect(panel, findsOneWidget);
  expect(_in(panel, find.text(name)), findsOneWidget);
  _expectPublicCopy(panel);
  return panel;
}

Future<Finder> _openAddPerson(
  WidgetTester tester,
  Locale locale, {
  required String name,
}) async {
  final l10n = lookupL10n(locale);
  await _tap(
    tester,
    find.byKey(const Key('constellation.app_bar.create_here')),
  );
  await _tap(tester, find.text(l10n.personCreateAction));
  final sheet = find
      .ancestor(
        of: find.text(l10n.personCreateCanvasAction),
        matching: find.byType(SingleChildScrollView),
      )
      .first;
  final editor = _in(sheet, find.byType(EditableText)).first;
  expect(editor, findsOneWidget);
  await tester.enterText(editor, name);
  await tester.pump();
  _expectPublicCopy(sheet);
  return sheet;
}

enum _PhotoAction { add, change, remove }

RegExp _photoLabel(Locale locale, _PhotoAction action) => RegExp(
  switch ((locale.languageCode, action)) {
    ('ru', _PhotoAction.add) => r'^(Добавить|Выбрать|Загрузить) фото(графию)?$',
    ('ru', _PhotoAction.change) =>
      r'^(Изменить|Сменить|Заменить) фото(графию)?$',
    ('ru', _PhotoAction.remove) => r'^Удалить фото(графию)?$',
    (_, _PhotoAction.add) => r'^(Add|Choose|Pick|Upload)( a)? photo$',
    (_, _PhotoAction.change) => r'^(Change|Replace) photo$',
    (_, _PhotoAction.remove) => r'^(Remove|Delete) photo$',
  },
  caseSensitive: false,
);

Finder _photoControl(Finder scope, Locale locale, _PhotoAction action) {
  final pattern = _photoLabel(locale, action);
  final text = _in(scope, find.textContaining(pattern, findRichText: true));
  if (text.evaluate().isNotEmpty) return text;
  return _in(scope, find.byTooltip(pattern));
}

Finder _expectPhotoControl(
  WidgetTester tester,
  Finder scope,
  Locale locale,
  _PhotoAction action,
) {
  final control = _photoControl(scope, locale, action);
  expect(
    control,
    findsOneWidget,
    reason:
        'The surface offers a visible ${action.name}-photo control in ${locale.languageCode}',
  );
  if (locale == _ru) {
    expect(
      _photoControl(scope, _en, action),
      findsNothing,
      reason: 'The photo control uses Russian throughout this surface',
    );
  }
  final widget = tester.widget(control);
  final copy = switch (widget) {
    Text() => widget.data ?? widget.textSpan!.toPlainText(),
    RichText() => widget.text.toPlainText(),
    Tooltip() => widget.message ?? widget.richMessage!.toPlainText(),
    RawTooltip(semanticsTooltip: final String label) => label,
    _ => throw StateError(
      'Unexpected photo label widget ${widget.runtimeType}',
    ),
  };
  _expectTranslatedPhotoLabel(copy, locale, action);
  return control;
}

Future<void> _tapPhoto(
  WidgetTester tester,
  Finder scope,
  Locale locale,
  _PhotoAction action,
) => _tap(tester, _expectPhotoControl(tester, scope, locale, action));

void _expectTranslatedPhotoLabel(
  String copy,
  Locale locale,
  _PhotoAction action,
) {
  final en = _arb('en');
  final ru = _arb('ru');
  final active = locale == _ru ? ru : en;
  expect(
    active.keys.any((key) {
      final english = en[key];
      final russian = ru[key];
      return active[key] == copy &&
          english is String &&
          _photoLabel(_en, action).hasMatch(english) &&
          russian is String &&
          _photoLabel(_ru, action).hasMatch(russian);
    }),
    isTrue,
    reason: 'The displayed "$copy" label has a matching EN and RU ARB entry',
  );
}

Map<String, Object?> _arb(String language) =>
    jsonDecode(File('l10n/app_$language.arb').readAsStringSync())
        as Map<String, Object?>;

void _expectPublicCopy(Finder scope) {
  final internal = RegExp(_privateWord, caseSensitive: false);
  expect(
    _in(scope, find.textContaining(internal, findRichText: true)),
    findsNothing,
  );
  expect(_in(scope, find.byTooltip(internal)), findsNothing);
}

ImageProvider? _imageProvider(Widget widget) => switch (widget) {
  Image() => widget.image,
  DecoratedBox(decoration: BoxDecoration(:final image)) => image?.image,
  _ => null,
};

ImageProvider? _withoutResize(ImageProvider? provider) =>
    provider is ResizeImage ? _withoutResize(provider.imageProvider) : provider;

Finder _image(Finder surface, bool Function(ImageProvider?) matches) => _in(
  surface,
  find.byWidgetPredicate(
    (widget) => matches(_withoutResize(_imageProvider(widget))),
    description: 'avatar image shown in the surface',
  ),
);

Finder _publicPhoto(Finder surface, PrivateAvatarWire wire, String id) =>
    _image(
      surface,
      (provider) =>
          provider is NetworkImage && provider.url == wire.publicUrl(id),
    );

Finder _privatePhoto(Finder surface, PrivateAvatarWire wire, String id) =>
    _image(
      surface,
      (provider) => switch (provider) {
        NetworkImage() => wire.isPrivateUrl(Uri.parse(provider.url), id),
        MemoryImage() => listEquals(
          provider.bytes,
          wire.expectedPhotoBytes(id),
        ),
        _ => false,
      },
    );

void _expectPrivateDownload(PrivateAvatarWire wire, String id) => expect(
  wire.downloads.any((url) => wire.isPrivateUrl(url, id)),
  isTrue,
  reason: 'The shown photo came from the owner-only download endpoint',
);

void _expectPrivatePhoto(Finder surface, PrivateAvatarWire wire, String id) {
  expect(_privatePhoto(surface, wire, id), findsOneWidget);
  _expectPrivateDownload(wire, id);
}

void _expectUpload(PrivateAvatarWire wire, String id) {
  expect(wire.picks, 1);
  expect(wire.uploads, hasLength(1));
  final upload = wire.uploads.single;
  expect(upload.isMutation, isTrue);
  expect(upload.path, '/api/v2/graphql');
  final isAccountless = id.startsWith('PH');
  expect(upload.variables['subjectUserId'], isAccountless ? isNull : id);
  expect(upload.variables['subjectPhantomId'], isAccountless ? id : isNull);
  expect(upload.file, orderedEquals(wire.pickedBytes));
}

void _expectMappedAccountlessFlag(
  PrivateAvatarWire wire,
  ConstellationCubit cubit,
  bool expected,
) {
  final flags = wire.returnedAvatarFlags
      .map((response) => response[accountlessId])
      .nonNulls;
  expect(flags, isNotEmpty, reason: 'The Field query requests the photo flag');
  expect(flags.last, expected);
  final selected = cubit.state.field!.phantoms.singleWhere(
    (entry) => entry.id == accountlessId,
  );
  expect(
    selected.hasPrivateAvatar,
    expected,
    reason:
        'The real Field repository maps the transport flag into cubit state',
  );
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _press(tester, finder);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 4),
  );
  expect(tester.takeException(), isNull);
}

List<String> _recordClipboard(WidgetTester tester) {
  final writes = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger
    ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = call.arguments as Map<Object?, Object?>;
        writes.add(data['text']! as String);
      }
      return null;
    });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return writes;
}

typedef _MountedField = ({
  ConstellationCubit cubit,
  Future<void> Function(String, RealtimeOperation) notifyPersonChange,
});

Future<void> _withField(
  WidgetTester tester,
  PrivateAvatarWire wire,
  Locale locale,
  Future<void> Function(_MountedField) scenario,
) => wire.run((remote) async {
  final realtime = buildTestRealtimeSync();
  final clock = FakeClockPort(avatarFixtureTime);
  final wakeUp = FakeWakeUpPort();
  addTearDown(realtime.port.dispose);
  final fixture = ConstellationStoreFixture(
    ConstellationRepository(remote),
    accountId: avatarViewer.id,
    clock: clock,
    wakeUp: wakeUp,
    realtime: realtime.case_,
  );
  final search = ConstellationFieldSearchCase(
    ConstellationFieldSearchRepository(remote),
  );
  final cubit = ConstellationCubit(
    case_: fixture.store,
    viewer: avatarViewer,
    loadOnCreate: false,
    fieldSearchCase: search,
  );
  addTearDown(cubit.close);

  final getIt = GetIt.I
    ..pushNewScope(
      init: (scope) {
        final images = ImageRepository();
        scope
          ..registerSingleton<RemoteApiService>(remote)
          ..registerSingleton<RemoteRequestClient>(remote)
          ..registerSingleton<ImageRepository>(images)
          ..registerSingleton<BeaconImagePort>(images)
          ..registerSingleton<ConstellationFieldStoreCase>(fixture.store)
          ..registerSingleton<ConstellationFieldSearchCase>(search)
          ..registerSingleton<PersonNoteRepositoryPort>(
            PersonNoteRepository(remote),
          )
          ..registerSingleton<PhantomRepositoryPort>(PhantomRepository(remote));
      },
    );
  addTearDown(getIt.popScope);

  final composer = buildComposerHarnessComposer(eligible: const {});
  if (locale == _ru) await usePhoneSurface(tester);
  await cubit.load().timeout(const Duration(seconds: 4));
  expect(cubit.state.loadError, isNull);
  expect(wire.calls.any((call) => call.field == 'constellationField'), isTrue);
  await pumpConstellationBody(
    tester,
    cubit,
    size: locale == _ru ? kPhoneSurface : const Size(1200, 900),
    locale: locale,
    disableAnimations: true,
    wrapBody: (body) => BlocProvider<ConstellationComposerCubit>.value(
      value: composer,
      child: Scaffold(
        body: Column(
          children: [
            ConstellationAppBarRow(
              legendExpanded: false,
              onToggleLegend: () {},
            ),
            Expanded(child: body),
          ],
        ),
      ),
    ),
  );
  try {
    await _settle(tester);
    expect(_node(accountHolderId), findsOneWidget);
    expect(_node(accountlessId), findsOneWidget);
    await scenario((
      cubit: cubit,
      notifyPersonChange: (id, operation) async {
        realtime.port.emitChange(
          RealtimeEntityChange(
            kind: RealtimeEntityKind.phantom,
            aggregateId: id,
            operation: operation,
            source: RealtimeChangeSource.serverInvalidation,
          ),
        );
        await tester.pump();
        const refreshWindow = Duration(seconds: 3);
        clock.advance(refreshWindow);
        wakeUp.elapse(refreshWindow);
        await _settle(tester);
      },
    ));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
});
