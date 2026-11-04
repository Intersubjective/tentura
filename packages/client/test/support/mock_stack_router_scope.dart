import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stack router for widget tests that render screens using app-bar
/// back controls backed by AutoRoute.
class MockStackRouterScope extends Fake implements StackRouter {
  MockStackRouterScope({this.poppable = true});

  final bool poppable;
  int maybePopCalls = 0;
  final navigatePaths = <String>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => poppable;

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    maybePopCalls++;
    return poppable;
  }

  @override
  Future<void> navigatePath(
    String path, {
    bool includePrefixMatches = false,
    OnNavigationFailure? onFailure,
  }) async {
    navigatePaths.add(path);
  }
}

/// Wraps [child] with [RouterScope] + [StackRouterScope] for AutoRoute APIs.
Widget wrapWithMockStackRouter(
  Widget child, {
  MockStackRouterScope? router,
  bool poppable = false,
}) {
  final scope = router ?? MockStackRouterScope(poppable: poppable);
  return RouterScope(
    controller: scope,
    stateHash: 0,
    inheritableObserversBuilder: () => const [],
    child: StackRouterScope(
      controller: scope,
      stateHash: 0,
      child: child,
    ),
  );
}
