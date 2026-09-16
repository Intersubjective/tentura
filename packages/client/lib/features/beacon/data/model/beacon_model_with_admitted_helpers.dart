import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/beacon_model_with_admitted_helpers.data.gql.dart';

extension type const BeaconModelWithAdmittedHelpers(
  GBeaconModelWithAdmittedHelpers i
) implements GBeaconModelWithAdmittedHelpers {
  Beacon toEntity() {
    final base = BeaconModel(i).toEntity();
    final users = <Profile>[
      for (final row in i.admitted_helpers)
        (row.user as UserModel).toEntity(),
    ];
    return base.copyWith(
      admittedHelperUsers: users,
      admittedHelperCount: i.admitted_helpers_aggregate.aggregate?.count ?? 0,
    );
  }
}
