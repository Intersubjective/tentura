import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
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

BeaconParticipant _participant(String handle) => BeaconParticipant(
      id: 'p-$handle',
      beaconId: 'b1',
      userId: 'u-$handle',
      role: 0,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      handle: handle,
      userTitle: 'User $handle',
    );

RoomMessage _replyTarget({
  String authorName = 'Anna',
  String body = 'can you bring the ladder tomorrow morning',
}) {
  return RoomMessage(
    id: 'target-1',
    beaconId: 'b1',
    authorId: 'anna',
    author: Profile(id: 'anna', displayName: authorName),
    body: body,
    createdAt: DateTime.utc(2026, 6, 30, 12),
  );
}

Future<void> pumpReplyComposer(
  WidgetTester tester, {
  RoomMessage? replyTarget,
  VoidCallback? onCancelReply,
  List<BeaconParticipant> participants = const [],
  bool enableParticipantMentions = false,
  double width = 400,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
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
          data: MediaQueryData(size: Size(width, 720)),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: BasicChatBody(
                messages: const [],
                myProfile: const Profile(id: 'me', displayName: 'Me'),
                participants: participants,
                isLoading: false,
                imageRepository: ImageRepository(),
                clipboardImageRepository: ClipboardImageRepository(),
                enableComposerAttachments: false,
                enableParticipantMentions: enableParticipantMentions,
                replyTarget: replyTarget,
                onCancelReply: onCancelReply,
                onSend: (_, _) async => true,
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> focusComposerField(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pump();
}

void main() {
  testWidgets('reply banner shows author and excerpt when target is set', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final target = _replyTarget();

    await pumpReplyComposer(
      tester,
      replyTarget: target,
      onCancelReply: () {},
    );

    expect(
      find.text(l10n.beaconRoomReplyingTo('Anna')),
      findsOneWidget,
    );
    expect(
      find.text('can you bring the ladder tomorrow morning'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('reply banner is absent without a reply target', (tester) async {
    await pumpReplyComposer(tester);

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.textContaining('Reply to'), findsNothing);
  });

  testWidgets('close button invokes onCancelReply', (tester) async {
    var cancelled = false;
    await pumpReplyComposer(
      tester,
      replyTarget: _replyTarget(),
      onCancelReply: () => cancelled = true,
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('Escape cancels reply when target and callback are set', (
    tester,
  ) async {
    var cancelled = false;
    await pumpReplyComposer(
      tester,
      replyTarget: _replyTarget(),
      onCancelReply: () => cancelled = true,
    );

    await focusComposerField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancelled, isTrue);
  });

  testWidgets('reply banner renders without close when onCancelReply is null', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));

    await pumpReplyComposer(
      tester,
      replyTarget: _replyTarget(),
      onCancelReply: null,
    );

    expect(find.text(l10n.beaconRoomReplyingTo('Anna')), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('Escape does not cancel when onCancelReply is null', (
    tester,
  ) async {
    await pumpReplyComposer(
      tester,
      replyTarget: _replyTarget(),
      onCancelReply: null,
    );

    await focusComposerField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.textContaining('Reply to Anna'), findsOneWidget);
  });

  testWidgets('Escape with active reply does not activate parent shortcuts', (
    tester,
  ) async {
    var escapeShortcutFired = false;
    var cancelled = false;

    await tester.binding.setSurfaceSize(const Size(400, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                escapeShortcutFired = true;
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: MultiBlocProvider(
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
                  data: const MediaQueryData(size: Size(400, 720)),
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
                        replyTarget: _replyTarget(),
                        onCancelReply: () => cancelled = true,
                        onSend: (_, _) async => true,
                        onToggleReaction: (_, _) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await focusComposerField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancelled, isTrue);
    expect(escapeShortcutFired, isFalse);
  });

  testWidgets('idle Escape is ignored and reaches parent shortcut handler', (
    tester,
  ) async {
    var escapeShortcutFired = false;

    await tester.binding.setSurfaceSize(const Size(400, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): ActivateIntent(),
        },
        child: Actions(
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                escapeShortcutFired = true;
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: MultiBlocProvider(
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
                  data: const MediaQueryData(size: Size(400, 720)),
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
                        onSend: (_, _) async => true,
                        onToggleReaction: (_, _) async {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Composer is not focused — Escape should bubble to the parent shortcut.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(escapeShortcutFired, isTrue);
  });

  testWidgets('Escape dismisses mention overlay before cancelling reply', (
    tester,
  ) async {
    var cancelled = false;
    await pumpReplyComposer(
      tester,
      replyTarget: _replyTarget(),
      onCancelReply: () => cancelled = true,
      participants: [_participant('alice')],
      enableParticipantMentions: true,
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '@al');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('@alice', skipOffstage: false), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('@alice', skipOffstage: false), findsNothing);
    expect(cancelled, isFalse);
  });

  testWidgets('reply banner truncates at compact width without overflow', (
    tester,
  ) async {
    final target = _replyTarget(
      authorName: 'Alexandra With A Very Long Display Name',
      body:
          'This is an intentionally long excerpt that should ellipsize instead of overflowing the composer banner at narrow widths',
    );

    await pumpReplyComposer(
      tester,
      replyTarget: target,
      onCancelReply: () {},
      width: 320,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Reply to Alexandra'), findsOneWidget);
    expect(find.textContaining('intentionally long excerpt'), findsOneWidget);
  });

  testWidgets('attachment-only target shows attachment excerpt in banner', (
    tester,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    final target = RoomMessage(
      id: 'target-2',
      beaconId: 'b1',
      authorId: 'anna',
      author: const Profile(id: 'anna', displayName: 'Anna'),
      body: '',
      createdAt: DateTime.utc(2026, 6, 30, 12),
      attachments: const [
        RoomMessageAttachment(
          id: 'att-1',
          kind: BeaconRoomMessageAttachmentKind.image,
          position: 0,
          mime: 'image/png',
          sizeBytes: 1024,
          fileName: 'photo.png',
        ),
      ],
    );

    await pumpReplyComposer(
      tester,
      replyTarget: target,
      onCancelReply: () {},
    );

    expect(find.text(l10n.beaconRoomReplyAttachmentExcerpt), findsOneWidget);
  });
}
