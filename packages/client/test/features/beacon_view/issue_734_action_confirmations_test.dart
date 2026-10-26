// #734: Accept, Decline and Invite on a Request gave no confirmation on the
// screen where they were taken; the only trace was a system line in the
// discussion, which can sit off-screen behind the side panel. Each success
// now says what happened in a snack bar.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/help_offer_tile_sheet_cubit.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'help_offer_author_seen_test_support.dart';

/// The snack bar messages [effects] carried, in English.
List<String> _snacks(FakeUiEffectPort effects) => [
  for (final e in effects.emitted.whereType<ShowMessage>()) e.message.toEn,
];

Beacon _openBeacon(String id) => Beacon.empty.copyWith(
  id: id,
  status: BeaconStatus.open,
  author: kAuthor,
);

void main() {
  group('the words', () {
    test('accepting names the helper', () {
      const message = HelpOfferAcceptedMessage('Dave');
      expect(message.toEn, 'Dave admitted to the discussion');
      expect(message.toRu, 'Dave теперь в обсуждении');
      expect(const HelpOfferAcceptedMessage('').toEn, 'Offer accepted');
      expect(const HelpOfferAcceptedMessage('').toRu, 'Предложение принято');
    });

    test('declining says the offerer was told', () {
      const message = HelpOfferDeclinedMessage('Eve');
      expect(message.toEn, 'Offer declined — Eve was told');
      expect(message.toRu, 'Предложение отклонено — Eve получит уведомление');
      expect(const HelpOfferDeclinedMessage('').toEn, 'Offer declined');
      expect(const HelpOfferDeclinedMessage('').toRu, 'Предложение отклонено');
    });

    test('inviting names the invitee', () {
      const message = AuthorInviteSentMessage('Carol');
      expect(message.toEn, 'Invitation sent to Carol');
      expect(message.toRu, 'Приглашение отправлено: Carol');
      expect(const AuthorInviteSentMessage('').toEn, 'Invitation sent');
    });
  });

  group('the offer sheet', () {
    Future<(HelpOfferTileSheetCubit, FakeUiEffectPort)> loaded({
      FakeBeaconViewCoordinationRepository? coordination,
    }) async {
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (id) async => _openBeacon(id);
      final effects = FakeUiEffectPort();
      final cubit = HelpOfferTileSheetCubit(
        beaconId: kAuthorSeenBeaconId,
        offerUserId: kOfferer.id,
        myProfile: kAuthor,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo:
              coordination ??
              FakeBeaconViewCoordinationRepository(rows: [pendingOfferRow()]),
        ),
        effects: effects,
      );
      await cubit.load();
      expect(cubit.canManageOffer, isTrue);
      effects.clear();
      return (cubit, effects);
    }

    test('Accept confirms who was admitted', () async {
      final (cubit, effects) = await loaded();
      addTearDown(cubit.close);

      expect(await cubit.accept(), isTrue);
      expect(_snacks(effects), ['Offerer admitted to the discussion']);
    });

    test('Decline confirms the offerer was told', () async {
      final (cubit, effects) = await loaded();
      addTearDown(cubit.close);

      expect(await cubit.decline(reason: 'We have enough gloves'), isTrue);
      expect(_snacks(effects), ['Offer declined — Offerer was told']);
    });

    test('a refused Accept confirms nothing', () async {
      final (cubit, effects) = await loaded(
        coordination: _FailingCoordination(rows: [pendingOfferRow()]),
      );
      addTearDown(cubit.close);

      expect(await cubit.accept(), isFalse);
      expect(_snacks(effects), isEmpty);
      expect(effects.emitted.whereType<ShowError>(), hasLength(1));
    });
  });

  group('the People tab', () {
    Future<(BeaconViewCubit, FakeUiEffectPort)> loaded() async {
      final effects = FakeUiEffectPort();
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => authorSeenBeacon();
      final cubit = BeaconViewCubit(
        id: kAuthorSeenBeaconId,
        myProfile: kAuthor,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          coordinationRepo: FakeBeaconViewCoordinationRepository(
            rows: [pendingOfferRow()],
          ),
          roomRepo: FakeBeaconViewRoomRepository(participants: const []),
        ),
        effects: effects,
      );
      addTearDown(() async {
        await cubit.close();
        await beaconRepo.dispose();
      });
      await waitFor(
        () =>
            cubit.state.beaconContextLoaded &&
            cubit.state.roomParticipantsLoaded &&
            cubit.state.helpOffers.isNotEmpty,
      );
      effects.clear();
      return (cubit, effects);
    }

    test('Accept confirms who was admitted', () async {
      final (cubit, effects) = await loaded();

      await cubit.acceptHelpOffer(offerUserId: kOfferer.id);
      expect(_snacks(effects), contains('Offerer admitted to the discussion'));
    });

    test('Decline with a reason confirms the offerer was told', () async {
      final (cubit, effects) = await loaded();

      await cubit.declineHelpOffer(
        offerUserId: kOfferer.id,
        reason: 'We have enough gloves',
      );
      expect(_snacks(effects), contains('Offer declined — Offerer was told'));
    });
  });
}

class _FailingCoordination extends FakeBeaconViewCoordinationRepository {
  _FailingCoordination({required super.rows});

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
  }) async {
    throw StateError('accept failed');
  }
}
