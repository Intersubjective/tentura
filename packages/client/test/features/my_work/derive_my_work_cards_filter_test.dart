import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _vm({
  required String id,
  required MyWorkCardRole role,
  required MyWorkCardKind kind,
  BeaconStatus status = BeaconStatus.open,
}) {
  final beacon = Beacon.empty.copyWith(
    id: id,
    updatedAt: DateTime(2025),
    status: status,
  );
  return MyWorkCardViewModel(
    beaconId: id,
    role: role,
    kind: kind,
    beacon: beacon,
  );
}

void main() {
  group('visibleMyWorkCardsForDesk', () {
    final active = _vm(
      id: 'a',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
    );
    final draft = _vm(
      id: 'd',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredDraft,
      status: BeaconStatus.draft,
    );
    final help = _vm(
      id: 'h',
      role: MyWorkCardRole.helpOffered,
      kind: MyWorkCardKind.helpOfferedActive,
    );
    final archived = _vm(
      id: 'x',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredFinished,
      status: BeaconStatus.closed,
    );
    final cards = [active, draft, help];

    test('active excludes drafts', () {
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.active,
        sort: MyWorkSort.recent,
        nonArchivedCards: cards,
        archivedCards: [archived],
      );
      expect(visible.map((e) => e.beaconId).toList(), ['a', 'h']);
    });

    test('drafts filter shows drafts only', () {
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.drafts,
        sort: MyWorkSort.recent,
        nonArchivedCards: cards,
        archivedCards: const [],
      );
      expect(visible.single.beaconId, 'd');
    });

    test('authored excludes drafts', () {
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.authored,
        sort: MyWorkSort.recent,
        nonArchivedCards: cards,
        archivedCards: const [],
      );
      expect(visible.single.beaconId, 'a');
    });

    test('all includes drafts', () {
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.all,
        sort: MyWorkSort.recent,
        nonArchivedCards: cards,
        archivedCards: const [],
      );
      expect(visible.length, 3);
    });
  });

  test('countDraftMyWorkCards counts authoredDraft only', () {
    final cards = [
      _vm(
        id: 'd1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredDraft,
        status: BeaconStatus.draft,
      ),
      _vm(
        id: 'a1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
      ),
    ];
    expect(countDraftMyWorkCards(cards), 1);
  });

  group('upsertAuthoredMyWorkCard', () {
    test('inserts new authored card sorted by tier', () {
      final existing = _vm(
        id: 'old',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
      );
      final beacon = Beacon.empty.copyWith(
        id: 'new',
        title: 'New',
        status: BeaconStatus.open,
        updatedAt: DateTime(2025, 8),
      );
      final merged = upsertAuthoredMyWorkCard([existing], beacon);
      expect(merged.map((c) => c.beaconId), ['new', 'old']);
      expect(merged.first.kind, MyWorkCardKind.authoredActive);
    });

    test('replaces existing card for same beacon id', () {
      final existing = _vm(
        id: 'b1',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredDraft,
        status: BeaconStatus.draft,
      );
      final beacon = Beacon.empty.copyWith(
        id: 'b1',
        status: BeaconStatus.open,
        updatedAt: DateTime(2025, 9),
      );
      final merged = upsertAuthoredMyWorkCard([existing], beacon);
      expect(merged, hasLength(1));
      expect(merged.single.kind, MyWorkCardKind.authoredActive);
    });
  });

  group('mergeMyWorkDeskCards', () {
    test('returns server list when preferIds is empty', () {
      final server = [
        _vm(
          id: 's1',
          role: MyWorkCardRole.authored,
          kind: MyWorkCardKind.authoredActive,
        ),
      ];
      final local = [
        _vm(
          id: 'l1',
          role: MyWorkCardRole.authored,
          kind: MyWorkCardKind.authoredActive,
        ),
      ];
      expect(
        mergeMyWorkDeskCards(
          serverCards: server,
          localCards: local,
          preferIds: const {},
        ),
        server,
      );
    });

    test('preserves local card when server omits pending id', () {
      final server = [
        _vm(
          id: 'b1',
          role: MyWorkCardRole.authored,
          kind: MyWorkCardKind.authoredActive,
        ),
      ];
      final localPending = _vm(
        id: 'b-new',
        role: MyWorkCardRole.authored,
        kind: MyWorkCardKind.authoredActive,
      );
      final merged = mergeMyWorkDeskCards(
        serverCards: server,
        localCards: [server.single, localPending],
        preferIds: {'b-new'},
      );
      expect(merged.map((c) => c.beaconId), containsAll(['b1', 'b-new']));
    });
  });

  test('maxMyWorkDeskActivityEpochMs picks max across lists', () {
    final a = _vm(
      id: 'a',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredActive,
    ).copyWith(
      beacon: Beacon.empty.copyWith(
        id: 'a',
        createdAt: DateTime.fromMillisecondsSinceEpoch(100),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(500),
      ),
    );
    final b = _vm(
      id: 'b',
      role: MyWorkCardRole.authored,
      kind: MyWorkCardKind.authoredFinished,
      status: BeaconStatus.closed,
    ).copyWith(
      beacon: Beacon.empty.copyWith(
        id: 'b',
        createdAt: DateTime.fromMillisecondsSinceEpoch(100),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(900),
      ),
    );
    expect(
      maxMyWorkDeskActivityEpochMs(nonArchivedCards: [a], archivedCards: [b]),
      900,
    );
  });
}
