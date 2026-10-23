import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

BeaconParticipant _participant(String handle, {String? title}) =>
    BeaconParticipant(
      id: 'p-${handle.isEmpty ? title : handle}',
      beaconId: 'b1',
      userId: 'u-${handle.isEmpty ? title : handle}',
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      handle: handle,
      userTitle: title ?? 'User $handle',
    );

Future<void> _pumpRoomComposer(
  WidgetTester tester,
  List<BeaconParticipant> participants,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1400, 900)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: participants,
                isLoading: false,
                imageRepository: ImageRepository(),
                clipboardImageRepository: ClipboardImageRepository(),
                onSend: (_, _) async => true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextEditingController _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!;

bool _composerHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

Future<void> _typeInComposer(
  WidgetTester tester,
  List<BeaconParticipant> participants,
  String typed,
) async {
  await _pumpRoomComposer(tester, participants);
  await tester.tap(find.byType(TextField));
  await tester.pump();
  await tester.enterText(find.byType(TextField), typed);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Pointer down and up on [target] with no frame between them, the way
/// macOS tap-to-click sends a click.
Future<void> _instantClick(WidgetTester tester, Finder target) async {
  final at = tester.getCenter(target);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: at);
  await tester.pump();
  await mouse.down(at);
  await mouse.up();
}

/// A tap on the suggestion row's semantics node: how the web app (semantics
/// always on) delivers a quick click on the row.
void _semanticsTap(WidgetTester tester, String identifier) {
  final row = find.semantics.byPredicate((node) {
    final data = node.getSemanticsData();
    return data.identifier == identifier && data.hasAction(SemanticsAction.tap);
  });
  expect(row.evaluate(), hasLength(1));
  tester.semantics.tap(row);
}

/// What the keyboard sends next: the field's text with [more] typed at the
/// caret. Lost if no keyboard is attached to the field.
void _keepTyping(WidgetTester tester, String more) {
  final value = _composerText(tester).value;
  final caret = value.selection.baseOffset;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: value.text.replaceRange(caret, caret, more),
      selection: TextSelection.collapsed(offset: caret + more.length),
    ),
  );
}

/// Right after the pick (no frame yet), the field still has its keyboard,
/// the next keys land, and the keyboard was never disconnected.
Future<void> _expectNextKeysLand(
  WidgetTester tester, {
  required String picked,
  required String more,
}) async {
  // Whatever runs before the next frame (microtasks, zero timers).
  await tester.idle();
  expect(_composerText(tester).text, picked);
  expect(_composerHasFocus(tester), isTrue);
  expect(tester.testTextInput.hasAnyClients, isTrue);

  _keepTyping(tester, more);
  await tester.pump();
  await tester.pump();

  expect(_composerText(tester).text, '$picked$more');
  expect(_composerHasFocus(tester), isTrue);
  expect(
    [for (final c in tester.testTextInput.log) c.method],
    isNot(contains('TextInput.clearClient')),
  );
}

void main() {
  // #688: a click whose pointer down and up arrive in one frame (tap-to-click)
  // on an emoji or @mention suggestion lost the keys typed right after it,
  // because the pick closed the field's keyboard connection and reopened it
  // a frame later.
  group('an instant click on a suggestion keeps the next keys (#688)', () {
    testWidgets('emoji row, mouse down and up in one frame', (tester) async {
      await _typeInComposer(tester, [_participant('bob')], 'hi :smi');
      expect(find.text(':smile:'), findsOneWidget);
      tester.testTextInput.log.clear();

      await _instantClick(tester, find.text(':smile:'));

      await _expectNextKeysLand(tester, picked: 'hi 😄', more: ' there');
      expect(find.text(':smile:'), findsNothing);
    });

    testWidgets('mention row, mouse down and up in one frame', (tester) async {
      await _typeInComposer(tester, [
        _participant('', title: 'Nina Mover'),
        _participant('bob'),
      ], 'Hi @Ni');
      expect(find.text('Nina Mover'), findsOneWidget);
      tester.testTextInput.log.clear();

      await _instantClick(tester, find.text('Nina Mover'));

      await _expectNextKeysLand(
        tester,
        picked: 'Hi @Nina Mover ',
        more: 'recheck 473',
      );
      expect(find.text('Nina Mover'), findsNothing);
    });

    testWidgets('emoji row, semantics tap', (tester) async {
      final semantics = tester.ensureSemantics();
      await _typeInComposer(tester, [_participant('bob')], 'hi :smi');
      tester.testTextInput.log.clear();

      _semanticsTap(tester, TestIds.roomEmojiSuggestion('smile'));

      await _expectNextKeysLand(tester, picked: 'hi 😄', more: ' there');
      semantics.dispose();
    });

    testWidgets('mention row, semantics tap', (tester) async {
      final semantics = tester.ensureSemantics();
      await _typeInComposer(tester, [
        _participant('alice'),
        _participant('bob'),
      ], 'Hi @al');
      tester.testTextInput.log.clear();

      _semanticsTap(tester, TestIds.roomMentionSuggestion('alice'));

      await _expectNextKeysLand(tester, picked: 'Hi @alice ', more: 'yo');
      semantics.dispose();
    });

    testWidgets('picking with Enter keeps the next keys too', (tester) async {
      await _typeInComposer(tester, [_participant('bob')], 'hi :smi');
      tester.testTextInput.log.clear();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(_composerText(tester).text, 'hi 😄');
      _keepTyping(tester, ' there');
      await tester.pump();
      expect(_composerText(tester).text, 'hi 😄 there');
      expect(_composerHasFocus(tester), isTrue);
    });
  });

  // The web fix keeps the browser focus on the field for a press on any node
  // whose identifier starts with these prefixes, so the rows must carry them.
  group('suggestion rows carry the prefixes the web focus fix matches', () {
    bool hasRowWithPrefix(String prefix) => find.semantics
        .byPredicate((node) {
          final identifier = node.getSemanticsData().identifier;
          return identifier.startsWith(prefix) && identifier != prefix;
        })
        .evaluate()
        .isNotEmpty;

    testWidgets('emoji row', (tester) async {
      final semantics = tester.ensureSemantics();
      await _typeInComposer(tester, [_participant('bob')], 'hi :smi');

      expect(hasRowWithPrefix(TestIds.roomEmojiSuggestionPrefix), isTrue);
      semantics.dispose();
    });

    testWidgets('mention row', (tester) async {
      final semantics = tester.ensureSemantics();
      await _typeInComposer(tester, [
        _participant('alice'),
        _participant('bob'),
      ], 'Hi @al');

      expect(hasRowWithPrefix(TestIds.roomMentionSuggestionPrefix), isTrue);
      semantics.dispose();
    });
  });
}
