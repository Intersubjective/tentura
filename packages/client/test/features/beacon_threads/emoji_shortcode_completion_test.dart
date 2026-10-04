import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/emoji_suggestions_overlay.dart';
import 'package:tentura/features/beacon_threads/ui/widget/mention_text_controller.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/emoji/emoji_catalog.dart';
import 'package:tentura/ui/emoji/emoji_picker.dart';
import 'package:tentura/ui/emoji/emoji_recents.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

String? _lookup(String name) => EmojiCatalog.byShortcode(name)?.emoji;

/// Simulates typing one character at the collapsed cursor.
void _type(MentionTextController c, String ch) {
  final at = c.selection.isValid ? c.selection.extentOffset : c.text.length;
  c.value = TextEditingValue(
    text: c.text.replaceRange(at, at, ch),
    selection: TextSelection.collapsed(offset: at + ch.length),
  );
}

void _typeAll(MentionTextController c, String text) {
  for (final ch in text.split('')) {
    _type(c, ch);
  }
}

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state =>
      const ProfileState(profile: Profile(id: 'me', displayName: 'Me'));

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

Finder _composerField() => find.descendant(
  of: find.byType(BeaconRoomComposer),
  matching: find.byType(TextField),
);

Future<List<String>> _pumpComposer(
  WidgetTester tester, {
  Size size = const Size(400, 720),
}) async {
  final sent = <String>[];
  await tester.binding.setSurfaceSize(size);
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
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: const [],
                isLoading: false,
                imageRepository: ImageRepository(),
                clipboardImageRepository: ClipboardImageRepository(),
                enableComposerAttachments: false,
                onSend: (body, _) async {
                  sent.add(body);
                  return true;
                },
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return sent;
}

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(_composerField()).controller!.text;

void main() {
  setUp(EmojiRecents.reset);
  tearDown(EmojiRecents.reset);

  group('MentionTextController :shortcode', () {
    test('detects a shortcode token after whitespace', () {
      final c = MentionTextController(text: 'hi :smi');
      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(c.activeEmojiQuery, 'smi');
      expect(c.activeEmojiRange, const TextRange(start: 3, end: 7));
      expect(c.activeMentionQuery, isNull);
    });

    test('ignores colons glued to words, times and URLs', () {
      for (final text in ['note:smi', '10:30', 'https://x', 'a :)']) {
        final c = MentionTextController(text: text);
        c.selection = TextSelection.collapsed(offset: text.length);
        expect(c.activeEmojiQuery, isNull, reason: text);
      }
    });

    test('a closed :name: is no longer an active query', () {
      final c = MentionTextController(text: ':nope:');
      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(c.activeEmojiQuery, isNull);
    });

    test('typing the closing colon of a known shortcode inserts emoji', () {
      final c = MentionTextController(emojiForShortcode: _lookup);
      _typeAll(c, 'hi :tada:');
      expect(c.text, 'hi 🎉');
      expect(c.selection, const TextSelection.collapsed(offset: 5));
      _typeAll(c, ' :+1:');
      expect(c.text, 'hi 🎉 👍');
    });

    test('unknown shortcodes and pasted text stay as typed', () {
      final c = MentionTextController(emojiForShortcode: _lookup);
      _typeAll(c, ':notanemoji:');
      expect(c.text, ':notanemoji:');

      c.value = const TextEditingValue(
        text: 'pasted :smile:',
        selection: TextSelection.collapsed(offset: 14),
      );
      expect(c.text, 'pasted :smile:');
    });

    test('without a lookup nothing is replaced', () {
      final c = MentionTextController();
      _typeAll(c, ':smile:');
      expect(c.text, ':smile:');
    });

    test('insertEmojiForActiveShortcode replaces the token', () {
      final c = MentionTextController(text: 'yay :ta and more');
      c.selection = const TextSelection.collapsed(offset: 7);
      expect(c.insertEmojiForActiveShortcode('🎉'), isTrue);
      expect(c.text, 'yay 🎉 and more');
      expect(c.selection, const TextSelection.collapsed(offset: 6));
    });

    test('insertAtSelection replaces a selection or appends', () {
      final c = MentionTextController(text: 'ab');
      c.insertAtSelection('😄');
      expect(c.text, 'ab😄');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 1);
      c.insertAtSelection('🎉');
      expect(c.text, '🎉b😄');
      expect(c.selection, const TextSelection.collapsed(offset: 2));
    });

    test('emoji inserted before a committed mention shift it', () {
      final c = MentionTextController(text: '@bo');
      c.selection = const TextSelection.collapsed(offset: 3);
      expect(c.insertLiteralMentionText('@Bob', userId: 'bob'), isTrue);
      c.selection = const TextSelection.collapsed(offset: 0);
      c.insertAtSelection('👋 ');
      expect(c.committedMentions, [(userId: 'bob', start: 3, end: 7)]);
    });
  });

  group('composer :shortcode: completion', () {
    testWidgets('typing :tad suggests emoji and Enter inserts it', (
      tester,
    ) async {
      final sent = await _pumpComposer(tester);
      await tester.tap(_composerField());
      await tester.enterText(_composerField(), 'party :tad');
      await tester.pumpAndSettle();

      expect(find.byType(EmojiSuggestionsOverlay), findsOneWidget);
      expect(find.text(':tada:'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_composerText(tester), 'party 🎉');
      expect(find.byType(EmojiSuggestionsOverlay), findsNothing);
      expect(sent, isEmpty, reason: 'Enter accepts the suggestion, not send');
      expect(EmojiRecents.value, ['🎉']);
    });

    testWidgets('one typed character after the colon shows nothing', (
      tester,
    ) async {
      await _pumpComposer(tester);
      await tester.tap(_composerField());
      await tester.enterText(_composerField(), 'ok :D');
      await tester.pumpAndSettle();
      expect(find.byType(EmojiSuggestionsOverlay), findsNothing);
    });

    testWidgets('Escape closes the suggestions and keeps the text', (
      tester,
    ) async {
      await _pumpComposer(tester);
      await tester.tap(_composerField());
      await tester.enterText(_composerField(), ':smi');
      await tester.pumpAndSettle();
      expect(find.byType(EmojiSuggestionsOverlay), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(EmojiSuggestionsOverlay), findsNothing);
      expect(_composerText(tester), ':smi');
    });
  });

  group('composer emoji picker', () {
    testWidgets('compact: bottom sheet inserts several emoji at cursor', (
      tester,
    ) async {
      await _pumpComposer(tester);
      await tester.enterText(_composerField(), 'hi');
      await tester.pump();

      await tester.tap(find.byKey(TestIds.key(TestIds.roomEmojiButton)));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(EmojiPickerPanel), findsOneWidget);

      final grinning = find.byKey(
        TestIds.key(TestIds.emojiPickerCell('grinning')),
      );
      await tester.tap(grinning);
      await tester.pump();
      await tester.tap(grinning);
      await tester.pump();

      expect(_composerText(tester), 'hi😀😀');
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'stays open');
      expect(EmojiRecents.value, ['😀']);
    });

    testWidgets('wide: popover search picks the first match and closes', (
      tester,
    ) async {
      await _pumpComposer(tester, size: const Size(1200, 800));
      await tester.tap(find.byKey(TestIds.key(TestIds.roomEmojiButton)));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(EmojiPickerPanel), findsOneWidget);

      await tester.enterText(
        find.byKey(TestIds.key(TestIds.emojiPickerSearch)),
        'rocket',
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.byType(EmojiPickerPanel), findsNothing);
      expect(_composerText(tester), '🚀');
    });

    testWidgets('picker shows recently used emoji first', (tester) async {
      EmojiRecents.add('🎉');
      await _pumpComposer(tester);
      await tester.tap(find.byKey(TestIds.key(TestIds.roomEmojiButton)));
      await tester.pumpAndSettle();
      expect(find.text('Recently used'), findsOneWidget);
      final tada = find.byKey(TestIds.key(TestIds.emojiPickerCell('tada')));
      expect(
        tester.getTopLeft(tada.first).dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(TestIds.key(TestIds.emojiPickerCell('grinning'))),
              )
              .dy,
        ),
      );
    });
  });
}
