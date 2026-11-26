@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/data/service/remote_api_client/remote_request_client.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/features/phantoms/data/repository/person_note_repository.dart';
import 'package:tentura/features/phantoms/data/repository/phantom_repository.dart';
import 'package:tentura/features/phantoms/domain/entity/phantom.dart';
import 'package:tentura/features/phantoms/domain/port/person_note_repository_port.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/graph_trust_write_fixture.dart';
import '../../support/people_tags_widget_harness.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _viewer = 'Uviewer000001';
const _personName = 'Anna';
const _person = Profile(id: 'Uanna00000001', displayName: _personName);
const _accountlessId = 'PH0123456789ab';
const _accountlessName = 'Kolya';
const _mergedHeading = '— «Kolya»';

void main() {
  testWidgets('a person note loads from GraphQL and saves its edit', (
    tester,
  ) async {
    final wire = _NoteWire(ownNote: 'Met at the market');
    await _withPanel(tester, wire, (panel) async {
      final note = panel.showing('Met at the market');
      expect(
        note,
        findsOneWidget,
        reason: 'The existing private note is shown',
      );
      wire.expectReadFor('subjectUserId', _person.id);

      final editor = await panel.edit(tester, existing: 'Met at the market');
      await panel.save(tester, editor, 'Fixes bikes');

      expect(wire.writes, [
        _write('PersonNoteUpsert', userId: _person.id, body: 'Fixes bikes'),
      ]);
      expect(panel.showing('Fixes bikes'), findsOneWidget);
      expect(note, findsNothing);
    });
  });

  testWidgets('a person without an account can get a new private note', (
    tester,
  ) async {
    final wire = _NoteWire();
    await _withPanel(tester, wire, (panel) async {
      final editor = await panel.edit(tester);
      wire.expectReadFor('subjectPhantomId', _accountlessId);
      await panel.save(tester, editor, 'Neighbour, 3rd floor');

      expect(wire.writes, [
        _write(
          'PersonNoteUpsert',
          accountlessId: _accountlessId,
          body: 'Neighbour, 3rd floor',
        ),
      ]);
      expect(panel.showing('Neighbour, 3rd floor'), findsOneWidget);
    }, accountless: true);
  });

  testWidgets('saving a cleared note deletes it and shows the add-note state', (
    tester,
  ) async {
    final wire = _NoteWire(ownNote: 'Fixes bikes');
    await _withPanel(tester, wire, (panel) async {
      final editor = await panel.edit(tester, existing: 'Fixes bikes');
      await panel.save(tester, editor, '');

      expect(wire.writes, [_write('PersonNoteDelete', userId: _person.id)]);
      expect(panel.showing('Fixes bikes'), findsNothing);
      expect(panel.addNote, findsWidgets);
    });
  });

  for (final accountless in [false, true]) {
    testWidgets(
      'the ${accountless ? 'accountless' : 'person'} panel limits a note to 4000 characters',
      (tester) async {
        final wire = _NoteWire();
        await _withPanel(tester, wire, (panel) async {
          final editor = await panel.edit(tester);
          final tooLong = List.filled(4001, 'a').join();
          final atLimit = tooLong.substring(0, 4000);
          await tester.ensureVisible(editor);
          await tester.enterText(editor, tooLong);
          await _settlePanel(tester);
          expect(wire.writes, isEmpty, reason: 'Pasting alone does not save');

          final body = tester.widget<EditableText>(editor).controller.text;
          if (body == tooLong) {
            final save = panel.saveControl(tester, editor);
            if (save != null) {
              await tester.ensureVisible(save);
              await tester.pump();
              final savePoint = tester.getCenter(save);
              expect(tester.getRect(panel.panel).contains(savePoint), isTrue);
              await tester.tapAt(savePoint);
              await _settlePanel(tester);
            }
            expect(
              wire.writes,
              isEmpty,
              reason: 'A save attempt with all 4001 characters sends no write',
            );
            expect(
              tester.widget<EditableText>(editor).controller.text,
              tooLong,
            );
            await panel.save(tester, editor, atLimit);
          } else {
            expect(body, atLimit, reason: 'The paste stops at 4000 characters');
            await panel.tapSave(tester, editor);
          }

          expect(wire.writes, [
            _write(
              'PersonNoteUpsert',
              userId: accountless ? null : _person.id,
              accountlessId: accountless ? _accountlessId : null,
              body: atLimit,
            ),
          ]);
        }, accountless: accountless);
      },
    );
  }

  testWidgets('a merged person shows the own note before the named section', (
    tester,
  ) async {
    await _withPanel(tester, _mergedNotes(), (panel) async {
      final own = panel.showing('Own note on U');
      final heading = panel.showing(_mergedHeading);
      final merged = panel.showing('Note from phantom');
      expect(own, findsOneWidget);
      expect(heading, findsOneWidget);
      expect(merged, findsOneWidget);
      expect(
        tester.getTopLeft(own).dy,
        lessThan(tester.getTopLeft(heading).dy),
      );
      expect(
        tester.getTopLeft(heading).dy,
        lessThan(tester.getTopLeft(merged).dy),
      );
    });
  });

  testWidgets('editing a merged section saves only that section', (
    tester,
  ) async {
    final wire = _mergedNotes();
    await _withPanel(tester, wire, (panel) async {
      final editor = await panel.edit(tester, existing: 'Note from phantom');
      await panel.save(tester, editor, 'Updated');

      expect(wire.writes, [
        _write(
          'PersonNoteUpsert',
          accountlessId: _accountlessId,
          body: 'Updated',
        ),
      ]);
      expect(panel.showing('Own note on U'), findsOneWidget);
      expect(panel.showing('Updated'), findsOneWidget);
      expect(panel.showing('Note from phantom'), findsNothing);
    });
  });

  for (final (locale, accountless) in const [
    (Locale('en'), false),
    (Locale('ru'), false),
    (Locale('en'), true),
    (Locale('ru'), true),
  ]) {
    final surface = accountless ? 'Accountless person' : 'Person';
    testWidgets('$surface note controls use ${locale.languageCode} copy', (
      tester,
    ) async {
      await _withPanel(
        tester,
        _NoteWire(),
        (panel) async {
          final arb = _readArb(locale.languageCode);
          final other = _readArb(locale.languageCode == 'en' ? 'ru' : 'en');

          expect(
            panel.addNote,
            findsWidgets,
            reason: 'The empty note invites editing',
          );
          final emptyCopy = tester
              .widgetList<Text>(panel.addNote)
              .map(
                (text) => text.data ?? text.textSpan!.toPlainText(),
              )
              .toList();

          final editor = await panel.edit(tester);
          final textField = find.ancestor(
            of: editor,
            matching: find.byType(TextField),
          );
          final decoration = tester.widget<TextField>(textField).decoration;
          final label =
              decoration?.labelText ??
              (decoration?.label is Text
                  ? (decoration!.label! as Text).data
                  : null) ??
              panel.noteLabel;
          final hint = decoration?.hintText;
          expect(label, isNotEmpty, reason: 'The private note has a label');
          expect(hint, isNotEmpty, reason: 'The private note has a hint');
          await panel.tap(tester, editor);
          expect(panel.showing(label!), findsWidgets);
          expect(panel.showing(hint!), findsWidgets);

          await tester.enterText(editor, 'For later');
          await tester.pump();
          final save = lookupL10n(locale).buttonSave;
          expect(panel.showing(save), findsWidgets);
          for (final copy in {label, hint, save, ...emptyCopy}) {
            _expectTranslated(copy, arb, other);
          }
          expect(tester.takeException(), isNull);
        },
        locale: locale,
        accountless: accountless,
      );
    });
  }
}

Map<String, Object?> _readArb(String language) =>
    (jsonDecode(File('l10n/app_$language.arb').readAsStringSync()) as Map)
        .cast<String, Object?>();

void _expectTranslated(
  String copy,
  Map<String, Object?> arb,
  Map<String, Object?> other,
) {
  final keys = arb.keys.where(
    (key) => !key.startsWith('@') && arb[key] == copy,
  );
  expect(
    keys.any((key) => other[key] is String && other[key] != copy),
    isTrue,
    reason: '"$copy" has a translated ARB entry in both locales',
  );
  expect(copy, isNot(matches(RegExp('phantom|фантом', caseSensitive: false))));
}

_NoteWire _mergedNotes() => _NoteWire(
  ownNote: 'Own note on U',
  accountlessNote: 'Note from phantom',
  merged: true,
);

Map<String, Object?> _write(
  String name, {
  String? userId,
  String? accountlessId,
  String? body,
}) => {
  'operationName': name,
  'variables': {
    'subjectUserId': ?userId,
    'subjectPhantomId': ?accountlessId,
    'body': ?body,
  },
};

/// Server responses and recorded HTTP calls. No note domain objects are passed
/// into the panels or the cubit.
final class _NoteWire {
  _NoteWire({this.ownNote, this.accountlessNote, this.merged = false});

  final sent = <WireSent>[];
  final paths = <String>[];
  String? ownNote;
  String? accountlessNote;
  final bool merged;

  void expectReadFor(String subject, String id) {
    final index = sent.indexWhere(
      (call) =>
          call.operationName == 'PersonNote' && call.variables[subject] == id,
    );
    expect(
      index,
      isNonNegative,
      reason: 'The panel reads the selected person’s note',
    );
    expect(paths[index], endsWith('/api/v2/graphql'));
  }

  List<Map<String, Object?>> get writes => [
    for (final call in sent)
      if (call.operationName == 'PersonNoteUpsert' ||
          call.operationName == 'PersonNoteDelete')
        {
          'operationName': call.operationName,
          'variables': Map.of(call.variables)
            ..removeWhere((_, value) => value == null),
        },
  ];

  Map<String, Object?> _section(String body, {bool named = false}) => {
    '__typename': 'PersonNoteSection',
    'body': body,
    'subjectPhantomId': named ? _accountlessId : null,
    'phantomName': named ? _accountlessName : null,
  };

  Future<Map<String, dynamic>> respond(WireSent request) async {
    final accountless = request.variables['subjectPhantomId'] != null;
    switch (request.operationName) {
      case 'PersonNote':
        return {
          '__typename': 'query_root',
          'personNote': [
            if (accountless) ...[
              if (accountlessNote case final body?) _section(body),
            ] else ...[
              if (ownNote case final body?) _section(body),
              if (merged && accountlessNote != null)
                _section(accountlessNote!, named: true),
            ],
          ],
        };
      case 'PersonNoteUpsert':
        final body = request.variables['body'] as String;
        if (accountless) {
          accountlessNote = body;
        } else {
          ownNote = body;
        }
        return {'__typename': 'mutation_root', 'personNoteUpsert': true};
      case 'PersonNoteDelete':
        if (accountless) {
          accountlessNote = null;
        } else {
          ownNote = null;
        }
        return {'__typename': 'mutation_root', 'personNoteDelete': true};
      default:
        throw StateError(
          'Unexpected GraphQL operation ${request.operationName}',
        );
    }
  }
}

final class _MountedPanel {
  _MountedPanel(this.panel, this.locale);

  final Finder panel;
  final Locale locale;

  Finder inside(Finder matching) =>
      find.descendant(of: panel, matching: matching);
  Finder showing(String text) => inside(find.text(text));

  String? get noteLabel {
    final label = inside(
      find.textContaining(
        switch (locale.languageCode) {
          'ru' => RegExp(
            r'^(личная |приватная )?заметка$',
            caseSensitive: false,
          ),
          _ => RegExp(r'^(private |personal )?notes?$', caseSensitive: false),
        },
      ),
    );
    final text = label.evaluate().firstOrNull?.widget;
    return text is Text ? text.data ?? text.textSpan?.toPlainText() : null;
  }

  Finder get addNote => inside(
    find.textContaining(
      switch (locale.languageCode) {
        'ru' => RegExp(
          '(добавить|напишите|введите).*заметк',
          caseSensitive: false,
        ),
        _ => RegExp(r'(add|write|enter).*\bnote\b', caseSensitive: false),
      },
    ),
  );

  Finder _editor(String? value) => inside(
    find.byWidgetPredicate(
      (widget) =>
          widget is EditableText &&
          (value == null || widget.controller.text == value),
      description: value == null
          ? 'private note editor'
          : 'editor for "$value"',
    ),
  );

  Future<Finder> edit(WidgetTester tester, {String? existing}) async {
    if (existing != null) {
      final body = showing(existing);
      expect(body, findsOneWidget, reason: 'The current note is displayed');
      if (_editor(existing).evaluate().isEmpty) await tap(tester, body);
    } else if (_editor(null).evaluate().isEmpty) {
      expect(addNote, findsWidgets, reason: 'An empty note can be added');
      await tap(tester, addNote.first);
    }
    final editor = _editor(existing);
    expect(
      editor,
      findsOneWidget,
      reason: 'The note can be edited in its panel',
    );
    // The initial value identifies the right editor in a multi-section panel.
    final element = editor.evaluate().single;
    return find.byElementPredicate(
      (candidate) => identical(candidate, element),
    );
  }

  Finder? saveControl(WidgetTester tester, Finder editor) {
    final controls = showing(lookupL10n(locale).buttonSave);
    final candidates = controls.evaluate().toList();
    if (candidates.isEmpty) return null;
    final editY = tester.getCenter(editor).dy;
    var closest = controls.first;
    var distance = double.infinity;
    for (var index = 0; index < candidates.length; index++) {
      final control = controls.at(index);
      final delta = (tester.getCenter(control).dy - editY).abs();
      if (delta < distance) {
        closest = control;
        distance = delta;
      }
    }
    return closest;
  }

  Future<void> tap(WidgetTester tester, Finder control) async {
    await tester.ensureVisible(control);
    await tester.tap(control);
    await _settlePanel(tester);
  }

  Future<void> tapSave(WidgetTester tester, Finder editor) async {
    final save = saveControl(tester, editor);
    expect(save, isNotNull, reason: 'The edited note can be saved');
    await tap(tester, save!);
  }

  Future<void> save(WidgetTester tester, Finder editor, String body) async {
    await tester.ensureVisible(editor);
    await tester.enterText(editor, body);
    await tester.pump();
    await tapSave(tester, editor);
  }
}

Future<void> _settlePanel(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
  expect(tester.takeException(), isNull);
}

Future<void> _withPanel(
  WidgetTester tester,
  _NoteWire wire,
  Future<void> Function(_MountedPanel) scenario, {
  Locale locale = const Locale('en'),
  bool accountless = false,
}) async {
  if (locale.languageCode == 'ru') await usePhoneSurface(tester);
  await withRemoteWire(
    const {},
    wire.sent,
    (remote) async {
      final fixture = GraphTrustWriteFixture();
      fixture.profiles.byId[_person.id] = _person;
      final contextCubit = fixture.createCubit(viewerId: _viewer);
      final getIt = GetIt.I
        ..pushNewScope(
          init: (scope) {
            scope
              ..registerSingleton<RemoteApiService>(remote)
              ..registerSingleton<RemoteRequestClient>(remote)
              ..registerSingleton<PersonNoteRepositoryPort>(
                PersonNoteRepository(remote),
              )
              ..registerSingleton<PhantomRepositoryPort>(
                PhantomRepository(remote),
              );
          },
        );
      addTearDown(() async {
        await fixture.dispose();
        await getIt.popScope();
      });

      final now = DateTime.utc(2026, 11, 5);
      final panel = accountless
          ? PhantomContextPanel(
              person: Phantom(
                id: _accountlessId,
                displayName: _accountlessName,
                hasPrivateAvatar: false,
                ownTagIds: const [],
                inviteState: PhantomInviteState.none,
                createdAt: now,
              ),
              tags: const [],
              nowUtc: now,
              linkCandidates: () => const [],
              onChanged: () async {},
              onClose: () {},
            )
          : const GraphPersonContextPanel(
              profile: _person,
              focusedNode: UserNode(user: _person),
            );

      if (!accountless) contextCubit.selectProfile(_person, intentional: true);
      await tester.pumpPeopleTagsWidget(
        MaterialApp(
          locale: locale,
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<GraphPersonContextCubit>.value(
                  value: contextCubit,
                ),
                BlocProvider(create: (_) => ScreenCubit(FakeUiEffectPort())),
              ],
              child: Scaffold(body: panel),
            ),
          ),
        ),
      );
      await _settlePanel(tester);
      final mounted = _MountedPanel(
        accountless
            ? find.byType(PhantomContextPanel)
            : find.byKey(TestIds.key(TestIds.graphPersonContextPanel)),
        locale,
      );
      expect(
        mounted.showing(accountless ? _accountlessName : _personName),
        findsOneWidget,
      );
      await scenario(mounted);
    },
    responseFor: wire.respond,
    requestPaths: wire.paths,
  );
}
