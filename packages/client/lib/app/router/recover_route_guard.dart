import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';

import 'package:tentura/features/auth/data/service/seed_recovery_landing_url.dart';
import 'root_router.gr.dart';

/// Post-auth redirect for `/recover` (seed recovery). Invite query wins over home.
PageRouteInfo? resolveRecoverAuthenticatedRedirect({String? inviteQuery}) {
  final code = normalizeInviteCode(inviteQuery ?? '');
  if (code.isNotEmpty && isValidInviteCode(code)) {
    stripSeedRecoveryLandingEntry(hashFragment: '#$kPathAcceptInvite/$code');
    return AcceptInviteRoute(id: code);
  }
  stripSeedRecoveryLandingEntry(hashFragment: '#$kPathHome');
  return const HomeRoute();
}
