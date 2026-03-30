import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'my_work_state.freezed.dart';

enum MyWorkFilter { all, authored, committed }

enum MyWorkSection { active, closed }

@freezed
abstract class MyWorkState extends StateBase with _$MyWorkState {
  const factory MyWorkState({
    @Default('') String context,
    @Default([]) List<Beacon> authoredActive,
    @Default([]) List<Beacon> authoredClosed,
    @Default([]) List<Beacon> committedActive,
    @Default([]) List<Beacon> committedClosed,
    @Default(MyWorkSection.active) MyWorkSection section,
    @Default(MyWorkFilter.all) MyWorkFilter filter,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyWorkState;

  const MyWorkState._();

  List<Beacon> get _authoredForSection =>
      section == MyWorkSection.active ? authoredActive : authoredClosed;

  List<Beacon> get _committedForSection =>
      section == MyWorkSection.active ? committedActive : committedClosed;

  List<Beacon> get visibleBeacons => switch (filter) {
    MyWorkFilter.all => [
      ..._authoredForSection,
      ..._committedForSection.where(
        (c) => !_authoredForSection.any((a) => a.id == c.id),
      ),
    ],
    MyWorkFilter.authored => _authoredForSection,
    MyWorkFilter.committed => _committedForSection,
  };
}
