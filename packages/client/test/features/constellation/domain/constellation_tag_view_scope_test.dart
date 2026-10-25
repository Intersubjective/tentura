// The tag view shows the members of the viewed tags (own tags and automatic
// ones alike); everyone else is hidden, drawn as dots, or left as the Field
// shows them. The entry to the tag view exists only while both the people-tags
// and the Field-arrange feature flags are on.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/constellation_tag_view_scope.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

const _ann = ConstellationPerson(id: 'ann', displayName: 'Ann');
const _bob = ConstellationPerson(
  id: 'bob',
  displayName: 'Bob',
  autoTagKinds: {ConstellationAutoTagKind.iTrust},
);
const _cid = ConstellationPerson(
  id: 'cid',
  displayName: 'Cid',
  autoTagKinds: {
    ConstellationAutoTagKind.iTrust,
    ConstellationAutoTagKind.trustsMe,
  },
);
const _dan = ConstellationPerson(id: 'dan', displayName: 'Dan');
const _people = [_ann, _bob, _cid, _dan];

Set<String> _ownTagsOf(String personId) => switch (personId) {
  'ann' => {'neighbour', 'garden'},
  'bob' => {'garden'},
  _ => const {},
};

ConstellationTagViewScope _scope(
  ConstellationTagFilter filter, {
  ConstellationTagViewOthers others = ConstellationTagViewOthers.dots,
}) => resolveConstellationTagViewScope(
  filter: filter,
  people: _people,
  ownTagIdsOf: _ownTagsOf,
  others: others,
);

void main() {
  group('who the tag view shows', () {
    test('an own tag shows exactly its members', () {
      final scope = _scope(
        const ConstellationTagFilter(selectedOwn: {'garden'}),
      );

      expect(scope.memberIds, {'ann', 'bob'});
    });

    test('an automatic tag works like an own tag', () {
      final scope = _scope(
        const ConstellationTagFilter(
          selectedAuto: {ConstellationAutoTagKind.iTrust},
        ),
      );

      expect(scope.memberIds, {'bob', 'cid'});
    });

    test('several tags follow the any / all choice of the filter', () {
      const own = {'neighbour', 'garden'};

      expect(
        _scope(const ConstellationTagFilter(selectedOwn: own)).memberIds,
        {'ann', 'bob'},
      );
      expect(
        _scope(
          const ConstellationTagFilter(
            selectedOwn: own,
            mode: ConstellationTagFilterMode.and,
          ),
        ).memberIds,
        {'ann'},
      );
    });

    test('an own tag together with an automatic tag combines both', () {
      final scope = _scope(
        const ConstellationTagFilter(
          selectedOwn: {'neighbour'},
          selectedAuto: {ConstellationAutoTagKind.trustsMe},
        ),
      );

      expect(scope.memberIds, {'ann', 'cid'});
    });
  });

  group('what happens to everyone else', () {
    const garden = ConstellationTagFilter(selectedOwn: {'garden'});

    test('hide: non-members are hidden and nothing is a dot', () {
      final scope = _scope(garden, others: ConstellationTagViewOthers.hide);

      expect(scope.hiddenIds, {'cid', 'dan'});
      expect(scope.dotIds, isEmpty);
      expect(scope.othersAsIsIds, isEmpty);
    });

    test('dots: non-members become dots and none is hidden', () {
      final scope = _scope(garden, others: ConstellationTagViewOthers.dots);

      expect(scope.dotIds, {'cid', 'dan'});
      expect(scope.hiddenIds, isEmpty);
      expect(scope.othersAsIsIds, isEmpty);
    });

    test('as is: non-members stay as the Field shows them', () {
      final scope = _scope(garden, others: ConstellationTagViewOthers.asIs);

      expect(scope.othersAsIsIds, {'cid', 'dan'});
      expect(scope.hiddenIds, isEmpty);
      expect(scope.dotIds, isEmpty);
    });

    test('a member is never hidden or a dot', () {
      for (final others in ConstellationTagViewOthers.values) {
        final scope = _scope(garden, others: others);

        expect(scope.memberIds.intersection(scope.hiddenIds), isEmpty);
        expect(scope.memberIds.intersection(scope.dotIds), isEmpty);
        expect(scope.memberIds.intersection(scope.othersAsIsIds), isEmpty);
      }
    });
  });

  group('when "Open tag view" is offered', () {
    test('only with both people tags and Field arrange on', () {
      bool offered(bool tags, bool arrange) =>
          constellationTagViewEntryAvailable(
            peopleTagsEnabled: tags,
            arrangeV2Enabled: arrange,
          );

      expect(offered(true, true), isTrue);
      expect(offered(true, false), isFalse);
      expect(offered(false, true), isFalse);
      expect(offered(false, false), isFalse);
    });
  });
}
