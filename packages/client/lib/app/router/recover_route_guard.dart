import 'package:auto_route/auto_route.dart';

import 'package:tentura/features/invitation/domain/invite_code.dart';

import 'root_router.gr.dart';

/// Post-auth redirect for `/recover` (seed recovery). Invite query wins over home.
PageRouteInfo? resolveRecoverAuthenticatedRedirect({String? inviteQuery}) {
  final code = normalizeInviteCode(inviteQuery ?? '');
  if (code.isNotEmpty && isValidInviteCode(code)) {
    return AcceptInviteRoute(id: code);
  }
  return const HomeRoute();
}
