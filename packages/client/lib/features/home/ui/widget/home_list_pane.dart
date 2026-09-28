import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/screen/inbox_screen.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import '../bloc/home_attention_cubit.dart';
import '../bloc/home_list_sources.dart';
import '../bloc/home_tab_reselect_cubit.dart';

/// A Home list (Activity or My Work) as the list pane beside a Request
/// (Material 3 list-detail), on the same cubit instances Home is using.
///
/// [forBeaconEntry] returns null when the Request was not opened from one of
/// those lists, or when Home has not published its cubits — the detail then
/// shows alone, as on a phone.
class HomeListPane extends StatelessWidget {
  const HomeListPane._({required this.entry});

  static Widget? forBeaconEntry(String? entry) {
    if (entry != kBeaconEntryInbox && entry != kBeaconEntryMyWork) {
      return null;
    }
    final sources = GetIt.I<HomeListSources>();
    if (sources.inbox == null || sources.myWork == null) return null;
    return HomeListPane._(entry: entry!);
  }

  final String entry;

  @override
  Widget build(BuildContext context) {
    final sources = GetIt.I<HomeListSources>();
    final inbox = sources.inbox;
    final myWork = sources.myWork;
    if (inbox == null || myWork == null) return const SizedBox.shrink();
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: GetIt.I<ScreenCubit>()),
        BlocProvider.value(value: GetIt.I<HomeTabReselectCubit>()),
        BlocProvider.value(value: GetIt.I<HomeAttentionCubit>()),
        BlocProvider.value(value: GetIt.I<InboxOperationalCubit>()),
        BlocProvider.value(value: inbox),
        BlocProvider.value(value: myWork),
      ],
      child: entry == kBeaconEntryInbox
          ? const InboxScreen()
          : const MyWorkScreen(),
    );
  }
}
