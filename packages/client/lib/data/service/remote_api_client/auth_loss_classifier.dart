import 'dart:async';

import 'package:ferry/ferry.dart'
    as gql
    show ResponseFormatException, ServerException;
import 'package:gql_exec/gql_exec.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/parallel_wait_failure.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/beacon_plan/domain/exception/beacon_plan_exceptions.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_lobby/domain/exception/beacon_lobby_exception.dart';
import 'package:tentura/features/beacon_threads/domain/exception/baton_exceptions.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';
import 'package:tentura/features/constellation/domain/exception.dart';
import 'package:tentura/features/people_tags/domain/people_tags_exception.dart';

import 'exception.dart';
import 'session_fetch.dart';

/// Maps transport/API failures to domain exceptions for repositories and cubits.
Never throwClassifiedRemoteFailure(Object? error) {
  throw mapRemoteFailure(error);
}

Exception mapRemoteFailure(Object? error) {
  // Already a classified domain exception. The link layer re-wraps anything an
  // earlier link throws (e.g. ErrorLink throwing RemoteApiException after a
  // 200-with-errors response) into a gql.ServerException; once we unwrap that
  // below we re-enter here with the original — pass it through untouched
  // instead of flattening its real message back into raw text.
  if (error is GenericException) {
    return error;
  }
  if (error is ClosureException) {
    return error;
  }
  // Typed by `throwIfBeaconHierarchyError` in the error link (nested
  // Requests, Post budding, author invites); callers catch these by type.
  if (error is BeaconHierarchyException) {
    return error;
  }
  // Typed by the error link; preserve their identity for caller catches.
  if (error is BatonException) {
    return error;
  }
  if (error is ConstellationException) {
    return error;
  }
  if (error is PeopleTagsException) {
    return error;
  }
  if (error is BeaconLobbyUnavailableException) {
    return error;
  }
  if (error is BeaconPlanException) {
    return error;
  }
  if (error is AuthSessionLostException) {
    return error;
  }
  if (error is ParallelWaitError) {
    final causes = parallelWaitCauses(error)?.map(mapRemoteFailure).toList();
    if (causes != null) {
      // Retrying cannot recover a lost session, so it wins over a sibling.
      if (causes.any((c) => c is AuthSessionLostException)) {
        return const AuthSessionLostException();
      }
      final retryLater = combinedRetryLater(causes);
      if (retryLater != null) {
        return retryLater;
      }
    }
  }
  if (error is SessionAuthRejectedException) {
    return error;
  }
  if (error is SessionHttpException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const AuthSessionLostException();
    }
    return ServerStatusException(error.statusCode);
  }
  if (error is AuthenticationNoKeyException) {
    return const AuthSessionLostException();
  }
  if (error is AuthenticationFailedException) {
    return const AuthSessionLostException();
  }
  if (error is ServerStatusException) {
    if (error.statusCode == 401) {
      return const AuthSessionLostException();
    }
    return error;
  }
  // GraphQL errors mean the server answered — never a connectivity problem.
  // Surface the server's message instead of a misleading "no internet".
  if (error is GraphQLError) {
    if (_isGraphQlAuthLoss(error)) {
      return const AuthSessionLostException();
    }
    return _retryLater([error]) ??
        _remoteApiOrUnknown(error.message, code: error.extensions?['code']);
  }
  if (error is List<GraphQLError>) {
    for (final e in error) {
      if (_isGraphQlAuthLoss(e)) {
        return const AuthSessionLostException();
      }
    }
    final first = error.isEmpty ? null : error.first;
    if (first != null) {
      return _retryLater(error) ??
          _remoteApiOrUnknown(first.message, code: first.extensions?['code']);
    }
  }
  // gql ServerException (incl. gql_http_link's HttpLinkServerException) is
  // thrown when the server answers with a non-2xx status or a body lacking
  // both data and errors — e.g. a 400 on a malformed/invalid GraphQL query.
  // The server DID answer, so surface its payload instead of a misleading
  // "no internet". A genuine socket failure also arrives as a ServerException
  // but with no statusCode and no parsedResponse — that case falls through to
  // the connectivity default below.
  if (error is gql.ServerException) {
    final mapped = _mapServerException(error);
    if (mapped != null) {
      return mapped;
    }
  }
  // The response body could not be parsed as a GraphQL response (e.g. an HTML
  // error page). The server still answered — surface what we can.
  if (error is gql.ResponseFormatException) {
    return _remoteApiOrUnknown(
      '$_malformedResponsePrefix${error.originalException ?? error}',
    );
  }
  final raw = error?.toString() ?? '';
  final message = raw.toLowerCase();
  if (message.contains('invalid-jwt') ||
      message.contains('invalid jwt') ||
      message.contains('jwtexpired') ||
      message.contains('could not verify jwt')) {
    return const AuthSessionLostException();
  }
  // A request timeout is not «no internet»: the server may have received the
  // request and carried it out (#513: a slow RoomMessageCreate was saved,
  // shown as offline, and Retry posted it twice).
  if (error is TimeoutException || message.contains('timeoutexception')) {
    return const RequestTimeoutException();
  }
  // Only errors that actually look like a transport/connectivity failure
  // become "no internet". Everything else (client-side StateError from an
  // empty stream, deserialization failures, unhandled link exceptions, …) is
  // a real bug — surface its text instead of a misleading "no internet".
  if (_looksLikeConnectivityFailure(message)) {
    return const ConnectionUplinkException();
  }
  return _remoteApiOrUnknown(raw);
}

const _malformedResponsePrefix = 'Malformed server response: ';
const _serverStatusPrefix = 'Server error (HTTP ';

/// True when [error] (as mapped by [mapRemoteFailure]) is the server's own
/// answer to the operation — GraphQL errors it returned — rather than a
/// transport failure, an HTTP status without a GraphQL body or an unreadable
/// response. Such a refusal won't change if the same request is sent again.
/// (An unclassified client-side error also maps to [RemoteApiException] and
/// counts here; a resend won't fix that either.) The server's internal fault
/// (an unmapped database error or pool timeout, answered with HTTP 200) is
/// not a refusal: a resend can succeed.
bool isRemoteRefusal(Object? error) =>
    error is RemoteApiException &&
    !_internalFaultCodes.contains(error.code) &&
    !error.message.startsWith(_serverStatusPrefix) &&
    !error.message.startsWith(_malformedResponsePrefix);

/// The server's internal-fault codes (its `unspecifiedException`s, as the
/// server's `isInternalFaultException` lists them); unmapped errors come back
/// as `1000` (#342).
const _internalFaultCodes = {'1000', '1100', '1200', '1300', '1400'};

/// True when [error] means the server was slow or unreachable (timeout, 5xx,
/// 408/429, transport failure) rather than that it rejected the credentials.
/// Session-restore callers retry these instead of signing the user out.
bool isTransientRemoteFailure(Object? error) {
  if (error is TimeoutException) {
    return true;
  }
  if (error is SessionHttpException) {
    return _isTransientStatus(error.statusCode);
  }
  if (error is gql.ServerException) {
    final status = error.statusCode;
    if (status != null && _isTransientStatus(status)) {
      return true;
    }
  }
  final mapped = mapRemoteFailure(error);
  return mapped is ConnectionUplinkException ||
      mapped is RequestTimeoutException ||
      (mapped is ServerStatusException &&
          _isTransientStatus(mapped.statusCode));
}

bool _isTransientStatus(int status) =>
    status >= 500 || status == 408 || status == 429;

/// Heuristic: does this error message look like a network/transport failure?
/// Matches the common socket/TLS/XHR/fetch signatures across the
/// native (`dart:io`) and web (`package:http` BrowserClient) stacks.
bool _looksLikeConnectivityFailure(String message) {
  const markers = [
    'socket', // SocketException, "socket closed", …
    'failed host lookup',
    'connection refused',
    'connection closed',
    'connection reset',
    'connection terminated',
    'connection attempt failed',
    'connection timed out',
    'network is unreachable',
    'software caused connection abort',
    'clientexception', // package:http transport error
    'xmlhttprequest error', // web
    'failed to fetch', // web fetch
    'handshakeexception', // TLS
    'os error',
  ];
  return markers.any(message.contains);
}

/// Maps a gql [ServerException] to a domain exception, or returns `null` when
/// it represents a genuine transport failure (no status, no parsed response)
/// that should be treated as a connectivity problem by the caller.
Exception? _mapServerException(gql.ServerException error) {
  final status = error.statusCode;
  final errors = error.parsedResponse?.errors;

  // The server returned GraphQL errors (even alongside a non-2xx status).
  if (errors != null && errors.isNotEmpty) {
    for (final e in errors) {
      if (_isGraphQlAuthLoss(e)) {
        return const AuthSessionLostException();
      }
    }
    final joined = errors.map((e) => e.message.trim()).join('; ');
    final detail = status == null ? joined : 'HTTP $status: $joined';
    return _retryLater(errors) ??
        _remoteApiOrUnknown(detail, code: errors.first.extensions?['code']);
  }

  // No GraphQL errors, but the server answered with a status code.
  if (status != null) {
    if (status == 401 || status == 403) {
      return const AuthSessionLostException();
    }
    return _remoteApiOrUnknown('$_serverStatusPrefix$status)');
  }

  // No status and no parsed response. This is how ferry surfaces an exception
  // thrown by an earlier link: the real cause (e.g. the RemoteApiException
  // ErrorLink threw for a GraphQL error) is tucked into `originalException`
  // while `parsedResponse` is null. Recover it so its message survives instead
  // of being lost behind this wrapper's toString().
  final original = error.originalException;
  if (original != null && original is! gql.ServerException) {
    return mapRemoteFailure(original);
  }

  // No status, no parsed response, nothing wrapped: a genuine transport failure.
  return null;
}

/// Server admission backoff: `ConstellationExceptionCode.retryLater` goes out
/// as the numeric-string code 1704 (the store tests also use `RETRY_LATER`).
bool _isRetryLaterCode(Object? code) =>
    code == 'RETRY_LATER' || code?.toString() == '1704';

RemoteApiRetryLaterException? _retryLater(List<GraphQLError> errors) {
  for (final error in errors) {
    final delay = error.extensions?['retryAfterMs'];
    if (_isRetryLaterCode(error.extensions?['code']) &&
        delay is int &&
        delay > 0) {
      return RemoteApiRetryLaterException(Duration(milliseconds: delay));
    }
  }
  return null;
}

GenericException _remoteApiOrUnknown(String message, {Object? code}) {
  final trimmed = message.trim();
  return trimmed.isEmpty
      ? const UnknownException()
      : RemoteApiException(trimmed, code: code?.toString());
}

bool _isGraphQlAuthLoss(GraphQLError error) {
  final code = error.extensions?['code']?.toString().toLowerCase();
  if (code == 'invalid-jwt' || code == 'invalid_jwt') {
    return true;
  }
  final message = error.message.toLowerCase();
  return message.contains('invalid-jwt') ||
      message.contains('could not verify jwt') ||
      message.contains('jwtexpired');
}
