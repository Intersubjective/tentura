import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_involved_profiles.dart';
import 'package:tentura/domain/entity/profile.dart';

void main() {
  test('orderBeaconInvolvedProfiles puts author first and skips duplicate', () {
    const author = Profile(id: 'a', displayName: 'Author');
    const helper = Profile(id: 'h', displayName: 'Helper');
    final ordered = orderBeaconInvolvedProfiles(author, [author, helper]);
    expect(ordered.map((p) => p.id).toList(), ['a', 'h']);
  });

  test('beaconInvolvedPeopleDisplay caps visible and computes overflow', () {
    const author = Profile(id: 'a', displayName: 'Author');
    final helpers = [
      const Profile(id: 'h1', displayName: 'H1'),
      const Profile(id: 'h2', displayName: 'H2'),
      const Profile(id: 'h3', displayName: 'H3'),
      const Profile(id: 'h4', displayName: 'H4'),
    ];
    final display = beaconInvolvedPeopleDisplay(
      author: author,
      helpOfferUsers: helpers,
      helpOfferCount: 4,
    );
    expect(display.visible.length, kBeaconInvolvedPeopleMaxVisible);
    expect(display.overflow, 2);
  });

  test('involvedPeopleDisplayFromOrdered uses ordered length when total omitted', () {
    final profiles = [
      const Profile(id: 'a', displayName: 'A'),
      const Profile(id: 'b', displayName: 'B'),
      const Profile(id: 'c', displayName: 'C'),
      const Profile(id: 'd', displayName: 'D'),
    ];
    final display = involvedPeopleDisplayFromOrdered(ordered: profiles);
    expect(display.visible.length, kBeaconInvolvedPeopleMaxVisible);
    expect(display.overflow, 1);
  });

  test('involvedPeopleDisplayFromOrdered respects explicit totalCount', () {
    final profiles = [
      const Profile(id: 'a', displayName: 'A'),
      const Profile(id: 'b', displayName: 'B'),
    ];
    final display = involvedPeopleDisplayFromOrdered(
      ordered: profiles,
      totalCount: 6,
    );
    expect(display.visible.length, 2);
    expect(display.overflow, 4);
  });
}
