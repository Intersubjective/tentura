// U093: the request header's team face pile shows online dots, so the
// request screen asks the presence service for its team (author + admitted
// helpers, minus the viewer) and lets go when the screen closes.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'help_offer_author_seen_test_support.dart';

const _helper = Profile(id: 'Uhelper00001', displayName: 'Nina');

class _RecordingPresence extends Mock implements PresenceRepository {
  final watches = <(String, Set<String>)>[];
  final unwatches = <String>[];

  @override
  void watch(String sourceKey, Set<String> userIds) =>
      watches.add((sourceKey, userIds));

  @override
  void unwatch(String sourceKey) => unwatches.add(sourceKey);
}

void main() {
  test('opening a Request watches its team; closing lets go', () async {
    final presence = _RecordingPresence();
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async =>
          authorSeenBeacon().copyWith(admittedHelperUsers: const [_helper]);
    final cubit = BeaconViewCubit(
      id: kAuthorSeenBeaconId,
      myProfile: kAuthor,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: FakeBeaconViewCoordinationRepository(rows: const []),
        presenceRepository: presence,
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(beaconRepo.dispose);

    await waitFor(() => cubit.state.beaconContextLoaded);

    final (key, ids) = presence.watches.last;
    expect(key, 'beacon:$kAuthorSeenBeaconId:team');
    expect(ids, {_helper.id});

    await cubit.close();
    expect(presence.unwatches, ['beacon:$kAuthorSeenBeaconId:team']);
  });
}
