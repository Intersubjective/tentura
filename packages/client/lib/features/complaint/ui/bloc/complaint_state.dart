import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/state_base.dart';

part 'complaint_state.freezed.dart';

@freezed
abstract class ComplaintState extends StateBase with _$ComplaintState {
  const factory ComplaintState({
    required String id,
    @Default('') String email,
    @Default('') String details,
    @Default(ComplaintType.violatesCsaePolicy) ComplaintType type,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ComplaintState;

  const ComplaintState._();
}
