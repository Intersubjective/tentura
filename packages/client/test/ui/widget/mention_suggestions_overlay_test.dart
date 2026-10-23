import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
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

void main() {
  testWidgets('mention overlay lays out when typing @handle', (tester) async {
    await _pumpRoomComposer(tester, [
      _participant('alice'),
      _participant('bob'),
    ]);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '@al');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('@alice', skipOffstage: false), findsOneWidget);
  });

  // #624: picking a suggestion with the mouse left the browser's focus on the
  // page, so the next words never reached the field. Enter kept working.
  group('picking a mention keeps typing in the composer (#624)', () {
    const typed = 'Hi @Ni';
    const picked = 'Hi @Nina Mover ';

    TextEditingController composerText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!;

    bool composerHasFocus(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

    Future<void> typeHiNi(WidgetTester tester) async {
      await _pumpRoomComposer(tester, [
        _participant('', title: 'Nina Mover'),
        _participant('bob'),
      ]);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Nina Mover'), findsOneWidget);
    }

    /// What the keyboard sends next: the field's text with [more] typed at
    /// the caret. Fails if no keyboard is attached to the field.
    void keepTyping(WidgetTester tester, String more) {
      final value = composerText(tester).value;
      final caret = value.selection.baseOffset;
      final text = value.text.replaceRange(caret, caret, more);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret + more.length),
        ),
      );
    }

    void expectPickedWithCaretAfterMention(WidgetTester tester) {
      final value = composerText(tester).value;
      expect(value.text, picked);
      expect(value.selection, const TextSelection.collapsed(offset: 15));
      expect(composerHasFocus(tester), isTrue);
      expect(find.text('Nina Mover'), findsNothing);
    }

    testWidgets('mouse pick re-attaches the keyboard to the field', (
      tester,
    ) async {
      await typeHiNi(tester);
      tester.testTextInput.log.clear();

      await tester.tap(
        find.text('Nina Mover'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterMention(tester);
      // The field reconnects its text input after the click, the way a click
      // into the field does, so the browser puts focus back on it.
      final methods = [for (final c in tester.testTextInput.log) c.method];
      final afterClose = methods.skipWhile(
        (m) => m != 'TextInput.clearClient',
      );
      expect(
        afterClose,
        containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
      );
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('after a mouse pick the next words land in the field', (
      tester,
    ) async {
      await typeHiNi(tester);

      await tester.tap(
        find.text('Nina Mover'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterMention(tester);
      keepTyping(tester, 'recheck 473');
      await tester.pump();
      expect(composerText(tester).text, 'Hi @Nina Mover recheck 473');
      expect(composerHasFocus(tester), isTrue);
    });

    testWidgets('picking with Enter keeps typing in the field', (
      tester,
    ) async {
      await typeHiNi(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterMention(tester);
      keepTyping(tester, 'recheck 473');
      await tester.pump();
      expect(composerText(tester).text, 'Hi @Nina Mover recheck 473');
    });

    testWidgets('touch pick keeps the keyboard up without reconnecting', (
      tester,
    ) async {
      await typeHiNi(tester);
      tester.testTextInput.log.clear();

      await tester.tap(find.text('Nina Mover'));
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterMention(tester);
      expect(
        [for (final c in tester.testTextInput.log) c.method],
        isNot(contains('TextInput.clearClient')),
      );
      keepTyping(tester, 'recheck 473');
      await tester.pump();
      expect(composerText(tester).text, 'Hi @Nina Mover recheck 473');
    });
  });

  // #630: emoji suggestion rows had the same mouse-pick problem as #624.
  group('picking an emoji suggestion keeps typing in the composer (#630)', () {
    const typed = 'hi :smi';
    const picked = 'hi 😄';

    TextEditingController composerText(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).controller!;

    bool composerHasFocus(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

    Future<void> typeHiSmi(WidgetTester tester) async {
      await _pumpRoomComposer(tester, [_participant('bob')]);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text(':smile:'), findsOneWidget);
    }

    void keepTyping(WidgetTester tester, String more) {
      final value = composerText(tester).value;
      final caret = value.selection.baseOffset;
      final text = value.text.replaceRange(caret, caret, more);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret + more.length),
        ),
      );
    }

    void expectPickedWithCaretAfterEmoji(WidgetTester tester) {
      final value = composerText(tester).value;
      expect(value.text, picked);
      expect(
        value.selection,
        const TextSelection.collapsed(offset: picked.length),
      );
      expect(composerHasFocus(tester), isTrue);
      expect(find.text(':smile:'), findsNothing);
    }

    testWidgets('mouse pick re-attaches the keyboard to the field', (
      tester,
    ) async {
      await typeHiSmi(tester);
      tester.testTextInput.log.clear();

      await tester.tap(find.text(':smile:'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterEmoji(tester);
      final methods = [for (final c in tester.testTextInput.log) c.method];
      final afterClose = methods.skipWhile(
        (m) => m != 'TextInput.clearClient',
      );
      expect(
        afterClose,
        containsAllInOrder(['TextInput.setClient', 'TextInput.show']),
      );
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('after a mouse pick the next words land in the field', (
      tester,
    ) async {
      await typeHiSmi(tester);

      await tester.tap(find.text(':smile:'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterEmoji(tester);
      keepTyping(tester, ' there');
      await tester.pump();
      expect(composerText(tester).text, '$picked there');
      expect(composerHasFocus(tester), isTrue);
    });

    testWidgets('picking with Enter keeps typing in the field', (
      tester,
    ) async {
      await typeHiSmi(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterEmoji(tester);
      keepTyping(tester, ' there');
      await tester.pump();
      expect(composerText(tester).text, '$picked there');
    });

    testWidgets('touch pick keeps the keyboard up without reconnecting', (
      tester,
    ) async {
      await typeHiSmi(tester);
      tester.testTextInput.log.clear();

      await tester.tap(find.text(':smile:'));
      await tester.pump();
      await tester.pump();

      expectPickedWithCaretAfterEmoji(tester);
      expect(
        [for (final c in tester.testTextInput.log) c.method],
        isNot(contains('TextInput.clearClient')),
      );
      keepTyping(tester, ' there');
      await tester.pump();
      expect(composerText(tester).text, '$picked there');
    });
  });
}
