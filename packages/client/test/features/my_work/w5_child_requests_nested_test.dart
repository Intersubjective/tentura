import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/fetch_by_id_batches.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_sections.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';

/// W5 — #487: a child Request is listed under its parent (not as an
/// unrelated sibling), and #525: every card gets its activity, however many
/// Requests are on the list.
MyWorkCardViewModel _vm(
  String id, {
  String parent = '',
  bool finished = false,
}) => MyWorkCardViewModel(
  beaconId: id,
  role: MyWorkCardRole.authored,
  kind: finished
      ? MyWorkCardKind.authoredFinished
      : MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(
    id: id,
    status: finished ? BeaconStatus.closed : BeaconStatus.open,
  ),
  parentBeaconId: parent,
  parentTitle: parent.isEmpty ? '' : 'Title of $parent',
);

List<String> _ids(MyWorkDeskSectionGroup g) => [
  for (final c in g.cards) c.beaconId,
];

MyWorkDeskSectionGroup _inProgress(List<MyWorkCardViewModel> ordered) =>
    deriveMyWorkSections(
      cards: ordered,
      attentionByBeacon: const {},
      filter: MyWorkFilter.active,
    ).single;

void main() {
  group('nestMyWorkChildCards (#487)', () {
    test('a child is listed right under its parent, one level in', () {
      final g = _inProgress([
        _vm('parent'),
        _vm('other'),
        _vm('child', parent: 'parent'),
      ]);
      expect(_ids(g), ['parent', 'child', 'other']);
      expect(g.depthOf('parent'), 0);
      expect(g.depthOf('child'), 1);
      expect(g.depthOf('other'), 0);
    });

    test('a busy child lifts its family to its own place (#525)', () {
      // "Recent" put the child first: the family takes that place, with the
      // parent heading it.
      final g = _inProgress([
        _vm('child', parent: 'parent'),
        _vm('other'),
        _vm('parent'),
      ]);
      expect(_ids(g), ['parent', 'child', 'other']);
    });

    test('siblings keep the sort order; a grandchild is two levels in', () {
      final g = _inProgress([
        _vm('grandchild', parent: 'childB'),
        _vm('childA', parent: 'root'),
        _vm('root'),
        _vm('childB', parent: 'root'),
      ]);
      expect(_ids(g), ['root', 'childB', 'grandchild', 'childA']);
      expect(g.depthOf('childB'), 1);
      expect(g.depthOf('grandchild'), 2);
      expect(g.depthOf('childA'), 1);
    });

    test('a child whose parent is not listed stays where the sort put it', () {
      final g = _inProgress([
        _vm('a'),
        _vm('child', parent: 'unlisted'),
        _vm('b'),
      ]);
      expect(_ids(g), ['a', 'child', 'b']);
      expect(g.depthOf('child'), 0);
    });

    test('families do not reach across sections', () {
      final sections = deriveMyWorkSections(
        cards: [
          _vm('child', parent: 'parent'),
          _vm('parent', finished: true),
        ],
        attentionByBeacon: const {},
        filter: MyWorkFilter.active,
      );
      expect(sections.map((s) => s.section), [
        MyWorkDeskSection.inProgress,
        MyWorkDeskSection.finished,
      ]);
      expect(sections.first.depthOf('child'), 0);
    });

    test('a parent cycle cannot hide cards', () {
      final g = _inProgress([
        _vm('a', parent: 'b'),
        _vm('b', parent: 'a'),
        _vm('c'),
      ]);
      expect(_ids(g), unorderedEquals(['a', 'b', 'c']));
    });

    test('a flat list is returned as it is', () {
      final cards = [_vm('a'), _vm('b')];
      final g = _inProgress(cards);
      expect(_ids(g), ['a', 'b']);
      expect(g.nestingDepth, isEmpty);
    });
  });

  group('fetchByIdBatches (#525)', () {
    test(
      'reads past 80 ids in batches the server serves, and merges',
      () async {
        final ids = [for (var i = 0; i < 170; i++) 'B$i'];
        final batches = <List<String>>[];
        final out = await fetchByIdBatches<int>(ids, (batch) async {
          batches.add(batch);
          return {for (final id in batch) id: int.parse(id.substring(1))};
        });
        expect(batches.map((b) => b.length), [80, 80, 10]);
        expect(out.length, 170);
        expect(out['B169'], 169);
      },
    );

    test('no ids: no read', () async {
      var calls = 0;
      final out = await fetchByIdBatches<int>(const [], (batch) async {
        calls++;
        return {};
      });
      expect(out, isEmpty);
      expect(calls, 0);
    });
  });
}
