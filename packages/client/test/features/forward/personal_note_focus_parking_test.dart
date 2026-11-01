import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_personal_note_slot.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _ProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState();

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

enum _Surface { picker, requestRecipients, band }

const _otherField = Key('another-field');
const _outsideArea = Key('outside-note');

Finder get _noteField => find.descendant(
  of: find.byType(ForwardRecipientExpandedPersonalNote),
  matching: find.byType(TextField),
);

Future<ForwardCubit> _openNote(
  WidgetTester tester,
  _Surface surface, {
  bool tapEditor = true,
  bool openWithKeyboard = false,
}) async {
  await usePhoneSurface(tester);
  final cubit =
      ForwardCubit(
        beaconId: 'draft',
        debugSkipInitialLoad: true,
        embedded: surface == _Surface.requestRecipients,
        effects: FakeUiEffectPort(),
      )..emit(
        ForwardState(
          beaconId: 'draft',
          beacon: Beacon.empty.copyWith(id: 'draft', title: 'Помощь'),
          candidates: const [
            ForwardCandidate(
              profile: Profile(
                id: 'alex',
                displayName: 'Алексей',
                score: 10,
                rScore: 1,
              ),
            ),
          ],
          selectedIds: const {'alex'},
          band: surface == _Surface.band
              ? const [
                  ForwardBandRow(userId: 'alex', isExploration: true),
                ]
              : const [],
          candidatesLoad: const ForwardCandidatesReady(),
        ),
      );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<ForwardCubit>.value(value: cubit),
          BlocProvider<ProfileCubit>.value(value: _ProfileCubit()),
        ],
        child: Scaffold(
          body: Column(
            children: [
              const SizedBox(
                key: _outsideArea,
                height: 48,
                width: double.infinity,
              ),
              Expanded(
                child: ForwardRecipientPicker(
                  beaconId: 'draft',
                  embedded: surface == _Surface.requestRecipients,
                ),
              ),
              const TextField(
                key: _otherField,
                decoration: InputDecoration(labelText: 'Другое поле'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final addNote = find.byTooltip('Добавить заметку для Алексей');
  if (openWithKeyboard) {
    final icon = find.descendant(
      of: addNote,
      matching: find.byIcon(Icons.add_comment_outlined),
    );
    bool actionHasFocus() => Focus.of(tester.element(icon)).hasFocus;
    for (var step = 0; step < 30 && !actionHasFocus(); step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(
      actionHasFocus(),
      isTrue,
      reason: 'The note action is keyboard reachable.',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await tester.tap(addNote);
  }
  await tester.pumpAndSettle();
  expect(_noteField, findsOneWidget);
  // These are collapse-policy tests. The browser test separately checks that
  // tapping + Note focuses its descendant and accepts keys without this tap.
  if (tapEditor) {
    await tester.tap(_noteField);
    await tester.pumpAndSettle();
  }
  return cubit;
}

FocusNode _editingFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _noteField, matching: find.byType(EditableText)),
    )
    .focusNode;

void main() {
  for (final surface in _Surface.values) {
    group('${surface.name} personal note at 375x667 in Russian', () {
      for (final parkOnRoot in [true, false]) {
        for (final draft in ['', 'Личная заметка']) {
          testWidgets(
            '${draft.isEmpty ? 'empty editor' : 'draft'} survives '
            '${parkOnRoot ? 'root focus parking' : 'editing reconnection'} '
            'until ${parkOnRoot ? 'focus settles on another field' : 'an outside tap'}',
            (tester) async {
              final cubit = await _openNote(tester, surface);
              await tester.enterText(_noteField, draft);
              final editingFocus = _editingFocus(tester);
              expect(editingFocus.hasPrimaryFocus, isTrue);

              // Model the frame boundary in view-focus parking / the shared
              // web helper's unfocus -> next-frame requestKeyboard cycle.
              // This asserts framework collapse policy, not browser recovery.
              if (parkOnRoot) {
                FocusManager.instance.rootScope.requestScopeFocus();
              } else {
                editingFocus.unfocus();
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Match the helper's next-frame recovery. On the unfixed
                // widget the editor has already been removed; do not call
                // requestFocus on its disposed node and obscure that failure.
                if (editingFocus.context?.mounted == true) {
                  editingFocus.requestFocus();
                }
              });
              await tester.pump();
              await tester.pump();
              expect(
                _noteField,
                findsOneWidget,
                reason:
                    'A focus scope is not an intentional destination; '
                    'the editor must remain mounted for recovery.',
              );
              editingFocus.requestFocus();
              await tester.pumpAndSettle();
              expect(editingFocus.hasPrimaryFocus, isTrue);
              expect(
                tester.widget<TextField>(_noteField).controller!.text,
                draft,
              );

              // Intentional destinations and outside taps both collapse,
              // including empty notes. Web touch is exercised in Playwright;
              // VM uses mouse because native touch has a different default
              // EditableTextTapOutsideAction policy.
              if (parkOnRoot) {
                await tester.tap(find.byKey(_otherField));
              } else {
                await tester.tap(
                  find.byKey(_outsideArea),
                  kind: PointerDeviceKind.mouse,
                );
              }
              await tester.pumpAndSettle();
              expect(_noteField, findsNothing);
              if (draft.isNotEmpty) {
                expect(find.text(draft), findsOneWidget);
                expect(cubit.state.perRecipientNotes['alex'], draft);
                // Reopening a saved preview obeys the same parking policy.
                await tester.tap(find.text(draft));
                await tester.pumpAndSettle();
                await tester.tap(_noteField);
                await tester.pump();
                _editingFocus(tester).unfocus();
                await tester.pump();
                await tester.pump();
                expect(_noteField, findsOneWidget);
              } else {
                expect(
                  find.byTooltip('Добавить заметку для Алексей'),
                  findsOneWidget,
                );
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }

      testWidgets('opening a note gives its editor descendant primary focus', (
        tester,
      ) async {
        await _openNote(tester, surface, tapEditor: false);
        expect(
          _editingFocus(tester).hasPrimaryFocus,
          isTrue,
          reason: 'Typing must reach the editor without a second field tap.',
        );
      });

      testWidgets('Enter on the note action moves typing focus to the editor', (
        tester,
      ) async {
        await _openNote(
          tester,
          surface,
          tapEditor: false,
          openWithKeyboard: true,
        );
        expect(
          _editingFocus(tester).hasPrimaryFocus,
          isTrue,
          reason: 'Keyboard activation must focus the editable descendant.',
        );
      });

      testWidgets('Escape collapses the editor and keeps the note preview', (
        tester,
      ) async {
        final cubit = await _openNote(tester, surface);
        await tester.enterText(_noteField, 'Для вас');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_noteField, findsNothing);
        expect(find.text('Для вас'), findsOneWidget);
        expect(cubit.state.perRecipientNotes['alex'], 'Для вас');
        expect(tester.takeException(), isNull);
      });

      // Exercise each intentional dismissal before any parking assertion,
      // so its coverage does not hide behind an earlier failing expectation.
      for (final outsideTap in [false, true]) {
        for (final draft in ['', 'Сохранённая заметка']) {
          testWidgets(
            '${outsideTap ? 'an outside tap' : 'moving to another field'} '
            'closes ${draft.isEmpty ? 'an empty note' : 'to its recipient preview'} '
            'and reopening focuses the editor',
            (tester) async {
              final cubit = await _openNote(tester, surface);
              await tester.enterText(_noteField, draft);
              expect(_editingFocus(tester).hasPrimaryFocus, isTrue);
              if (outsideTap) {
                await tester.tap(
                  find.byKey(_outsideArea),
                  kind: PointerDeviceKind.mouse,
                );
              } else {
                await tester.tap(find.byKey(_otherField));
              }
              await tester.pumpAndSettle();
              expect(_noteField, findsNothing);
              expect(cubit.state.perRecipientNotes['alex'] ?? '', draft);
              if (draft.isEmpty) {
                await tester.tap(
                  find.byTooltip('Добавить заметку для Алексей'),
                );
              } else {
                expect(find.text(draft), findsOneWidget);
                await tester.tap(find.text(draft));
              }
              await tester.pumpAndSettle();
              expect(_noteField, findsOneWidget);
              expect(
                tester.widget<TextField>(_noteField).controller!.text,
                draft,
              );
              expect(
                _editingFocus(tester).hasPrimaryFocus,
                isTrue,
                reason: 'Reopening must accept keys without an editor tap.',
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }

      testWidgets(
        'Escape closes an empty editor without moving to another control',
        (tester) async {
          final cubit = await _openNote(tester, surface);
          expect(
            tester.widget<TextField>(_noteField).controller!.text,
            isEmpty,
          );
          expect(_editingFocus(tester).hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_noteField, findsNothing);
          expect(
            find.byTooltip('Добавить заметку для Алексей'),
            findsOneWidget,
          );
          expect(cubit.state.perRecipientNotes['alex'] ?? '', isEmpty);
          final otherEditing = tester.widget<EditableText>(
            find.descendant(
              of: find.byKey(_otherField),
              matching: find.byType(EditableText),
            ),
          );
          expect(otherEditing.focusNode.hasFocus, isFalse);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'an empty editor closes after an unrecovered blur and reopens ready for typing',
        (tester) async {
          final cubit = await _openNote(tester, surface);
          expect(_editingFocus(tester).hasPrimaryFocus, isTrue);
          expect(
            tester.widget<TextField>(_noteField).controller!.text,
            isEmpty,
          );
          // Unlike the recovered parking cases, no next-frame focus request
          // is pending. Let the focus transition and frames finish, with no
          // tap, Escape or destination control and no elapsed-time debounce.
          FocusManager.instance.rootScope.requestScopeFocus();
          await tester.pumpAndSettle();
          expect(_noteField, findsNothing);
          expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
          expect(cubit.state.perRecipientNotes['alex'] ?? '', isEmpty);
          expect(
            find.byTooltip('Добавить заметку для Алексей'),
            findsOneWidget,
          );

          await tester.tap(find.byTooltip('Добавить заметку для Алексей'));
          await tester.pumpAndSettle();
          expect(_noteField, findsOneWidget);
          expect(
            _editingFocus(tester).hasPrimaryFocus,
            isTrue,
            reason: 'Reopening an empty note must accept keys immediately.',
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('a draft stays expanded while view focus remains parked', (
        tester,
      ) async {
        final cubit = await _openNote(tester, surface);
        await tester.enterText(_noteField, 'Важная заметка');
        final editingFocus = _editingFocus(tester);
        FocusManager.instance.rootScope.requestScopeFocus();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(_noteField, findsOneWidget);
        expect(
          tester.widget<TextField>(_noteField).controller!.text,
          'Важная заметка',
        );
        editingFocus.requestFocus();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_otherField));
        await tester.pumpAndSettle();
        expect(_noteField, findsNothing);
        expect(find.text('Важная заметка'), findsOneWidget);
        expect(cubit.state.perRecipientNotes['alex'], 'Важная заметка');
        expect(tester.takeException(), isNull);
      });
    });
  }
}
