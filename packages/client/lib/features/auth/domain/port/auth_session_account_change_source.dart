import '../exception.dart';

/// Auth transports and repositories that detect a replaced cookie session.
abstract interface class AuthSessionAccountChangeSource {
  Stream<AuthSessionAccountChangedException> get sessionAccountChanges;
}
