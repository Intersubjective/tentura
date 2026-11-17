import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit(this._state);

  final RoomState _state;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => const Stream<RoomState>.empty();

  @override
  Future<void> markReadToBottom() async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  _MockProfileCubit(this.profile);

  final Profile profile;

  @override
  ProfileState get state => ProfileState(profile: profile);

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

RoomMessage _message({
  int? semanticMarker,
  int? systemMessageKind,
  String? linkedPollingId,
  String? linkedFactCardId,
  String? threadItemId,
}) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'other',
  author: const Profile(id: 'other', displayName: 'Alex'),
  body: 'Hello room',
  createdAt: DateTime.utc(2026, 6, 30, 12),
  semanticMarker: semanticMarker,
  systemMessageKind: systemMessageKind,
  linkedPollingId: linkedPollingId,
  linkedFactCardId: linkedFactCardId,
  threadItemId: threadItemId,
);

class _RecordingNavigator extends Mock implements AppNavigator {
  final createBeaconCalls =
      <({String parentBeaconId, String sourceMessageId})>[];

  @override
  Future<void> createBeacon({
    String draftId = '',
    String editId = '',
    String initialTab = '',
    String forwardToUserId = '',
    String parentBeaconId = '',
    String sourceMessageId = '',
    String forkSourceId = '',
    String forkPlanTimes = '',
    List<String> forkFactIds = const [],
    Set<String> initialRecipientIds = const {},
    Map<String, String> initialNotes = const {},
    void Function(Set<String>, Map<String, String>)? onRecipientsChanged,
    VoidCallback? onPublished,
  }) async {
    createBeaconCalls.add((
      parentBeaconId: parentBeaconId,
      sourceMessageId: sourceMessageId,
    ));
  }
}

void main() {
  final navigator = _RecordingNavigator();
  setUp(navigator.createBeaconCalls.clear);
  const viewer = Profile(id: 'me', displayName: 'Me');

  Future<void> pumpRoom(
    WidgetTester tester, {
    required RoomMessage message,
  }) async {
    const viewport = Size(375, 667);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const mediaQuery = MediaQueryData(size: viewport);

    final profileCubit = _MockProfileCubit(viewer);
    final presenceCubit = _MockPresenceCubit();
    final roomCubit = _MockRoomCubit(
      RoomState(
        beaconId: 'b1',
        myUserId: viewer.id,
        beaconStatus: BeaconStatus.open,
        participants: [
          BeaconParticipant(
            id: 'p-me',
            beaconId: 'b1',
            userId: viewer.id,
            role: BeaconParticipantRoleBits.helper,
            status: 0,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            userTitle: viewer.displayName,
          ),
        ],
        participantsLoaded: true,
        messages: [message],
      ),
    );

    GetIt.I
      ..registerSingleton<AppNavigator>(navigator)
      ..registerSingleton<ProfileCubit>(profileCubit)
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );
    addTearDown(GetIt.I.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<RoomCubit>.value(value: roomCubit),
          BlocProvider<ProfileCubit>.value(value: profileCubit),
          BlocProvider<PresenceCubit>.value(value: presenceCubit),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const MediaQuery(
            data: mediaQuery,
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BeaconRoomBody(enableComposer: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<bool> createChildOffered(
    WidgetTester tester,
    RoomMessage message,
  ) async {
    final l10n = lookupL10n(const Locale('en'));
    await pumpRoom(tester, message: message);
    final target = find.text('Hello room');
    if (target.evaluate().isEmpty) {
      // Messages without a text body (poll / system lines) open the sheet
      // from their tile.
      await tester.longPress(find.byType(RoomMessageTile).first);
    } else {
      await tester.longPress(target.first);
    }
    await tester.pumpAndSettle();
    // The sheet must really be open (it lists tiles) before its absence of
    // the create-child tile means anything.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsWidgets,
      reason: 'the action sheet must list actions',
    );
    return find.text(l10n.beaconCreateChildRequest).evaluate().isNotEmpty;
  }

  group('Create child request is offered only for promotable messages', () {
    testWidgets('a plain authored message offers it and opens the composer '
        'for that message', (tester) async {
      expect(await createChildOffered(tester, _message()), isTrue);

      await tester.tap(
        find.text(lookupL10n(const Locale('en')).beaconCreateChildRequest),
      );
      await tester.pumpAndSettle();

      expect(navigator.createBeaconCalls, [
        (parentBeaconId: 'b1', sourceMessageId: 'm1'),
      ]);
    });

    testWidgets('a system line does not offer it', (tester) async {
      await pumpRoom(
        tester,
        message: _message(
          systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        ),
      );
      await tester.longPress(find.byType(RoomMessageTile).first);
      await tester.pumpAndSettle();

      final createChild = find.text(
        lookupL10n(const Locale('en')).beaconCreateChildRequest,
      );
      expect(createChild, findsNothing);
      expect(navigator.createBeaconCalls, isEmpty);
    });

    final ineligible = <String, RoomMessage>{
      'a poll message': _message(linkedPollingId: 'poll-1'),
      'a message with a semantic marker': _message(
        semanticMarker: BeaconRoomSemanticMarker.participantJoined,
      ),
      'a message pinned as a fact': _message(linkedFactCardId: 'fact-1'),
      'a thread-item message': _message(threadItemId: 'item-1'),
    };
    for (final entry in ineligible.entries) {
      testWidgets('${entry.key} does not offer it', (tester) async {
        expect(entry.value.isPromotionEligible(), isFalse);
        expect(await createChildOffered(tester, entry.value), isFalse);
      });
    }
  });
}
