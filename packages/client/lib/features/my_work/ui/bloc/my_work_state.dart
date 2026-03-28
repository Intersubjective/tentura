import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'my_work_state.freezed.dart';

enum MyWorkFilter { all, authored, committed }

@freezed
abstract class MyWorkState extends StateBase with _$MyWorkState {
  const factory MyWorkState({
    @Default('') String context,
    @Default([]) List<Beacon> authored,
    @Default([]) List<Beacon> committed,
    @Default(MyWorkFilter.all) MyWorkFilter filter,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyWorkState;

  const MyWorkState._();

  List<Beacon> get visibleBeacons => switch (filter) {
    MyWorkFilter.all => [
      ...authored,
      ...committed.where((c) => !authored.any((a) => a.id == c.id)),
    ],
    MyWorkFilter.authored => authored,
    MyWorkFilter.committed => committed,
  };
}
