import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';

import 'input/_input_types.dart';

export 'package:get_it/get_it.dart';
export 'package:graphql_schema2/graphql_schema2.dart';

base class GqlNodeBase {
  const GqlNodeBase();

  JwtEntity getCredentials(Map<String, dynamic> args) =>
      args[kGlobalInputQueryJwt] as JwtEntity? ??
      (throw const UnauthorizedException());
}
