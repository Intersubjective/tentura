import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/friends/domain/entity/person_list_meta.dart';

import '../gql/_g/friends_fetch.req.gql.dart';
import '../gql/_g/people_list_meta_fetch.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class FriendsRemoteRepository extends RemoteRepository {
  FriendsRemoteRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<Iterable<Profile>> fetch() async {
    final data = await requestDataOnlineOrThrow(
      GFriendsFetchReq(),
      label: _label,
    );
    return data.vote_user.map((e) => (e.user as UserModel).toEntity());
  }

  Future<Map<String, PersonListMeta>> fetchPeopleListMeta() async {
    final data = await requestDataOnlineOrThrow(
      GPeopleListMetaFetchReq(),
      label: _metaLabel,
    );
    final rows = data.peopleListMeta;
    return {
      for (final row in rows)
        row.id: PersonListMeta(
          id: row.id,
          newSince: _parseDate(row.newSince),
          newReason: PersonListMeta.reasonFromWire(row.newReason),
          lastInteractionAt: _parseDate(row.lastInteractionAt),
        ),
    };
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static const _label = 'Friends';
  static const _metaLabel = 'PeopleListMeta';
}
