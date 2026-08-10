import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

const _logicalSize = Size(320, 600);
final _createdAt = DateTime.utc(2026, 6, 30, 12);

Widget _harness(Widget child) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
      BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
      BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: _logicalSize),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(width: _logicalSize.width, child: child),
          ),
        ),
      ),
    ),
  );
}

RoomMessage _replyMessage({
  String body = 'Short reply',
  String? replyToAuthorTitle,
  String? replyToBodyExcerpt,
  bool replyToHasAttachments = false,
  String replyToMessageId = 'parent-1',
  String? replyToAuthorId,
  String authorId = 'viewer',
  Profile author = const Profile(id: 'viewer', displayName: 'Me'),
}) {
  return RoomMessage(
    id: 'reply-1',
    beaconId: 'b1',
    authorId: authorId,
    author: author,
    body: body,
    createdAt: _createdAt,
    replyToMessageId: replyToMessageId,
    replyToAuthorId: replyToAuthorId ?? 'anna',
    replyToAuthorTitle: replyToAuthorTitle ?? 'Anna',
    replyToBodyExcerpt: replyToBodyExcerpt ??
        'can you bring the ladder tomorrow morning if you get a chance',
    replyToHasAttachments: replyToHasAttachments,
  );
}

RoomMessage _linkedReplyMessage() => RoomMessage(
  id: 'reply-linked',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: 'Reply with linked item',
  createdAt: _createdAt,
  linkedItemId: 'item1',
  linkedItemKind: CoordinationItemKind.ask.value,
  linkedItemStatus: CoordinationItemStatus.open.value,
  linkedItemCreatorId: 'u1',
  linkedItemCreatedAt: _createdAt,
  linkedItemUpdatedAt: _createdAt,
  linkedEventKind: CoordinationItemEventKind.created.value,
  replyToMessageId: 'parent-1',
  replyToAuthorId: 'anna',
  replyToAuthorTitle: 'Anna',
  replyToBodyExcerpt: 'Parent excerpt text',
);

Future<void> _tapAndSettle(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders author and excerpt for a normal reply quote', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _replyMessage(),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onToggleReaction: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(
      find.text(
        'can you bring the ladder tomorrow morning if you get a chance',
      ),
      findsOneWidget,
    );
    expect(
      find.text(l10n.beaconRoomReplyOriginalUnavailable),
      findsNothing,
    );
  });

  testWidgets('unavailable reply quote is muted and non-tappable', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    String? jumped;
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: RoomMessage(
            id: 'reply-1',
            beaconId: 'b1',
            authorId: 'viewer',
            author: const Profile(id: 'viewer', displayName: 'Me'),
            body: 'Reply body',
            createdAt: _createdAt,
            replyToMessageId: 'parent-1',
          ),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onJumpToReply: (id) => jumped = id,
          onToggleReaction: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsNothing);
    expect(
      find.text(l10n.beaconRoomReplyOriginalUnavailable),
      findsOneWidget,
    );
    expect(find.byType(InkWell), findsNothing);

    await tester.tap(find.text(l10n.beaconRoomReplyOriginalUnavailable));
    await tester.pumpAndSettle();
    expect(jumped, isNull);
  });

  testWidgets('quote tap invokes jump-to-reply with semantics label', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    String? jumped;
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _replyMessage(
            authorId: 'peer',
            author: const Profile(id: 'peer', displayName: 'Peer'),
          ),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onJumpToReply: (id) => jumped = id,
          onToggleReaction: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final semanticsHandle = tester.ensureSemantics();
    addTearDown(semanticsHandle.dispose);
    expect(
      find.bySemanticsLabel(l10n.beaconRoomReplyQuoteA11yLabel('Anna')),
      findsOneWidget,
    );

    await _tapAndSettle(
      tester,
      tester.getCenter(find.byType(RoomMessageReplyQuote)),
    );
    expect(jumped, 'parent-1');
  });

  testWidgets('compact width does not overflow with a long quote excerpt', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _replyMessage(
            body: 'ok',
            replyToBodyExcerpt:
                'abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ '
                'second line wider than first line of quote text',
          ),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onToggleReaction: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final quote = tester.renderObject<RenderBox>(
      find.byType(RoomMessageReplyQuote),
    );
    expect(quote.size.width, lessThanOrEqualTo(_logicalSize.width));
  });

  testWidgets(
    'tapping quote on linked message jumps without opening coordination item',
    (tester) async {
      CoordinationItem? openedItem;
      String? jumped;

      await tester.pumpWidget(
        _harness(
          RoomMessageTile(
            message: _linkedReplyMessage(),
            myProfile: const Profile(id: 'viewer', displayName: 'Me'),
            onJumpToReply: (id) => jumped = id,
            onOpenCoordinationItem: (item) => openedItem = item,
            onToggleReaction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final quoteCenter = tester.getCenter(find.byType(RoomMessageReplyQuote));
      await _tapAndSettle(tester, quoteCenter);

      expect(jumped, 'parent-1');
      expect(openedItem, isNull);
    },
  );
}
