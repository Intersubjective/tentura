// #487 residuals (QA, r8).
//
// 1. A Request in Final check printed its flag ("Next step") row as a bare
//    "—": the desk NOW row fell back to the neutral coordination label. That
//    is a placeholder, so the row is hidden like the no-next-step case.
// 2. A just-created child Request showed "Part of: <parent>" only after the
//    next list load: the local card kept over the server row after the
//    create had no parent link, and an edit dropped the one already read.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_metadata_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

import 'my_work_test_support.dart';

const _viewerId = 'viewer';
const _parentId = 'b-couch';
const _childId = 'b-straps';
const _parentTitle = 'Need a hand moving a couch';
const _childTitle = 'Child: borrow moving straps';

Beacon _beacon(
  String id,
  String title, {
  BeaconStatus status = BeaconStatus.open,
  DateTime? updatedAt,
}) => Beacon.empty.copyWith(
  id: id,
  title: title,
  status: status,
  updatedAt: updatedAt ?? DateTime(2026, 10),
  author: const Profile(id: _viewerId, displayName: 'Vadim'),
);

Future<void> _pumpRow(WidgetTester tester, MyWorkCardViewModel vm) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(480, 800)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: MyWorkCardMetadataRow(
                beacon: vm.beacon,
                viewModel: vm,
                currentUserId: _viewerId,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MyWorkCardViewModel _authored(Beacon beacon, {String currentLine = ''}) =>
    MyWorkCardViewModel(
      beaconId: beacon.id,
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
      beacon: beacon,
      roomCurrentLine: currentLine,
    );

void main() {
  group('Final check: no "—" flag row', () {
    test('the desk NOW display in Final check is a placeholder', () {
      final display = myWorkDeskNowDisplay(
        L10nEn(),
        beacon: _beacon(
          _parentId,
          _parentTitle,
          status: BeaconStatus.reviewOpen,
        ),
        roomCurrentLine: '',
      );
      expect(display.isPlaceholder, isTrue);
      expect(display.blockerText, isNull);
    });

    testWidgets('a Request in Final check shows no flag row', (tester) async {
      await _pumpRow(
        tester,
        _authored(
          _beacon(_parentId, _parentTitle, status: BeaconStatus.reviewOpen),
        ),
      );

      expect(find.byIcon(BeaconHudRowIcons.now), findsNothing);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('guard: an open Request with a next step keeps its row', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        _authored(
          _beacon(_parentId, _parentTitle),
          currentLine: 'Pick up the van at noon',
        ),
      );

      expect(find.byIcon(BeaconHudRowIcons.now), findsOneWidget);
      expect(find.textContaining('Pick up the van at noon'), findsOneWidget);
    });
  });

  group('a new child Request names its parent at once', () {
    final parent = _beacon(_parentId, _parentTitle);
    final child = _beacon(
      _childId,
      _childTitle,
      updatedAt: DateTime(2026, 10, 2),
    );

    test('a local card kept over the server row takes its parent link', () {
      final local = upsertAuthoredMyWorkCard(const [], child);
      final server = _authored(child).copyWith(
        parentBeaconId: _parentId,
        parentTitle: _parentTitle,
      );

      final merged = mergeMyWorkDeskCards(
        serverCards: [server],
        localCards: local,
        preferIds: {_childId},
      );

      expect(merged.single.parentBeaconId, _parentId);
      expect(merged.single.parentTitle, _parentTitle);
    });

    test('an edit keeps the parent link the list already read', () {
      final loaded = _authored(child).copyWith(
        parentBeaconId: _parentId,
        parentTitle: _parentTitle,
      );

      final cards = upsertAuthoredMyWorkCard(
        [loaded],
        child.copyWith(title: 'Child: borrow straps and a dolly'),
      );

      expect(cards.single.parentBeaconId, _parentId);
      expect(cards.single.parentTitle, _parentTitle);
    });

    test('guard: a top-level Request gets no parent link', () {
      final cards = upsertAuthoredMyWorkCard(const [], parent);
      expect(cards.single.parentBeaconId, isEmpty);
      expect(cards.single.parentTitle, isEmpty);
    });

    test(
      'the desk shows the parent link right after the child is created',
      () async {
        final repo = FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: [parent],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          );
        final beaconRepo = FakeBeaconRepository();
        final hints = FakeRoomHints()
          ..hintsByBeaconId = {
            _parentId: const InboxRoomCardHints(
              isRoomMember: true,
              roomUnreadCount: 0,
            ),
            _childId: const InboxRoomCardHints(
              isRoomMember: true,
              roomUnreadCount: 0,
              parentBeaconId: _parentId,
              parentTitle: _parentTitle,
            ),
          };
        final cubit = MyWorkCubit(
          userId: _viewerId,
          myWorkCase: buildTestMyWorkCase(
            repo: repo,
            beaconRepo: beaconRepo,
            roomHints: hints,
          ),
        );
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((s) => s.isSuccess);

        // The server now lists the child, as of the same moment the create
        // returned (the read is not newer than the local copy).
        repo.initResult = (
          authoredNonArchived: [parent, child],
          helpOfferedNonArchived: const [],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
        final callsBefore = repo.fetchInitCallCount;
        beaconRepo.emitChange(RepositoryEventCreate(child));
        // Settle the refresh the create starts (and any queued behind it).
        for (var i = 0; i < 20; i++) {
          await pumpEventQueue();
        }
        expect(repo.fetchInitCallCount, greaterThan(callsBefore));

        final card = cubit.state.nonArchivedCards.singleWhere(
          (c) => c.beaconId == _childId,
        );
        expect(card.parentBeaconId, _parentId);
        expect(card.parentTitle, _parentTitle);
      },
    );
  });
}
