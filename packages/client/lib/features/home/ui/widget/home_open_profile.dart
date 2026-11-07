import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';

/// Opens Home's Me tab, from inside Home or from a route pushed above it.
void openMyProfile(BuildContext context) {
  final root = context.router.root;
  root
      .innerRouterOf<TabsRouter>(HomeRoute.name)
      ?.setActiveIndex(HomeTabSpec.forTab(HomeTab.me).index);
  if (root.current.name != HomeRoute.name) {
    unawaited(root.replacePath(kPathProfile));
  }
}
