import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/items_tab.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _MockItemsTabCubit extends Mock implements ItemsTabCubit {
  _MockItemsTabCubit(this._state);

  final ItemsTabState _state;

  @override
  ItemsTabState get state => _state;

  @override
  Stream<ItemsTabState> get stream => Stream<ItemsTabState>.value(_state);
}

class _ToggleItemsTabCubit extends Mock implements ItemsTabCubit {
  _ToggleItemsTabCubit(ItemsTabState initial) {
    _state = initial;
    _controller = StreamController<ItemsTabState>.broadcast();
    _controller.add(initial);
  }

  late ItemsTabState _state;
  late final StreamController<ItemsTabState> _controller;

  @override
  ItemsTabState get state => _state;

  @override
  Stream<ItemsTabState> get stream => _controller.stream;

  @override
  void setActiveForMeOnly(bool value) {
    _state = _state.copyWith(activeForMeOnly: value);
    _controller.add(_state);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

final _t = DateTime.utc(2025);

CoordinationItem _item({
  required String id,
  required CoordinationItemStatus status,
  required String body,
  String creatorId = 'auth',
  String? targetPersonId,
}) =>
    CoordinationItem(
      id: id,
      beaconId: 'B1',
      kind: CoordinationItemKind.ask,
      status: status,
      creatorId: creatorId,
      createdAt: _t,
      updatedAt: _t,
      body: body,
      targetPersonId: targetPersonId,
    );

BeaconViewState _viewState() {
  return BeaconViewState(
    beacon: Beacon(
      id: 'B1',
      title: 'T',
      author: const Profile(id: 'auth', displayName: 'Author'),
      createdAt: _t,
      updatedAt: _t,
    ),
    myProfile: const Profile(id: 'auth', displayName: 'Author'),
  );
}

Widget _wrapItemsTab({
  required ItemsTabCubit cubit,
  required Size size,
  String? focusItemId,
}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: BlocProvider<ItemsTabCubit>.value(
          value: cubit,
          child: ItemsTab(
            state: _viewState(),
            onOpenItemThread: (_) {},
            focusItemId: focusItemId,
          ),
        ),
      ),
    ),
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
    );
    final cubit = _MockItemsTabCubit(tabState);

    await tester.pumpWidget(
      _wrapItemsTab(cubit: cubit, size: compact, focusItemId: 'closed-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Closed item unique body'), findsOneWidget);
    expect(find.text('Open item unique body'), findsNothing);
  });

  testWidgets('for me filter toggles visible active items', (tester) async {
    const regular = Size(800, 600);
    await tester.binding.setSurfaceSize(regular);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final mine = _item(
      id: 'mine',
      status: CoordinationItemStatus.open,
      body: 'My ask body',
    );
    final other = _item(
      id: 'other',
      status: CoordinationItemStatus.open,
      body: 'Other ask body',
      creatorId: 'stranger',
      targetPersonId: 'someone',
    );

    final cubit = _ToggleItemsTabCubit(
      ItemsTabState(openItems: [mine, other]),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrapItemsTab(cubit: cubit, size: regular));
    await tester.pumpAndSettle();

    expect(find.text('My ask body'), findsOneWidget);
    expect(find.text('Other ask body'), findsOneWidget);

    await tester.tap(find.text('For me'));
    await tester.pumpAndSettle();

    expect(find.text('My ask body'), findsOneWidget);
    expect(find.text('Other ask body'), findsNothing);

    await tester.tap(find.text('For me'));
    await tester.pumpAndSettle();

    expect(find.text('My ask body'), findsOneWidget);
    expect(find.text('Other ask body'), findsOneWidget);
  });
}
