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
  final message = error?.toString().toLowerCase() ?? '';
  if (message.contains('invalid-jwt') ||
      message.contains('invalid jwt') ||
      message.contains('jwtexpired') ||
      message.contains('could not verify jwt')) {
    return const AuthSessionLostException();
  }
  // Everything else reaching here is transport-level (link exceptions,
  // socket/timeout/XHR failures) — connectivity is the honest default.
  return const ConnectionUplinkException();
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
