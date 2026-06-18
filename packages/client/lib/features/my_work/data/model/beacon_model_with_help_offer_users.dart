import 'package:tentura/data/model/beacon_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/beacon_model_with_help_offer_users.data.gql.dart';

extension type const BeaconModelWithHelpOfferUsers(
  GBeaconModelWithHelpOfferUsers i
) implements GBeaconModelWithHelpOfferUsers {
  Beacon toEntity() {
    final base = BeaconModel(i).toEntity();
    final users = <Profile>[
      for (final row in i.help_offers)
        (row.user as UserModel).toEntity(),
    ];
    return base.copyWith(helpOfferUsers: users);
  }
}
