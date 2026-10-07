import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// A recognised remote load failure that can be presented and retried.
/// An arbitrary Exception, StateError, or assertion failure is not sufficient.
Matcher remoteLoadFailure() => allOf(
  isNot(isA<StateError>()),
  anyOf([
    isA<GraphQLException>(),
    isA<GraphQLNoDataException>(),
    isA<RemoteApiException>(),
    isA<ConnectionUplinkException>(),
    isA<AuthenticationException>(),
    isA<AuthSessionLostException>(),
    isA<SessionAuthRejectedException>(),
    isA<ServerException>(),
  ]),
);
