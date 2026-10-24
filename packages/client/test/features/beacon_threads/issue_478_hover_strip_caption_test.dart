// The desktop hover strip (Reply / heart / more) must never be drawn over the
// message text: on a captioned photo it hid the caption's first line ("Here is
// the couch"), so the strip sits outside the text (#478).
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'me', displayName: 'Me');
const _caption = 'Here is the couch';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(profile: _viewer);

  @override
  Stream<ProfileState> get stream => const Stream<ProfileState>.empty();
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      const Stream<Map<String, UserPresenceStatus>>.empty();
}

final _sentAt = DateTime(2026, 10, 9, 23, 28);

const _photo = RoomMessageAttachment(
  id: 'a1',
  kind: BeaconRoomMessageAttachmentKind.image,
  position: 0,
  mime: 'image/jpeg',
  sizeBytes: 1,
  imageId: 'img-1',
  imageAuthorId: 'me',
);

RoomMessage _message({List<RoomMessageAttachment> attachments = const []}) =>
    RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: _viewer.id,
      author: _viewer,
      body: _caption,
      createdAt: _sentAt,
      attachments: attachments,
    );

const _other = Profile(id: 'u2', displayName: 'Olga');

const _otherPhoto = RoomMessageAttachment(
  id: 'a2',
  kind: BeaconRoomMessageAttachmentKind.image,
  position: 0,
  mime: 'image/jpeg',
  sizeBytes: 1,
  imageId: 'img-2',
  imageAuthorId: 'u2',
);

/// Another participant's captioned photo. The caption is long enough to wrap
/// across the whole bubble width, so a strip pinned to the bubble's far
/// (right) edge lands on it horizontally too.
RoomMessage _otherPhotoMessage() => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body:
      '$_caption, the grey one by the window, pick it up tomorrow evening '
      'after six if that still works for you',
  createdAt: _sentAt,
  attachments: const [_otherPhoto],
);

/// Same author a minute earlier: the photo continues her group, so no name
/// header sits above the caption and the caption is the bubble's first line.
RoomMessage _otherPrevious() => RoomMessage(
  id: 'm0',
  beaconId: 'b1',
  authorId: _other.id,
  author: _other,
  body: 'Found it',
  createdAt: _sentAt.subtract(const Duration(minutes: 1)),
);

Future<void> _pumpTile(
  WidgetTester tester,
  RoomMessage message, {
  required void Function(RoomMessage message) onReplyPressed,
  RoomMessage? previousMessage,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RoomMessageTile(
              message: message,
              previousMessage: previousMessage,
              myProfile: _viewer,
              onActionsPressed: (_) {},
              onReplyPressed: onReplyPressed,
              onToggleReaction: (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tile inside a chat-like scroll view under an app bar. [gapAbove] is
/// the list space before the tile: 0 puts the bubble at the very top of the
/// view, right under the app bar.
Future<void> _pumpTileInList(
  WidgetTester tester,
  RoomMessage message, {
  required void Function(RoomMessage message) onReplyPressed,
  required double gapAbove,
  RoomMessage? previousMessage,
  bool withAppBar = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          appBar: withAppBar ? AppBar(title: const Text('Room')) : null,
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              SizedBox(height: gapAbove),
              RoomMessageTile(
                message: message,
                previousMessage: previousMessage,
                myProfile: _viewer,
                onActionsPressed: (_) {},
                onReplyPressed: onReplyPressed,
                onToggleReaction: (_, _) async {},
              ),
              const SizedBox(height: 600),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<TestGesture> _hoverCaption(WidgetTester tester) async {
  final at = tester.getCenter(find.textContaining(_caption));
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: at);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(at);
  await tester.pumpAndSettle();
  return gesture;
}

/// Union of the hover strip buttons (found by their tooltips).
Rect _stripRect(WidgetTester tester, L10n l10n) {
  final tooltips = [
    l10n.beaconRoomActionReply,
    l10n.beaconRoomReactionAddTooltip,
    l10n.beaconRoomMessageActionsTitle,
  ];
  Rect? rect;
  for (final t in tooltips) {
    final f = find.byTooltip(t);
    expect(f, findsOneWidget, reason: 'hover strip button "$t" is shown');
    final r = tester.getRect(f);
    rect = rect == null ? r : rect.expandToInclude(r);
  }
  return rect!;
}

bool _covers(Rect a, Rect b) {
  final i = a.intersect(b);
  return i.width > 0 && i.height > 0;
}

Future<void> _expectStripClearOfText(WidgetTester tester) async {
  final l10n = lookupL10n(const Locale('en'));
  final strip = _stripRect(tester, l10n);
  final text = tester.getRect(find.textContaining(_caption));
  expect(
    _covers(strip, text),
    isFalse,
    reason: 'hover strip $strip must not cover the message text $text',
  );
}

/// Guard: the strip stays usable once moved away from the text — the pointer
/// can travel onto it without dismissing it, and Reply still hits.
Future<void> _expectStripStillWorks(
  WidgetTester tester,
  TestGesture gesture,
  List<String> replied,
) async {
  final l10n = lookupL10n(const Locale('en'));
  final reply = find.byTooltip(l10n.beaconRoomActionReply);
  await gesture.moveTo(tester.getCenter(reply));
  await tester.pumpAndSettle();
  expect(reply, findsOneWidget, reason: 'strip survives the pointer on it');
  await tester.tap(reply);
  await tester.pumpAndSettle();
  expect(replied, ['m1']);
}

void main() {
  testWidgets('hover strip does not cover the caption of a photo', (
    tester,
  ) async {
    final replied = <String>[];
    await _pumpTile(
      tester,
      _message(attachments: const [_photo]),
      onReplyPressed: (m) => replied.add(m.id),
    );

    final gesture = await _hoverCaption(tester);
    await _expectStripClearOfText(tester);
    await _expectStripStillWorks(tester, gesture, replied);
  });

  testWidgets('hover strip does not cover the text of a plain message', (
    tester,
  ) async {
    final replied = <String>[];
    await _pumpTile(
      tester,
      _message(),
      onReplyPressed: (m) => replied.add(m.id),
    );

    final gesture = await _hoverCaption(tester);
    await _expectStripClearOfText(tester);
    await _expectStripStillWorks(tester, gesture, replied);
  });

  // The strip has its own branch for other people's messages (pinned to the
  // bubble's right edge instead of the left), so the fix must cover it too.
  testWidgets(
    "hover strip does not cover the caption of another author's photo",
    (tester) async {
      final replied = <String>[];
      await _pumpTile(
        tester,
        _otherPhotoMessage(),
        previousMessage: _otherPrevious(),
        onReplyPressed: (m) => replied.add(m.id),
      );

      final gesture = await _hoverCaption(tester);
      await _expectStripClearOfText(tester);
      await _expectStripStillWorks(tester, gesture, replied);
    },
  );

  // A bubble at the top of the chat has no room above it: the strip used to
  // float over the app bar (or above the screen edge). It flips below (#478).
  group('bubble at the top of the view', () {
    testWidgets('strip flips below the bubble, clear of the app bar', (
      tester,
    ) async {
      final replied = <String>[];
      await _pumpTileInList(
        tester,
        _message(),
        gapAbove: 0,
        onReplyPressed: (m) => replied.add(m.id),
      );

      final gesture = await _hoverCaption(tester);
      final l10n = lookupL10n(const Locale('en'));
      final strip = _stripRect(tester, l10n);
      final appBar = tester.getRect(find.byType(AppBar));
      final text = tester.getRect(find.textContaining(_caption));
      expect(
        strip.top,
        greaterThanOrEqualTo(appBar.bottom),
        reason: 'strip $strip must not cover the app bar $appBar',
      );
      expect(
        strip.top,
        greaterThan(text.bottom),
        reason: 'strip $strip sits under the bubble text $text',
      );
      await _expectStripClearOfText(tester);
      await _expectStripStillWorks(tester, gesture, replied);
    });

    testWidgets('strip of another author flips below too', (tester) async {
      final replied = <String>[];
      await _pumpTileInList(
        tester,
        _otherPhotoMessage(),
        previousMessage: _otherPrevious(),
        gapAbove: 0,
        onReplyPressed: (m) => replied.add(m.id),
      );

      final gesture = await _hoverCaption(tester);
      final l10n = lookupL10n(const Locale('en'));
      final strip = _stripRect(tester, l10n);
      final appBar = tester.getRect(find.byType(AppBar));
      expect(
        strip.top,
        greaterThanOrEqualTo(appBar.bottom),
        reason: 'strip $strip must not cover the app bar $appBar',
      );
      await _expectStripClearOfText(tester);
      await _expectStripStillWorks(tester, gesture, replied);
    });

    testWidgets('strip stays on screen without an app bar', (tester) async {
      final replied = <String>[];
      await _pumpTileInList(
        tester,
        _message(),
        gapAbove: 0,
        withAppBar: false,
        onReplyPressed: (m) => replied.add(m.id),
      );

      final gesture = await _hoverCaption(tester);
      final l10n = lookupL10n(const Locale('en'));
      final strip = _stripRect(tester, l10n);
      expect(
        strip.top,
        greaterThanOrEqualTo(0),
        reason: 'strip $strip must not go above the screen edge',
      );
      await _expectStripClearOfText(tester);
      await _expectStripStillWorks(tester, gesture, replied);
    });
  });

  // Guard: with room above, the strip keeps its place over the bubble's top.
  testWidgets('strip stays above a bubble with room above it', (tester) async {
    final replied = <String>[];
    await _pumpTileInList(
      tester,
      _message(),
      gapAbove: 200,
      onReplyPressed: (m) => replied.add(m.id),
    );

    final gesture = await _hoverCaption(tester);
    final l10n = lookupL10n(const Locale('en'));
    final strip = _stripRect(tester, l10n);
    final text = tester.getRect(find.textContaining(_caption));
    expect(
      strip.bottom,
      lessThanOrEqualTo(text.top),
      reason: 'strip $strip sits above the bubble text $text',
    );
    await _expectStripStillWorks(tester, gesture, replied);
  });
}
