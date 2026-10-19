// SPDX-License-Identifier: AGPL-3.0-only
// Issue #488: the complaint form must not start on the most severe category.
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/features/complaint/ui/bloc/complaint_cubit.dart';
import 'package:tentura/features/complaint/ui/bloc/complaint_messages.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'recording_complaint_case.dart';

void main() {
  late RecordingComplaintCase complaintCase;
  late FakeUiEffectPort effects;

  setUp(() {
    complaintCase = RecordingComplaintCase();
    effects = FakeUiEffectPort();
  });

  ComplaintCubit cubitFor({ComplaintType? fixedType}) {
    final cubit = ComplaintCubit(
      id: 'B1',
      fixedType: fixedType,
      complaintCase: complaintCase.useCase,
      effects: effects,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('a new complaint starts with no category chosen', () {
    final cubit = cubitFor();

    expect(cubit.state.type, isNull);
    expect(cubit.state.type, isNot(ComplaintType.violatesCsaePolicy));
  });

  test('submitting without a category sends nothing and stays open', () async {
    final cubit = cubitFor()..setDetails('Spam links everywhere');

    await cubit.submit();

    expect(complaintCase.created, isEmpty);
    expect(effects.emitted.whereType<NavigateBack>(), isEmpty);
    expect(
      effects.emitted.whereType<ShowMessage>().where(
        (e) => e.message is ComplaintSentMessage,
      ),
      isEmpty,
    );
    expect(cubit.state.isLoading, isFalse);
  });

  test('the chosen category is the one sent', () async {
    final cubit = cubitFor()
      ..setType(ComplaintType.violatesPlatformRules)
      ..setDetails('Spam links everywhere');

    await cubit.submit();

    expect(complaintCase.created, hasLength(1));
    expect(
      complaintCase.created.single.type,
      ComplaintType.violatesPlatformRules,
    );
    expect(complaintCase.created.single.id, 'B1');
  });

  test('a profile deletion request keeps its fixed category', () async {
    final cubit = cubitFor(fixedType: ComplaintType.accountDeletionRequest)
      ..setDetails('Please delete my profile');

    expect(cubit.state.type, ComplaintType.accountDeletionRequest);

    await cubit.submit();

    expect(complaintCase.created, hasLength(1));
    expect(
      complaintCase.created.single.type,
      ComplaintType.accountDeletionRequest,
    );
  });
}
