import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'home_tab_reselect_state.dart';

export 'home_tab_reselect_state.dart';

@singleton
class HomeTabReselectCubit extends Cubit<HomeTabReselectState> {
  HomeTabReselectCubit() : super(const HomeTabReselectState());

  void bumpInboxReselect() => emit(
    state.copyWith(inboxReselectCount: state.inboxReselectCount + 1),
  );

  void bumpMyWorkReselect() => emit(
    state.copyWith(myWorkReselectCount: state.myWorkReselectCount + 1),
  );
}
