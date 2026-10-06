import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/plan_assignable_people.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

/// [planAssignablePeople] of the Request [state] shows.
List<Profile> beaconPlanAdmittedPeople(BeaconViewState state) =>
    planAssignablePeople(
      author: state.beacon.author,
      admittedHelpers: state.admittedHelpersLoaded
          ? state.admittedHelperRoster
          : state.beacon.admittedHelperUsers,
      roomParticipants: state.roomParticipants,
    );
