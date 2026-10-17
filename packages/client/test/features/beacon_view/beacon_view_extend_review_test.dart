// #380: "Extend review" in the status sheet closed the sheet and said nothing.
// The cubit now confirms with the new deadline.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/message/beacon_status_messages.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

const _beaconId = 'Bextend01';

/// Local 27 Oct 2026, 14:00, as the server sends it (UTC ISO string).
final _closesAt = DateTime(2026, 10, 27, 14);

class _ExtendingClosureRepository extends FakeBeaconViewClosureRepository {
  _ExtendingClosureRepository({this.fail = false});

  final bool fail;

  @override
  Future<BeaconExtendReviewResult> beaconExtendReview(String beaconId) async {
    if (fail) throw Exception('extend failed');
    return BeaconExtendReviewResult(
      beaconId: beaconId,
      closesAt: _closesAt.toUtc().toIso8601String(),
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  Future<(BeaconViewCubit, FakeUiEffectPort)> loadedCubit({
    bool fail = false,
  }) async {
    final effects = FakeUiEffectPort();
    final cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: const Profile(id: 'Uauthor', displayName: 'Author'),
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => Beacon(
            id: _beaconId,
            title: 'Wrapping up beacon',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            status: BeaconStatus.reviewOpen,
            author: const Profile(id: 'Uauthor', displayName: 'Author'),
          ),
        closureRepo: _ExtendingClosureRepository(fail: fail),
      ),
      effects: effects,
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContentLoaded);
    return (cubit, effects);
  }

  test('extendReview confirms with the new deadline', () async {
    final (cubit, effects) = await loadedCubit();

    await cubit.extendReview();

    final messages = effects.emitted
        .whereType<ShowMessage>()
        .map((e) => e.message)
        .whereType<ReviewExtendedMessage>()
        .toList();
    expect(messages, hasLength(1));
    expect(messages.single.toEn, 'Deadline extended to Oct 27 14:00');
    expect(messages.single.toRu, 'Срок продлён до 27 окт. 14:00');
  });

  test('a failed extendReview shows no confirmation', () async {
    final (cubit, effects) = await loadedCubit(fail: true);

    await cubit.extendReview();

    expect(
      effects.emitted
          .whereType<ShowMessage>()
          .map((e) => e.message)
          .whereType<ReviewExtendedMessage>(),
      isEmpty,
    );
  });
}
