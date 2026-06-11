import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/items_tab.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockItemsTabCubit extends Mock implements ItemsTabCubit {
  _MockItemsTabCubit(this._state);

  final ItemsTabState _state;

  @override
  ItemsTabState get state => _state;

  @override
  Stream<ItemsTabState> get stream => Stream<ItemsTabState>.value(_state);
}

final _t = DateTime.utc(2025);

CoordinationItem _item({
  required String id,
  required CoordinationItemStatus status,
  required String body,
}) =>
    CoordinationItem(
      id: id,
      beaconId: 'B1',
      kind: CoordinationItemKind.ask,
      status: status,
      creatorId: 'auth',
      createdAt: _t,
      updatedAt: _t,
      body: body,
    );

BeaconViewState _viewState() {
  return BeaconViewState(
    beacon: Beacon(
      id: 'B1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
      lifecycle: BeaconLifecycle.open,
      coordinationStatus: BeaconCoordinationStatus.helpOffersWaitingForReview,
    ),
    myProfile: const Profile(id: 'auth', displayName: 'Author'),
    status: const StateIsSuccess(),
  );
}

void main() {
  testWidgets('compact focus in closed opens closed only', (tester) async {
    const compact = Size(375, 812);
    await tester.binding.setSurfaceSize(compact);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final openItem = _item(
      id: 'open-1',
      status: CoordinationItemStatus.open,
      body: 'Open item unique body',
    );
    final closedItem = _item(
      id: 'closed-1',
      status: CoordinationItemStatus.resolved,
      body: 'Closed item unique body',
    );

    final tabState = ItemsTabState(
      openItems: [openItem],
      closedItems: [closedItem],
      status: const StateIsSuccess(),
    );
    final cubit = _MockItemsTabCubit(tabState);

    await tester.pumpWidget(
      MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: MediaQuery(
          data: const MediaQueryData(size: compact),
          child: Scaffold(
            body: BlocProvider<ItemsTabCubit>.value(
              value: cubit,
              child: ItemsTab(
                state: _viewState(),
                onOpenItemThread: (_) {},
                focusItemId: 'closed-1',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Closed item unique body'), findsOneWidget);
    expect(find.text('Open item unique body'), findsNothing);
  });
}
