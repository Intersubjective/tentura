// SPDX-License-Identifier: AGPL-3.0-only
// Issue #488 (owner review on PR #610): the report form fetches what is being
// reported by its id — a beacon's title and author, a person's name — instead
// of trusting title/author text carried in the link.
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/complaint/ui/bloc/complaint_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'recording_complaint_case.dart';

final _at = DateTime.utc(2026, 10, 19);

final _beacon = Beacon(
  id: 'B1',
  title: 'Fix my bike before Sunday',
  createdAt: _at,
  updatedAt: _at,
  author: const Profile(id: 'Ualice', displayName: 'Alice Moreau'),
);

const _person = Profile(
  id: 'U7',
  displayName: 'Robert Stone',
  contactName: 'Bob from climbing',
);

/// Lets the constructor's fetch (fake futures) settle.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a beacon id shows the fetched beacon title and author name', () async {
    final complaintCase = RecordingComplaintCase(beacon: _beacon);
    final cubit = ComplaintCubit(
      id: 'B1',
      complaintCase: complaintCase.useCase,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    await _settle();

    expect(complaintCase.beacons.requested, ['B1']);
    expect(cubit.state.title, 'Fix my bike before Sunday');
    expect(cubit.state.author, 'Alice Moreau');
  });

  test('a user id shows the fetched person name and no author line', () async {
    final complaintCase = RecordingComplaintCase(profile: _person);
    final cubit = ComplaintCubit(
      id: 'U7',
      complaintCase: complaintCase.useCase,
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);

    await _settle();

    expect(complaintCase.profiles.requested, ['U7']);
    expect(complaintCase.beacons.requested, isEmpty);
    // The name the viewer knows them by (shownName), like the profile screen.
    expect(cubit.state.title, 'Bob from climbing');
    expect(cubit.state.author, isEmpty);
  });

  test('a failed fetch leaves no title line and the form still submits', () async {
    // Nothing to fetch: every lookup throws.
    final complaintCase = RecordingComplaintCase();
    final effects = FakeUiEffectPort();
    final cubit = ComplaintCubit(
      id: 'B404',
      complaintCase: complaintCase.useCase,
      effects: effects,
    );
    addTearDown(cubit.close);

    await _settle();

    expect(complaintCase.beacons.requested, ['B404']);
    expect(cubit.state.title, isEmpty);
    expect(cubit.state.author, isEmpty);
    expect(cubit.state.isSuccess, isTrue);
    expect(effects.emitted.whereType<ShowError>(), isEmpty);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);

    cubit
      ..setType(ComplaintType.violatesPlatformRules)
      ..setDetails('Spam links everywhere');
    await cubit.submit();

    expect(complaintCase.created, hasLength(1));
    expect(complaintCase.created.single.id, 'B404');
  });
}
