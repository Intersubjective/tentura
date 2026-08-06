import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_room/fake_coordination_item_case.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const myProfile = Profile(id: 'Uhelper', displayName: 'Helper');
  const beaconId = 'Boffer01';

  Beacon readableBeacon({BeaconStatus status = BeaconStatus.open}) => Beacon(
    id: beaconId,
    title: 'Coordination beacon',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: status,
    canReadContent: true,
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  group('BeaconViewCubit offerHelp', () {
    test(
      'enoughHelp beacon emits BackupOfferSentMessage after first offer',
      () async {
        final forward = TrackingOfferHelpForwardRepository();
        addTearDown(forward.dispose);
        final beaconRepo = TrackingBeaconRepository();
        beaconRepo.fetchByIdHandler = (_) async {
          if (beaconRepo.fetchByIdCalls > 1) {
            return readableBeacon();
          }
          return readableBeacon(status: BeaconStatus.enoughHelp);
        };
        final effects = FakeUiEffectPort();
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(
            forward: forward,
            beaconRepo: beaconRepo,
          ),
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);

        await pumpUntil(
          cubit.stream,
          () => cubit.state.beaconContentLoaded,
        );
        expect(cubit.state.beacon.status, BeaconStatus.enoughHelp);
        expect(cubit.state.isHelpOffered, isFalse);

        await cubit.offerHelp(message: 'I can help as backup');

        expect(forward.offerHelpCalls, 1);
        expect(cubit.state.beacon.status, BeaconStatus.open);
        final messages =
            effects.emitted.whereType<ShowMessage>().map((e) => e.message);
        expect(messages, contains(isA<BackupOfferSentMessage>()));
        expect(messages, isNot(contains(isA<HelpOfferedForwardNudgeMessage>())));
      },
    );

    test(
      'open beacon emits HelpOfferedForwardNudgeMessage after first offer',
      () async {
        final forward = TrackingOfferHelpForwardRepository();
        addTearDown(forward.dispose);
        final beaconRepo = TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => readableBeacon();
        final effects = FakeUiEffectPort();
        final cubit = BeaconViewCubit(
          id: beaconId,
          myProfile: myProfile,
          beaconViewCase: buildTestBeaconViewCase(
            forward: forward,
            beaconRepo: beaconRepo,
          ),
          coordinationItemCase: const FakeCoordinationItemCaseForRoom(),
          effects: effects,
        );
        addTearDown(cubit.close);

        await pumpUntil(
          cubit.stream,
          () => cubit.state.beaconContentLoaded,
        );
        expect(cubit.state.beacon.status, BeaconStatus.open);

        await cubit.offerHelp(message: 'I can help');

        expect(forward.offerHelpCalls, 1);
        final showMessages = effects.emitted.whereType<ShowMessage>().toList();
        expect(showMessages, hasLength(1));
        expect(showMessages.single.message, isA<HelpOfferedForwardNudgeMessage>());
        expect(
          (showMessages.single.message as HelpOfferedForwardNudgeMessage).beaconId,
          beaconId,
        );
      },
    );
  });
}

class TrackingOfferHelpForwardRepository extends FakeBeaconViewForwardRepository {
  int offerHelpCalls = 0;

  @override
  Future<bool> offerHelp({
    required String beaconId,
    String? message,
    List<String>? helpTypes,
    bool notifyHelpOfferListeners = true,
  }) async {
    offerHelpCalls++;
    if (notifyHelpOfferListeners) {
      notifyHelpOfferChanged(HelpOfferCreated(beaconId));
    }
    return true;
  }
}
