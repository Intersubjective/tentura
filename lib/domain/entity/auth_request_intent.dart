sealed class AuthRequestIntent {
  const AuthRequestIntent({required this.cname});

  final String cname;

  String get keyCname => 'int';

  static const keyPublicKey = 'pk';

  static const keyRoles = 'roles';

  static const cnameSignIn = 'sign_in';

  static const cnameSignUp = 'sign_up';

  static const cnameSignOut = 'sign_out';
}

final class AuthRequestIntentSignUp extends AuthRequestIntent {
  const AuthRequestIntentSignUp({required this.invitationCode})
    : super(cname: AuthRequestIntent.cnameSignUp);

  final String invitationCode;

  static const keyCode = 'code';
}

final class AuthRequestIntentSignIn extends AuthRequestIntent {
  const AuthRequestIntentSignIn() : super(cname: AuthRequestIntent.cnameSignIn);
}

final class AuthRequestIntentSignOut extends AuthRequestIntent {
  const AuthRequestIntentSignOut()
    : super(cname: AuthRequestIntent.cnameSignOut);
}
