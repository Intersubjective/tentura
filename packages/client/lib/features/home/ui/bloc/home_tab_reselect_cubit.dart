import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

import 'home_tab_reselect_state.dart';

export 'home_tab_reselect_state.dart';

@singleton
class HomeTabReselectCubit extends Cubit<HomeTabReselectState> {
  HomeTabReselectCubit() : super(const HomeTabReselectState());

  void bump(HomeTab tab) => switch (tab) {
    HomeTab.inbox => emit(
      state.copyWith(inboxReselectCount: state.inboxReselectCount + 1),
    ),
    HomeTab.work => emit(
      state.copyWith(myWorkReselectCount: state.myWorkReselectCount + 1),
    ),
    HomeTab.network || HomeTab.me => null,
  };
}
