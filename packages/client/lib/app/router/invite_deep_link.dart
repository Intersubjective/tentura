import 'package:tentura/consts.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';

final _invitePathPattern = RegExp(r'^/invite/([^/]+)$');

/// Maps canonical `/invite/<code>` App Links to explicit signup or accept routes.
Uri transformInviteDeepLink({
  required Uri uri,
  required bool isAuthenticated,
}) {
  final match = _invitePathPattern.firstMatch(uri.path);
  if (match == null) {
    return uri;
  }
  final id = normalizeInviteCode(Uri.decodeComponent(match.group(1)!));
  if (!id.startsWith('I')) {
    return uri;
  }
  return uri.replace(
    path: isAuthenticated ? '$kPathAcceptInvite/$id' : '$kPathSignUp/$id',
    queryParameters: {kQueryIsDeepLink: 'true'},
  );
}

/// Maps `/shared/view?id=I…` invite ids to explicit signup or accept routes.
Uri transformSharedViewInviteDeepLink({
  required Uri uri,
  required String id,
  required bool isAuthenticated,
}) {
  final normalizedId = normalizeInviteCode(id);
  return uri.replace(
    path: isAuthenticated
        ? '$kPathAcceptInvite/$normalizedId'
        : '$kPathSignUp/$normalizedId',
    queryParameters: {kQueryIsDeepLink: 'true'},
  );
}
