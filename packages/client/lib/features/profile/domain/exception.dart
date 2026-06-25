sealed class ProfileException implements Exception {
  const ProfileException(this.message);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

final class ProfileFetchException extends ProfileException {
  const ProfileFetchException(super.message);
}

final class ProfileDeleteException extends ProfileException {
  const ProfileDeleteException(super.message);
}
