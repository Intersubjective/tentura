import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/model/beacon_model_with_admitted_helpers.dart';

import '../gql/_g/beacon_model_with_help_offer_users.data.gql.dart';

extension type const BeaconModelWithHelpOfferUsers(
  GBeaconModelWithHelpOfferUsers i
) implements GBeaconModelWithHelpOfferUsers {
  Beacon toEntity() {
    final withHelpers = BeaconModelWithAdmittedHelpers(i).toEntity();
    final offerUsers = <Profile>[
      for (final row in i.help_offers) (row.user as UserModel).toEntity(),
    ];
    return withHelpers.copyWith(helpOfferUsers: offerUsers);
  }
}
