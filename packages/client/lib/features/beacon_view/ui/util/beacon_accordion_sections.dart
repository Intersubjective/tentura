import 'package:tentura/domain/entity/beacon_people_row.dart';

/// Stable accordion section ids for the beacon Items tab.
abstract final class BeaconItemsAccordionSection {
  static const active = 'active';
  static const closed = 'closed';
  static const drafts = 'drafts';
  static const facts = 'facts';
}

/// Stable accordion section ids for the beacon People tab.
abstract final class BeaconPeopleAccordionSection {
  static const activeHelpers = 'activeHelpers';
  static const willingToHelp = 'willingToHelp';
  static const notFitting = 'notFitting';
  static const withdrawn = 'withdrawn';
}

/// Which Items fold should be open on compact (focus-aware).
String? itemsTabAccordionSectionId({
  required bool focusInDrafts,
  required bool focusInClosed,
  required bool showActiveFold,
  required bool showClosedFold,
  required bool showDrafts,
  required bool showFacts,
}) {
  if (focusInDrafts && showDrafts) {
    return BeaconItemsAccordionSection.drafts;
  }
  if (focusInClosed && showClosedFold) {
    return BeaconItemsAccordionSection.closed;
  }
  if (showActiveFold) {
    return BeaconItemsAccordionSection.active;
  }
  if (showClosedFold) {
    return BeaconItemsAccordionSection.closed;
  }
  if (showDrafts) {
    return BeaconItemsAccordionSection.drafts;
  }
  if (showFacts) {
    return BeaconItemsAccordionSection.facts;
  }
  return null;
}

bool _sectionContainsUser(List<BeaconPeopleRow> rows, String userId) {
  for (final row in rows) {
    if (row.userId == userId) return true;
  }
  return false;
}

/// Which People fold should be open on compact (focus-aware).
String? peopleTabAccordionSectionId({
  required BeaconPeopleSections sections,
  required String? focusUserId,
  required bool showWithdrawn,
}) {
  final focus = focusUserId?.trim();
  if (focus != null && focus.isNotEmpty) {
    if (_sectionContainsUser(sections.activeHelpers, focus)) {
      return BeaconPeopleAccordionSection.activeHelpers;
    }
    if (_sectionContainsUser(sections.willingToHelp, focus)) {
      return BeaconPeopleAccordionSection.willingToHelp;
    }
    if (_sectionContainsUser(sections.notFitting, focus)) {
      return BeaconPeopleAccordionSection.notFitting;
    }
    if (showWithdrawn) {
      return BeaconPeopleAccordionSection.withdrawn;
    }
  }
  if (sections.activeHelpers.isNotEmpty) {
    return BeaconPeopleAccordionSection.activeHelpers;
  }
  if (sections.willingToHelp.isNotEmpty) {
    return BeaconPeopleAccordionSection.willingToHelp;
  }
  if (sections.notFitting.isNotEmpty) {
    return BeaconPeopleAccordionSection.notFitting;
  }
  if (showWithdrawn) {
    return BeaconPeopleAccordionSection.withdrawn;
  }
  return null;
}
