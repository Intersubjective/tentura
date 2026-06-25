sealed class ContextException implements Exception {
  const ContextException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

final class ContextCreateException extends ContextException {
  const ContextCreateException([super.message]);
}

final class ContextDeleteException extends ContextException {
  const ContextDeleteException([super.message]);
}

final class ContextUnknownException extends ContextException {
  const ContextUnknownException([super.message]);
}
