import 'package:ferry/ferry.dart' as gql
    show ResponseFormatException, ServerException;
import 'package:gql_exec/gql_exec.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

import 'exception.dart';
import 'session_fetch.dart';

/// Maps transport/API failures to domain exceptions for repositories and cubits.
Never throwClassifiedRemoteFailure(Object? error) {
  throw mapRemoteFailure(error);
}

Object mapRemoteFailure(Object? error) {
  // Already a classified domain exception. The link layer re-wraps anything an
  // earlier link throws (e.g. ErrorLink throwing RemoteApiException after a
  // 200-with-errors response) into a gql.ServerException; once we unwrap that
  // below we re-enter here with the original — pass it through untouched
  // instead of flattening its real message back into raw text.
  if (error is GenericException) {
    return error;
  }
  if (error is AuthSessionLostException) {
    return error;
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
    return _remoteApiOrUnknown(error.message);
  }
  if (error is List<GraphQLError>) {
    for (final e in error) {
      if (_isGraphQlAuthLoss(e)) {
        return const AuthSessionLostException();
      }
    }
    final first = error.isEmpty ? null : error.first;
    if (first != null) {
      return _remoteApiOrUnknown(first.message);
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
      'Malformed server response: ${error.originalException ?? error}',
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
  // Only errors that actually look like a transport/connectivity failure
  // become "no internet". Everything else (client-side StateError from an
  // empty stream, deserialization failures, unhandled link exceptions, …) is
  // a real bug — surface its text instead of a misleading "no internet".
  if (_looksLikeConnectivityFailure(message)) {
    return const ConnectionUplinkException();
  }
  return _remoteApiOrUnknown(raw);
}

/// Heuristic: does this error message look like a network/transport failure?
/// Matches the common socket/timeout/TLS/XHR/fetch signatures across the
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
    'timeoutexception',
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
Object? _mapServerException(gql.ServerException error) {
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
    return _remoteApiOrUnknown(detail);
  }

  // No GraphQL errors, but the server answered with a status code.
  if (status != null) {
    if (status == 401 || status == 403) {
      return const AuthSessionLostException();
    }
    return _remoteApiOrUnknown('Server error (HTTP $status)');
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

GenericException _remoteApiOrUnknown(String message) {
  final trimmed = message.trim();
  return trimmed.isEmpty
      ? const UnknownException()
      : RemoteApiException(trimmed);
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
