import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'my_field_state.freezed.dart';

@freezed
abstract class MyFieldState extends StateBase with _$MyFieldState {
  const factory MyFieldState({
    @Default('') String context,
    @Default([]) List<String> tags,
    @Default([]) List<Beacon> beacons,
    @Default([]) List<String> selectedTags,
    @Default([]) List<Beacon> visibleBeacons,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyFieldState;

  const MyFieldState._();
}
