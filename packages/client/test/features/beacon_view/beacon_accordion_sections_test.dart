import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_people_row.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_accordion_sections.dart';

BeaconPeopleRow _row(String id) => BeaconPeopleRow(
      userId: id,
      profile: Profile(id: id, displayName: id),
    );

void main() {
  group('itemsTabAccordionSectionId', () {
    test('focus in drafts wins', () {
      expect(
        itemsTabAccordionSectionId(
          focusInDrafts: true,
          focusInClosed: true,
          showActiveFold: true,
          showClosedFold: true,
          showDrafts: true,
          showFacts: true,
        ),
        BeaconItemsAccordionSection.drafts,
      );
    });

    test('focus in closed when no draft focus', () {
      expect(
        itemsTabAccordionSectionId(
          focusInDrafts: false,
          focusInClosed: true,
          showActiveFold: true,
          showClosedFold: true,
          showDrafts: false,
          showFacts: false,
        ),
        BeaconItemsAccordionSection.closed,
      );
    });

    test('defaults to active when visible', () {
      expect(
        itemsTabAccordionSectionId(
          focusInDrafts: false,
          focusInClosed: false,
          showActiveFold: true,
          showClosedFold: true,
          showDrafts: false,
          showFacts: false,
        ),
        BeaconItemsAccordionSection.active,
      );
    });

    test('falls through to null when no folds', () {
      expect(
        itemsTabAccordionSectionId(
          focusInDrafts: false,
          focusInClosed: false,
          showActiveFold: false,
          showClosedFold: false,
          showDrafts: false,
          showFacts: false,
        ),
        isNull,
      );
    });
  });

  group('peopleTabAccordionSectionId', () {
    test('focus user in not fitting section', () {
      final sections = BeaconPeopleSections(
        activeHelpers: [_row('auth')],
        willingToHelp: [_row('w1')],
        notFitting: [_row('nf1')],
      );
      expect(
        peopleTabAccordionSectionId(
          sections: sections,
          focusUserId: 'nf1',
          showWithdrawn: false,
        ),
        BeaconPeopleAccordionSection.notFitting,
      );
    });

    test('first non-empty section when no focus', () {
      final sections = BeaconPeopleSections(
        activeHelpers: [_row('auth')],
        willingToHelp: [_row('w1')],
      );
      expect(
        peopleTabAccordionSectionId(
          sections: sections,
          focusUserId: null,
          showWithdrawn: false,
        ),
        BeaconPeopleAccordionSection.activeHelpers,
      );
    });
  });
}
