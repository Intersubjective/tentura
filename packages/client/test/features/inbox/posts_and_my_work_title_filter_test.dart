// The VM service identifies the declaring library of mounted widget
// instances. Run this file with flutter test --enable-vmservice.

import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/screen/my_work_screen.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'posts_tab_wire_test_support.dart';

/// Only the desk's data loading is held pending. The real MyWorkScreen
/// builds its controls and handles menu selections and sort presses.
class _DeskCubit extends Cubit<MyWorkState> implements MyWorkCubit {
  _DeskCubit() : super(const MyWorkState());

  @override
  void setFilter(MyWorkFilter filter) => emit(state.copyWith(filter: filter));

  @override
  void setSort(MyWorkSort sort) => emit(state.copyWith(sort: sort));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _filterControl() => find.byWidgetPredicate(
  (w) => w is TenturaTopBarControl && w.icon == Icons.filter_list,
);

Finder _sortControl() => find.byWidgetPredicate(
  (w) => w is TenturaTopBarControl && w.icon != Icons.filter_list,
);

void _expectControlLabel(WidgetTester tester, Finder control, String label) {
  final widget = tester.widget<TenturaTopBarControl>(control);
  expect(widget.label, label);
  expect(
    widget.collapsed
        ? find.descendant(
            of: control,
            matching: find.byTooltip('${widget.tooltip}: $label'),
          )
        : find.descendant(of: control, matching: find.text(label)),
    findsOneWidget,
  );
}

/// Resolve the declaring library of the actual mounted instance through the
/// VM, rather than matching its display name against source text. Classes
/// with the same name in separate libraries cannot satisfy this check.
class _MountedWidgetTypes {
  _MountedWidgetTypes(this.service, this.isolateId);

  final vm.VmService service;
  final String isolateId;

  static Future<_MountedWidgetTypes?> connect() async {
    final info = await developer.Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    ).timeout(const Duration(seconds: 5));
    final uri = info.serverWebSocketUri;
    if (uri == null) return null;
    final service = await vmServiceConnectUri(
      uri.toString(),
    ).timeout(const Duration(seconds: 5));
    return _MountedWidgetTypes(
      service,
      developer.Service.getIsolateId(Isolate.current)!,
    );
  }

  Future<String> declaringLibrary(Widget widget) async {
    final id = developer.Service.getObjectId(widget)!;
    final instance =
        await service
                .getObject(isolateId, id)
                .timeout(const Duration(seconds: 5))
            as vm.Instance;
    final declaration =
        await service
                .getObject(isolateId, instance.classRef!.id!)
                .timeout(const Duration(seconds: 5))
            as vm.Class;
    return declaration.library!.uri!;
  }

  Future<Map<Type, String>> titleFilterOwners(String title) async {
    final candidates = <Widget>[];
    _filterControl().evaluate().single.visitAncestorElements((element) {
      if (element.widget is TenturaTopBar) return false;
      if (find
          .descendant(
            of: find.byElementPredicate((e) => identical(e, element)),
            matching: find.text(title),
          )
          .evaluate()
          .isNotEmpty) {
        candidates.add(element.widget);
      }
      return true;
    });
    final owners = <Type, String>{};
    for (final widget in candidates) {
      final uri = await declaringLibrary(widget);
      if (uri.startsWith('package:tentura/design_system/')) {
        owners[widget.runtimeType] = uri;
      }
    }
    return owners;
  }
}

void main() {
  final l10n = lookupL10n(const Locale('ru'));
  final menuLabels = [
    l10n.myWorkFilterActive,
    l10n.myWorkFilterAuthored,
    l10n.myWorkFilterHelpOffered,
    l10n.myWorkFilterDrafts,
    l10n.myWorkFilterAll,
    l10n.myWorkFilterArchived,
  ];
  final chipLabels = [
    l10n.myWorkFilterActive,
    l10n.myWorkFilterAuthored,
    l10n.myWorkFilterHelpOfferedChip,
    l10n.myWorkFilterDrafts,
    l10n.myWorkFilterAll,
    l10n.myWorkFilterArchived,
  ];

  for (final viewport in postsTabViewports) {
    testWidgets(
      'My Work retains filter and sort behavior in the title control shared with Posts (${viewport.name})',
      (tester) async {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final types = await tester.runAsync(_MountedWidgetTypes.connect);
        final desk = _DeskCubit();
        final reselect = HomeTabReselectCubit();
        try {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ru'),
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: TenturaResponsiveScope(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<MyWorkCubit>.value(value: desk),
                    BlocProvider<HomeTabReselectCubit>.value(value: reselect),
                    BlocProvider<ScreenCubit>(
                      create: (_) => ScreenCubit.local(),
                    ),
                  ],
                  child: const MyWorkScreen(),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text(l10n.myWork), findsOneWidget);
          expect(_filterControl(), findsOneWidget);
          expect(_sortControl(), findsOneWidget);
          _expectControlLabel(
            tester,
            _filterControl(),
            l10n.myWorkFilterActive,
          );
          _expectControlLabel(tester, _sortControl(), l10n.myWorkSortRecent);
          final compact = viewport.size.width < 600;
          expect(
            tester.widget<TenturaTopBarControl>(_filterControl()).collapsed,
            compact,
          );
          expect(
            tester.widget<TenturaTopBarControl>(_sortControl()).collapsed,
            compact,
          );

          for (var i = 0; i < menuLabels.length; i++) {
            await tester.tap(_filterControl());
            await tester.pumpAndSettle(const Duration(milliseconds: 50));
            expect(
              openMenuLabels(tester),
              menuLabels,
              reason: 'My Work keeps all six options, in order, without counts',
            );
            await tester.tap(
              find.descendant(
                of: openMenuItems,
                matching: find.text(menuLabels[i]),
              ),
            );
            await tester.pumpAndSettle(const Duration(milliseconds: 50));
            _expectControlLabel(tester, _filterControl(), chipLabels[i]);
          }
          for (final label in [
            l10n.myWorkSortOldest,
            l10n.myWorkSortAlphabetical,
            l10n.myWorkSortRecent,
          ]) {
            // The production sort button debounces taps on wall-clock time.
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 240)),
            );
            await tester.tap(_sortControl());
            await tester.pump();
            _expectControlLabel(tester, _sortControl(), label);
          }
          expect(tester.takeException(), isNull);
          if (types == null) {
            // Match the existing VM-inspection test convention. The dedicated
            // baseline check enables the VM service and must execute below.
            markTestSkipped(
              'Declaring-library inspection requires --enable-vmservice',
            );
            return;
          }
          // Validate the VM lookup against a known mounted DS control first,
          // so unavailable inspection cannot masquerade as missing reuse.
          expect(
            await tester.runAsync(
              () => types.declaringLibrary(
                tester.widget<Widget>(_filterControl()),
              ),
            ),
            startsWith('package:tentura/design_system/'),
          );
          final deskOwners = (await tester.runAsync(
            () => types.titleFilterOwners(l10n.myWork),
          ))!;
          expect(
            deskOwners,
            isNotEmpty,
            reason:
                'My Work title and filter must belong to one design-system component below TenturaTopBar',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          await withPostsTab(
            tester,
            size: viewport.size,
            wire: PostsTabWire([]),
            body: (h) async {
              expect(_filterControl(), findsOneWidget);
              final postsOwners = await types.titleFilterOwners(
                l10n.activityTabConversations,
              );
              expect(
                postsOwners,
                isNotEmpty,
                reason:
                    'The mounted Posts title/filter component must be declared in design_system',
              );
              expect(
                postsOwners.values,
                everyElement(startsWith('package:tentura/design_system/')),
              );
              expect(
                deskOwners.values,
                everyElement(startsWith('package:tentura/design_system/')),
              );
              expect(
                postsOwners.keys.toSet().intersection(deskOwners.keys.toSet()),
                isNotEmpty,
                reason:
                    'Conversations must mount the same design-system title/filter component as My Work, not a second copy',
              );
              await pickPostsFilter(
                tester,
                current: 'Активные',
                next: 'Черновики',
              );
              _expectControlLabel(tester, _filterControl(), 'Черновики');
            },
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await desk.close();
          await reselect.close();
          if (types != null) await tester.runAsync(types.service.dispose);
        }
      },
    );
  }
}
