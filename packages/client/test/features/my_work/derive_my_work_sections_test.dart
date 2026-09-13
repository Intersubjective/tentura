import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_sections.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_state.dart';

MyWorkCardViewModel _vm({
  required String id,
  required MyWorkCardKind kind,
  MyWorkCardRole role = MyWorkCardRole.authored,
}) {
  return MyWorkCardViewModel(
    beaconId: id,
    role: role,
    kind: kind,
    beacon: Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime.utc(2026, 9, id.hashCode % 28 + 1),
      status: kind == MyWorkCardKind.authoredFinished
          ? BeaconStatus.closed
          : BeaconStatus.open,
    ),
  );
}

AttentionReceipt _obligation(String id, String beaconId) => AttentionReceipt(
  id: id,
  category: 'asksOfMe',
  kind: 'needsMe',
  priority: 'normal',
  title: 'Obligation',
  body: 'Body',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: beaconId,
  requiresAction: true,
);

void main() {
  test('sections follow Needs you → In progress → Finished with counts', () {
    final needs = _vm(id: 'n', kind: MyWorkCardKind.authoredActive);
    final progress = _vm(id: 'p', kind: MyWorkCardKind.helpOfferedActive);
    final finished = _vm(id: 'f', kind: MyWorkCardKind.authoredFinished);
    final attention = {
      'n': MyWorkBeaconAttention(
        beaconId: 'n',
        unseenCount: 0,
        liveObligations: [
          _obligation('r1', 'n'),
          _obligation('r2', 'n'),
        ],
      ),
    };
    final cards = [finished, progress, needs];

    final groups = deriveMyWorkSections(
      cards: cards,
      attentionByBeacon: attention,
      filter: MyWorkFilter.active,
    );

    expect(groups.map((g) => g.section).toList(), [
      MyWorkDeskSection.needsYou,
      MyWorkDeskSection.inProgress,
      MyWorkDeskSection.finished,
    ]);
    expect(groups[0].cards.map((c) => c.beaconId), ['n']);
    expect(groups[1].cards.map((c) => c.beaconId), ['p']);
    expect(groups[2].cards.map((c) => c.beaconId), ['f']);
    expect(
      myWorkNeedsYouObligationReceiptCount(groups[0].cards, attention),
      2,
    );
  });

  test('finished card with live obligation lands in Needs you only', () {
    final finishedWithObligation = _vm(
      id: 'fin',
      kind: MyWorkCardKind.authoredFinished,
    );
    final attention = {
      'fin': MyWorkBeaconAttention(
        beaconId: 'fin',
        unseenCount: 0,
        liveObligations: [_obligation('r', 'fin')],
      ),
    };

    final groups = deriveMyWorkSections(
      cards: [finishedWithObligation],
      attentionByBeacon: attention,
      filter: MyWorkFilter.all,
    );

    expect(groups.length, 1);
    expect(groups.single.section, MyWorkDeskSection.needsYou);
    expect(groups.single.cards.single.beaconId, 'fin');
  });

  test('drafts filter returns one unlabeled section', () {
    final draft = _vm(id: 'd', kind: MyWorkCardKind.authoredDraft);
    final groups = deriveMyWorkSections(
      cards: [draft],
      attentionByBeacon: const {},
      filter: MyWorkFilter.drafts,
    );
    expect(groups.single.section, MyWorkDeskSection.unlabeled);
    expect(groups.single.cards, [draft]);
  });

  test('no live obligations omits Needs you section', () {
    final progress = _vm(id: 'p', kind: MyWorkCardKind.authoredActive);
    final groups = deriveMyWorkSections(
      cards: [progress],
      attentionByBeacon: const {},
      filter: MyWorkFilter.active,
    );
    expect(groups.map((g) => g.section), [MyWorkDeskSection.inProgress]);
  });
}
