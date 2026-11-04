import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../gql/_g/user_fetch_by_id.data.gql.dart';
import '../gql/_g/users_fetch_by_ids.data.gql.dart';

/// Maps a profile fetch row (UserModel + ProfileUserFields) to [Profile].
Profile profileFromUserFetchRow(GUserFetchByIdData_user_by_pk row) {
  final base = (row as UserModel).toEntity();
  return base.copyWith(joinedAt: row.created_at.toUtc());
}

Profile profileFromUsersFetchRow(GUsersFetchByIdsData_user row) {
  final base = (row as UserModel).toEntity();
  return base.copyWith(joinedAt: row.created_at.toUtc());
}
