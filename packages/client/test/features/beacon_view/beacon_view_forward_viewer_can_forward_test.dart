import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_forward_overflow.dart';

BeaconViewState _state({required bool viewerCanForward}) {
  final t = DateTime.utc(2026, 6, 20);
  return BeaconViewState(
    beacon: Beacon(
      id: 'b1',
      author: const Profile(id: 'uAuthor', displayName: 'Author'),
      createdAt: t,
      updatedAt: t,
      viewerCanForward: viewerCanForward,
    ),
    myProfile: const Profile(id: 'uViewer', displayName: 'Viewer'),
    beaconContextLoaded: true,
  );
}

void main() {
  group('beaconViewAllowsForwardAction follows the server forward verdict', () {
    test('hidden for an open Request the viewer may not forward', () {
      expect(
        beaconViewAllowsForwardAction(
          state: _state(viewerCanForward: false),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isFalse,
      );
    });

    test('shown for an open Request the viewer may forward', () {
      expect(
        beaconViewAllowsForwardAction(
          state: _state(viewerCanForward: true),
          showBeaconContent: true,
          showInitialLoading: false,
        ),
        isTrue,
      );
    });
  });
}
