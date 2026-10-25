import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_tab_reentry_listener.dart';

import 'my_work_test_support.dart';

// #491: after Field and then `#/home/work`, the Requests filter stayed on
// Archived. Re-entering the Requests tab (URL or tap — both switch the
// active tab) must open on Active; the sort is kept.

class _FakeTabsRouter extends Fake with ChangeNotifier implements TabsRouter {
  _FakeTabsRouter(this._index);

  int _index;

  @override
  int get activeIndex => _index;

  @override
  void setActiveIndex(int value, {bool notify = true}) {
    _index = value;
    if (notify) notifyListeners();
  }
}

final _work = HomeTabSpec.forTab(HomeTab.work).index;
final _field = HomeTabSpec.forTab(HomeTab.constellation).index;

Future<MyWorkCubit> _archivedCubit() async {
  final cubit = MyWorkCubit(
    userId: 'user-491',
    myWorkCase: buildTestMyWorkCase(),
  );
  await cubit.stream.firstWhere((s) => s.isSuccess);
  cubit.setFilter(MyWorkFilter.archived);
  await cubit.stream.firstWhere((s) => s.archivedDataFetched && s.isSuccess);
  return cubit;
}

Future<void> _pump(
  WidgetTester tester,
  MyWorkCubit cubit,
  _FakeTabsRouter tabs,
) => tester.pumpWidget(
  BlocProvider<MyWorkCubit>.value(
    value: cubit,
    child: MyWorkTabReentryListener(tabsRouter: tabs, child: const SizedBox()),
  ),
);

void main() {
  testWidgets('re-entering Requests from Field resets Archived to Active', (
    tester,
  ) async {
    final cubit = await tester.runAsync(_archivedCubit);
    cubit!.setSort(MyWorkSort.oldest);
    final tabs = _FakeTabsRouter(_work);
    await _pump(tester, cubit, tabs);

    tabs.setActiveIndex(_field);
    await tester.pump();
    expect(cubit.state.filter, MyWorkFilter.archived);

    tabs.setActiveIndex(_work);
    await tester.pump();
    expect(cubit.state.filter, MyWorkFilter.active);
    expect(cubit.state.sort, MyWorkSort.oldest);

    await tester.runAsync(cubit.close);
  });

  testWidgets('staying on Requests keeps the Archived filter', (tester) async {
    final cubit = await tester.runAsync(_archivedCubit);
    final tabs = _FakeTabsRouter(_work);
    await _pump(tester, cubit!, tabs);

    // A notify without a tab change (e.g. a pushed request page popping).
    tabs.setActiveIndex(_work);
    await tester.pump();
    expect(cubit.state.filter, MyWorkFilter.archived);

    await tester.runAsync(cubit.close);
  });

  testWidgets('other filters survive re-entry', (tester) async {
    final cubit = await tester.runAsync(_archivedCubit);
    cubit!.setFilter(MyWorkFilter.drafts);
    final tabs = _FakeTabsRouter(_field);
    await _pump(tester, cubit, tabs);

    tabs.setActiveIndex(_work);
    await tester.pump();
    expect(cubit.state.filter, MyWorkFilter.drafts);

    await tester.runAsync(cubit.close);
  });
}
