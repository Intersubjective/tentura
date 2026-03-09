import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/env.dart';

void issueJwt(List<String> args) {
  final optionSubIndex = args.indexOf('--sub');
  final userId = optionSubIndex != -1
      ? args[optionSubIndex + 1]
      : 'U3ea0a229ad85';
  final optionExpIndex = args.indexOf('--exp');
  final expiresIn = optionExpIndex != -1
      ? Duration(days: int.parse(args[optionExpIndex + 1]))
      : const Duration(days: 365);

  print(
    JWT({'sub': userId}).sign(
      Env.prod().privateKey,
      algorithm: JWTAlgorithm.EdDSA,
      expiresIn: expiresIn,
    ),
  );
}
