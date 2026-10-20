// #416: screen-reader names in a room. A read mark is announced once, poll
// bars say which option and how many votes they show, a photo has alt text,
// and the author avatar is "<Name>, open profile", not the initials.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/a11y_spoken.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Me');
const _helper = Profile(id: 'u-helper', displayName: 'Helper Two');

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

Widget _host(Widget child, {Locale locale = const Locale('en')}) =>
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 700)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );

RoomMessageAttachment _photo({String fileName = ''}) => RoomMessageAttachment(
  id: 'a1',
  kind: BeaconRoomMessageAttachmentKind.image,
  position: 0,
  mime: 'image/jpeg',
  sizeBytes: 1,
  imageId: 'img-1',
  imageAuthorId: 'u-helper',
  fileName: fileName,
);

const _poll = RoomPollData(
  id: 'poll-1',
  question: 'Which day?',
  myVariantIds: ['sat'],
  totalVotes: 4,
  variants: [
    RoomPollVariant(id: 'sat', description: 'Saturday', votesCount: 3),
    RoomPollVariant(id: 'sun', description: 'Sunday', votesCount: 1),
  ],
);

List<String> _progressBarLabels() => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().role == SemanticsRole.progressBar,
    )
    .evaluate()
    .map((node) => node.getSemanticsData().label)
    .toList();

void main() {
  group('read mark is announced once', () {
    testWidgets('Sent is one phrase, not label plus an equal tooltip', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const RoomMessageReceiptGlyph(
            receipt: RoomMessageReceipt(state: RoomMessageReceiptState.sent),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(spokenCount('Sent'), 1, reason: spokenNodes().join(' | '));
      handle.dispose();
    });

    testWidgets('Read by 2 people is one phrase', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const RoomMessageReceiptGlyph(
            receipt: RoomMessageReceipt(
              state: RoomMessageReceiptState.read,
              readerIds: ['reader-a', 'reader-b'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        spokenCount('Read by 2 people'),
        1,
        reason: spokenNodes().join(' | '),
      );
      // The glyph keeps its visual tooltip for mouse users.
      expect(find.byType(Tooltip), findsWidgets);
      handle.dispose();
    });

    testWidgets('a whole own message announces its read mark once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RoomMessageTile(
            message: RoomMessage(
              id: 'm1',
              beaconId: 'b1',
              authorId: _viewer.id,
              author: _viewer,
              body: 'See you there',
              createdAt: DateTime(2026, 10, 9, 23, 28),
            ),
            myProfile: _viewer,
            receipt: const RoomMessageReceipt(
              state: RoomMessageReceiptState.read,
              readerIds: ['reader-a'],
            ),
            onToggleReaction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        spokenCount('Read by 1 person'),
        1,
        reason: spokenNodes().join(' | '),
      );
      handle.dispose();
    });
  });

  group('poll result bars are named', () {
    testWidgets('each bar names its option and its vote count', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const RoomPollCard(poll: _poll)));
      await tester.pumpAndSettle();

      final labels = _progressBarLabels();
      expect(labels, hasLength(2), reason: spokenNodes().join(' | '));
      expect(labels[0], contains('Saturday'));
      expect(labels[0], contains('3 votes'));
      expect(labels[1], contains('Sunday'));
      expect(labels[1], contains('1 vote'));
      expect(labels[1], isNot(contains('1 votes')));
      handle.dispose();
    });

    testWidgets('bar names are localized', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const RoomPollCard(poll: _poll), locale: const Locale('ru')),
      );
      await tester.pumpAndSettle();

      final labels = _progressBarLabels();
      expect(labels, hasLength(2), reason: spokenNodes().join(' | '));
      expect(labels[0], contains('Saturday'));
      expect(labels[0], contains('3 голоса'));
      expect(labels[1], contains('Sunday'));
      expect(labels[1], contains('1 голос'));
      handle.dispose();
    });
  });

  group('a photo has alt text', () {
    // The exact wording after "Photo" is the implementer's (a camera file
    // name like IMG_1234.jpg is noise); the alt must start with "Photo".
    bool startsWithPhoto(String text, String word) =>
        text.split('\n').any((line) => line.trimLeft().startsWith(word));

    testWidgets('a named photo is announced as a Photo', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RoomMessageInlineImageAlbum(
            attachments: [_photo(fileName: 'couch.jpg')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final spoken = spokenNodes();
      expect(
        spoken.where((text) => startsWithPhoto(text, 'Photo')),
        hasLength(1),
        reason: spoken.join(' | '),
      );
      expect(spokenCount('Image gallery'), 0);
      handle.dispose();
    });

    testWidgets('a photo without a file name is still announced as a Photo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(RoomMessageInlineImageAlbum(attachments: [_photo()])),
      );
      await tester.pumpAndSettle();

      final spoken = spokenNodes();
      expect(
        spoken.where((text) => startsWithPhoto(text, 'Photo')),
        hasLength(1),
        reason: spoken.join(' | '),
      );
      expect(spokenCount('Image gallery'), 0);
      handle.dispose();
    });

    testWidgets('the alt text is localized', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RoomMessageInlineImageAlbum(
            attachments: [_photo(fileName: 'couch.jpg')],
          ),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      final spoken = spokenNodes();
      expect(
        spoken.where((text) => startsWithPhoto(text, 'Фото')),
        hasLength(1),
        reason: spoken.join(' | '),
      );
      expect(spokenCount('Image gallery'), 0);
      handle.dispose();
    });

    testWidgets('an unnamed photo is localized too', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RoomMessageInlineImageAlbum(attachments: [_photo()]),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      final spoken = spokenNodes();
      expect(
        spoken.where((text) => startsWithPhoto(text, 'Фото')),
        hasLength(1),
        reason: spoken.join(' | '),
      );
      handle.dispose();
    });
  });

  group('the author avatar is named after the person', () {
    testWidgets('it reads <Name>, open profile, not the initials', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          RoomMessageTile(
            message: RoomMessage(
              id: 'm2',
              beaconId: 'b1',
              authorId: _helper.id,
              author: _helper,
              body: 'I can bring chairs',
              createdAt: DateTime(2026, 10, 9, 23, 28),
            ),
            myProfile: _viewer,
            onToggleReaction: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final named = find.semantics.byPredicate(
        (node) =>
            !node.isMergedIntoParent &&
            node.getSemanticsData().label.contains(
              'Helper Two, open profile',
            ),
      );
      expect(named, findsOne, reason: spokenNodes().join(' | '));
      expect(
        named.evaluate().single.getSemanticsData().hasAction(
          SemanticsAction.tap,
        ),
        isTrue,
      );
      expect(spokenLines(), isNot(contains('HT')));
      handle.dispose();
    });
  });
}
