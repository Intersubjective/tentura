import 'package:injectable/injectable.dart';

import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

/// The account-scoped list cubits Home owns, published so a detail route
/// pushed above Home can show the same list beside itself (Material 3
/// list-detail) — the same instances, not a second copy with its own fetch
/// and diverging state.
///
/// Home's inbox scope sets them while it is mounted and clears them when it
/// goes away; a detail route without them simply shows no list pane.
@singleton
class HomeListSources {
  InboxCubit? inbox;
  MyWorkCubit? myWork;

  void publish({required InboxCubit inbox, required MyWorkCubit myWork}) {
    this.inbox = inbox;
    this.myWork = myWork;
  }

  void clear({required InboxCubit inbox, required MyWorkCubit myWork}) {
    if (identical(this.inbox, inbox)) this.inbox = null;
    if (identical(this.myWork, myWork)) this.myWork = null;
  }
}
