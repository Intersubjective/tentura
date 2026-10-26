/// Typed translations of the nested-request GraphQL error codes (plan §3.5).
///
/// Thrown by [_V2RoutingLink]'s `onGraphQLError` handler in
/// `data/service/remote_api_client/build_client.dart` when it recognizes one
/// of these `codeNumber`s in a GraphQL error's `extensions.code`, the same
/// way `BeaconFactAlreadyPinnedException` is already special-cased there.
sealed class BeaconHierarchyException implements Exception {
  const BeaconHierarchyException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

/// The viewer is not authorized to create a child request on this parent.
final class BeaconChildCreateForbiddenException
    extends BeaconHierarchyException {
  const BeaconChildCreateForbiddenException([super.message]);

  static const codeNumber = 1309;
}

/// The parent request cannot accept child requests in its current state.
final class BeaconParentNotCoordinatableException
    extends BeaconHierarchyException {
  const BeaconParentNotCoordinatableException([super.message]);

  static const codeNumber = 1310;
}

/// The referenced promotion source message is not eligible.
final class BeaconPromotionSourceInvalidException
    extends BeaconHierarchyException {
  const BeaconPromotionSourceInvalidException([super.message]);

  static const codeNumber = 1311;
}

/// The source message already has a published child.
final class BeaconSourceAlreadyPromotedException
    extends BeaconHierarchyException {
  const BeaconSourceAlreadyPromotedException({
    this.existingChildBeaconId,
    Object? message,
  }) : super(message);

  /// Only present when the existing child is currently readable by the
  /// viewer (plan §4.3: never disclose a conflicting child ID before
  /// authorizing it).
  final String? existingChildBeaconId;

  static const codeNumber = 1312;
}

/// The `clientCommandId` was reused with different input.
final class BeaconChildCommandConflictException
    extends BeaconHierarchyException {
  const BeaconChildCommandConflictException([super.message]);

  static const codeNumber = 1313;
}

/// The prior child draft for this command was deleted.
final class BeaconChildCommandGoneException extends BeaconHierarchyException {
  const BeaconChildCommandGoneException([super.message]);

  static const codeNumber = 1314;
}

/// A non-General discussion scope was supplied where only General is
/// available.
final class DiscussionScopeDisabledException extends BeaconHierarchyException {
  const DiscussionScopeDisabledException([super.message]);

  static const codeNumber = 1315;
}

/// The requested coordination item kind is retired and no longer supported.
final class CoordinationKindDisabledException extends BeaconHierarchyException {
  const CoordinationKindDisabledException([super.message]);

  static const codeNumber = 1316;
}

/// The `after` pagination cursor is invalid, tampered, or does not match the
/// requested parent/group.
final class BeaconHierarchyCursorInvalidException
    extends BeaconHierarchyException {
  const BeaconHierarchyCursorInvalidException([super.message]);

  static const codeNumber = 1317;
}

/// A Request under a Post is created only by budding.
final class PostChildRequiresBudException extends BeaconHierarchyException {
  const PostChildRequiresBudException([super.message]);

  static const codeNumber = 1330;
}

/// A Request can be budded only from the budder's own message.
final class BudSourceNotOwnMessageException extends BeaconHierarchyException {
  const BudSourceNotOwnMessageException([super.message]);

  static const codeNumber = 1331;
}

/// The Post is not open (draft, closed or deleted).
final class PostNotOpenException extends BeaconHierarchyException {
  const PostNotOpenException([super.message]);

  static const codeNumber = 1332;
}

/// The requested Post lifetime is outside 1…72 hours.
final class PostLifetimeInvalidException extends BeaconHierarchyException {
  const PostLifetimeInvalidException([super.message]);

  static const codeNumber = 1349;
}

/// The new Post deadline is not earlier than its current deadline.
final class PostLifetimeExtendException extends BeaconHierarchyException {
  const PostLifetimeExtendException([super.message]);

  static const codeNumber = 1350;
}

/// No author invite with this id for the caller.
final class AuthorInviteNotFoundException extends BeaconHierarchyException {
  const AuthorInviteNotFoundException([super.message]);

  static const codeNumber = 1333;
}

/// The author invite is no longer pending (declined, withdrawn, expired or
/// superseded).
final class AuthorInviteNotPendingException extends BeaconHierarchyException {
  const AuthorInviteNotPendingException([super.message]);

  static const codeNumber = 1334;
}

/// The invited Request is not open (for example, it is in review).
final class AuthorInviteRequestNotOpenException
    extends BeaconHierarchyException {
  const AuthorInviteRequestNotOpenException([super.message]);

  static const codeNumber = 1335;
}
