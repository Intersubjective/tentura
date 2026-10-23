// #498 — a message with no text (a photo with no caption, a file, a poll, a
// quoted fact) must still read as the latest message on the Requests card:
// "Nina: 📷 Photo · 1m", never "—" and never the older text message. The
// server sends the latest message's kind (`lastMessageKind`: image, file,
// poll, fact) beside its text; the client turns it into the label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/data/gql/_g/inbox_room_context_batch.data.gql.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_latest_message_line.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

MyWorkCardViewModel _vm({
  String text = '',
  String kind = 'image',
  int unread = 2,
}) => MyWorkCardViewModel(
  beaconId: 'B1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'B1', title: 'Moving day'),
  roomLatestMessageText: text,
  roomLatestMessageKind: kind,
  roomLatestMessageAuthorId: 'u-nina',
  roomLatestMessageAuthorName: 'Nina',
  roomLatestMessageAt: _now.subtract(const Duration(minutes: 1)),
  roomUnreadCount: unread,
);

Widget _line(MyWorkCardViewModel vm, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: MyWorkLatestMessageLine(
            vm: vm,
            currentUserId: 'u-me',
            now: _now.toLocal(),
          ),
        ),
      ),
    );

const _viewerId = 'helper-498';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

final class _NoDismissals implements OfferAcceptedDismissalPort {
  @override
  Future<Set<String>> load({required String viewerId}) async => {};

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async => {};
}

MyWorkHelpOfferedRow _helperRow(Beacon beacon) => (
  beacon: beacon,
  offerHelpMessage: 'I can help',
  helpType: null,
  authorResponseType: null,
  stakeState: CommitmentStakeState.none,
  forwarderSenders: const <Profile>[],
  helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
  authorCoordinationUpdatedAt: null,
  coordinationAuthor: null,
);

void main() {
  group('latest line labels a message without text', () {
    const cases = <String, (String, String)>{
      'image': ('📷 Photo', '📷 Фото'),
      'file': ('📎 File', '📎 Файл'),
      'poll': ('📊 Poll', '📊 Опрос'),
      'fact': ('📌 Fact', '📌 Факт'),
    };
    for (final MapEntry(key: kind, value: (en, ru)) in cases.entries) {
      testWidgets('$kind reads "$en"', (tester) async {
        await tester.pumpWidget(_line(_vm(kind: kind)));
        await tester.pumpAndSettle();
        expect(find.textContaining('Nina: $en'), findsOneWidget);
        expect(find.textContaining('—'), findsNothing);
        expect(find.text('2 new'), findsOneWidget);
      });

      testWidgets('$kind reads "$ru" in ru', (tester) async {
        await tester.pumpWidget(
          _line(_vm(kind: kind), locale: const Locale('ru')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Nina: $ru'), findsOneWidget);
        expect(find.textContaining('—'), findsNothing);
      });
    }
  });

  testWidgets('a photo with a caption shows the caption, not "Photo"', (
    tester,
  ) async {
    await tester.pumpWidget(_line(_vm(text: 'The van is here')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nina: The van is here'), findsOneWidget);
    expect(find.textContaining('Photo'), findsNothing);
  });

  testWidgets('guard: no text and no kind still renders nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_line(_vm(kind: '')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nina'), findsNothing);
  });

  testWidgets('screen readers hear the photo label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_line(_vm()));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Latest message\. Nina: (📷 )?Photo\b.*2 new$'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('the batch row carries lastMessageKind from the wire', () {
    final row = GInboxRoomContextBatchData_InboxRoomContextBatch.fromJson({
      '__typename': 'v2_InboxRoomContextRow',
      'beaconId': 'B1',
      'isRoomMember': true,
      'roomUnreadCount': 0,
      'lastMessageKind': 'image',
    });
    expect(row!.lastMessageKind, 'image');
  });

  test('MyWorkCase carries the kind onto the card, and the unread count '
      'rides on the latest line instead of the header', () async {
    final beacon = Beacon.empty.copyWith(
      id: 'b1',
      status: BeaconStatus.open,
      updatedAt: DateTime(2025, 6),
    );
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [beacon],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 0,
      );
    final hints = FakeRoomHints()
      ..hintsByBeaconId = {
        'b1': InboxRoomCardHints(
          isRoomMember: true,
          roomUnreadCount: 1,
          lastMessageAt: DateTime.utc(2026, 10, 14, 11),
          lastMessageKind: 'image',
          lastMessageAuthorId: 'u-nina',
          lastMessageAuthorName: 'Nina',
        ),
      };
    final case_ = buildTestMyWorkCase(repo: repo, roomHints: hints);

    final card = (await case_.loadDeskInit(
      userId: 'u1',
    )).nonArchivedCards.single;
    expect(card.roomLatestMessageKind, 'image');
    expect(card.roomLatestMessageAuthorName, 'Nina');
    expect(card.roomUnreadCount, 1);
    // The "1 new" sits on the latest line; no second "+1" in the header.
    expect(card.roomInboxSubtitle, isEmpty);
  });

  group('Requests card', () {
    setUp(() {
      if (!GetIt.I.isRegistered<Logger>()) {
        GetIt.I.registerSingleton<Logger>(Logger('issue498'));
      }
      if (!GetIt.I.isRegistered<BeaconRepository>()) {
        GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
      }
      if (!GetIt.I.isRegistered<ClosureRepository>()) {
        GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
      }
      if (!GetIt.I.isRegistered<OfferAcceptedDismissals>()) {
        GetIt.I.registerSingleton<OfferAcceptedDismissals>(
          OfferAcceptedDismissals(_NoDismissals()),
        );
      }
    });

    tearDown(() {
      for (final unregister in <void Function()>[
        if (GetIt.I.isRegistered<BeaconRepository>())
          GetIt.I.unregister<BeaconRepository>,
        if (GetIt.I.isRegistered<ClosureRepository>())
          GetIt.I.unregister<ClosureRepository>,
        if (GetIt.I.isRegistered<OfferAcceptedDismissals>())
          GetIt.I.unregister<OfferAcceptedDismissals>,
      ]) {
        unregister();
      }
    });

    testWidgets('a photo-only latest message shows "📷 Photo" on the card', (
      tester,
    ) async {
      final beacon = Beacon.empty.copyWith(
        id: 'open-498',
        title: 'Moving day',
        updatedAt: DateTime(2026, 9, 5),
        status: BeaconStatus.open,
        author: const Profile(id: 'auth', displayName: 'Author Co'),
      );
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: const <Beacon>[],
          helpOfferedNonArchived: [_helperRow(beacon)],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
      final hints = FakeRoomHints()
        ..hintsByBeaconId = {
          'open-498': InboxRoomCardHints(
            isRoomMember: true,
            roomUnreadCount: 0,
            lastMessageAt: DateTime.now().subtract(const Duration(minutes: 1)),
            lastMessageKind: 'image',
            lastMessageAuthorId: 'auth',
            lastMessageAuthorName: 'Author Co',
          ),
        };
      final cubit = MyWorkCubit(
        userId: _viewerId,
        myWorkCase: buildTestMyWorkCase(repo: repo, roomHints: hints),
      );
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((s) => s.isSuccess);

      tester.view
        ..physicalSize = const Size(400, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: TenturaResponsiveScope(
            child: MultiBlocProvider(
              providers: [
                BlocProvider<MyWorkCubit>.value(value: cubit),
                BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
                BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
              ],
              child: Scaffold(
                body: BlocBuilder<MyWorkCubit, MyWorkState>(
                  builder: (context, state) => ListView(
                    children: [
                      for (final vm in state.nonArchivedCards)
                        MyWorkCardRouter(vm: vm),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final line = find.byType(MyWorkLatestMessageLine);
      expect(line, findsOneWidget);
      expect(
        find.descendant(
          of: line,
          matching: find.textContaining('Author Co: 📷 Photo'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: line, matching: find.textContaining('—')),
        findsNothing,
      );
    });
  });
}
