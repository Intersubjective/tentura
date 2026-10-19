import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/ui/bloc/state_base.dart';

part 'complaint_state.freezed.dart';

@freezed
abstract class ComplaintState extends StateBase with _$ComplaintState {
  const factory ComplaintState({
    required String id,
    @Default('') String email,
    @Default('') String details,

    /// No category until the user picks one (#488); fixed types preset it.
    ComplaintType? type,
    ComplaintType? fixedType,

    /// What is being reported, fetched by [id] (#488); empty until loaded.
    @Default('') String title,
    @Default('') String author,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ComplaintState;

  const ComplaintState._();
}
