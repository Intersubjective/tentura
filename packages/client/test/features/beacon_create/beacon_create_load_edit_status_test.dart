import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

/// B011 — "Edit request" is offered for every status `beaconAllowsEdit`
/// accepts (and the server's updateBeacon accepts), but the editor used to
/// load only `open` requests and fell back to an empty create form.
void main() {
  Future<BeaconCreateCubit> loadEdit(BeaconStatus status) async {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(
        write: FakeBeaconWritePort(
          beacon: Beacon.empty.copyWith(
            id: 'b-edit',
            status: status,
            title: 'Move a sofa',
            description: 'Third floor, no lift.',
            author: const Profile(id: 'author-1'),
          ),
        ),
      ),
      effects: FakeUiEffectPort(),
    );
    await cubit.loadEdit('b-edit');
    return cubit;
  }

  for (final status in [
    BeaconStatus.open,
    BeaconStatus.needsMoreHelp,
    BeaconStatus.enoughHelp,
    BeaconStatus.reviewOpen,
  ]) {
    test('a request in ${status.name} opens in the editor, pre-filled', () async {
      final cubit = await loadEdit(status);
      addTearDown(cubit.close);

      expect(cubit.state.editId, 'b-edit');
      expect(cubit.state.isEditMode, isTrue);
      expect(cubit.state.title, 'Move a sofa');
    });
  }

  for (final status in [BeaconStatus.closed, BeaconStatus.cancelled]) {
    test('a request in ${status.name} is still refused', () async {
      final cubit = await loadEdit(status);
      addTearDown(cubit.close);

      expect(cubit.state.isEditMode, isFalse);
    });
  }
}
