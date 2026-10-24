import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/gql/_g/schema.schema.gql.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/people_tags_entities.dart';
import '../../domain/port/people_tags_repository_port.dart';
import '../gql/_g/person_auto_tag_members.req.gql.dart';
import '../gql/_g/person_auto_tag_pref_set.req.gql.dart';
import '../gql/_g/person_auto_tags.req.gql.dart';
import '../gql/_g/person_tag_create.req.gql.dart';
import '../gql/_g/person_tag_delete.req.gql.dart';
import '../gql/_g/person_tag_members_apply.req.gql.dart';
import '../gql/_g/person_tag_memberships.req.gql.dart';
import '../gql/_g/person_tag_restore.req.gql.dart';
import '../gql/_g/person_tag_suggestion_record.req.gql.dart';
import '../gql/_g/person_tag_suggestion_state.req.gql.dart';
import '../gql/_g/person_tag_update.req.gql.dart';
import '../gql/_g/person_tags.req.gql.dart';
import '../gql/_g/person_tags_of.req.gql.dart';
import '../model/people_tags_mapper.dart';

@LazySingleton(
  as: PeopleTagsRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
final class PeopleTagsRepository implements PeopleTagsRepositoryPort {
  PeopleTagsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<List<PersonTag>> personTags() => _remoteApiService
      .request(GPersonTagsReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTags([
          for (final t in r.dataOrThrow(label: 'PersonTags').personTags)
            t.toJson(),
        ]),
      );

  @override
  Future<PersonTagsOf> personTagsOf(String personId) => _remoteApiService
      .request(GPersonTagsOfReq((b) => b.vars.personId = personId))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTagsOf(
          r.dataOrThrow(label: 'PersonTagsOf').personTagsOf.toJson(),
        ),
      );

  @override
  Future<List<PersonTagMembers>> personTagMemberships() => _remoteApiService
      .request(GPersonTagMembershipsReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTagMembers([
          for (final m
              in r
                  .dataOrThrow(label: 'PersonTagMemberships')
                  .personTagMemberships)
            m.toJson(),
        ]),
      );

  @override
  Future<List<PersonAutoTag>> personAutoTags() => _remoteApiService
      .request(GPersonAutoTagsReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => [
          for (final t
              in r.dataOrThrow(label: 'PersonAutoTags').personAutoTags)
            mapPersonAutoTag(t.toJson()),
        ],
      );

  @override
  Future<List<String>> personAutoTagMembers(int kind) => _remoteApiService
      .request(GPersonAutoTagMembersReq((b) => b.vars.kind = kind))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonAutoTagMembers(
          r.dataOrThrow(label: 'PersonAutoTagMembers').personAutoTagMembers,
        ),
      );

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() =>
      _remoteApiService
          .request(GPersonTagSuggestionStateReq())
          .firstWhere((e) => e.dataSource == DataSource.Link)
          .then(
            (r) => mapPersonTagSuggestionState(
              r
                  .dataOrThrow(label: 'PersonTagSuggestionState')
                  .personTagSuggestionState
                  .toJson(),
            ),
          );

  @override
  Future<PersonTag> personTagCreate({
    required String name,
    required String clientOpId,
    String? glyph,
    int? color,
  }) => _remoteApiService
      .request(
        GPersonTagCreateReq(
          (b) => b.vars
            ..name = name
            ..glyph = glyph
            ..color = color
            ..clientOpId = clientOpId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTag(
          r.dataOrThrow(label: 'PersonTagCreate').personTagCreate.toJson(),
        ),
      );

  @override
  Future<PersonTag> personTagUpdate({
    required String id,
    required String clientOpId,
    String? name,
    String? glyph,
    int? color,
    int? ord,
  }) => _remoteApiService
      .request(
        GPersonTagUpdateReq(
          (b) => b.vars
            ..id = id
            ..name = name
            ..glyph = glyph
            ..color = color
            ..ord = ord
            ..clientOpId = clientOpId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTag(
          r.dataOrThrow(label: 'PersonTagUpdate').personTagUpdate.toJson(),
        ),
      );

  @override
  Future<PersonTagSnapshot> personTagDelete({
    required String id,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GPersonTagDeleteReq(
          (b) => b.vars
            ..id = id
            ..clientOpId = clientOpId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTagSnapshot(
          r.dataOrThrow(label: 'PersonTagDelete').personTagDelete.toJson(),
        ),
      );

  @override
  Future<PersonTag> personTagRestore({
    required PersonTagSnapshot snapshot,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GPersonTagRestoreReq(
          (b) => b.vars
            ..clientOpId = clientOpId
            ..snapshot.replace(
              Gv2_PersonTagSnapshotInput(
                (s) => s
                  ..tag.replace(
                    Gv2_PersonTagInput(
                      (t) => t
                        ..id = snapshot.tag.id
                        ..name = snapshot.tag.name
                        ..glyph = snapshot.tag.glyph
                        ..color = snapshot.tag.color
                        ..ord = snapshot.tag.ord,
                    ),
                  )
                  ..memberIds = ListBuilder(snapshot.memberIds)
                  ..sources = ListBuilder(snapshot.sources),
              ),
            ),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTag(
          r.dataOrThrow(label: 'PersonTagRestore').personTagRestore.toJson(),
        ),
      );

  @override
  Future<void> personTagMembersApply({
    required List<PersonTagMemberOp> ops,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GPersonTagMembersApplyReq(
          (b) => b.vars
            ..clientOpId = clientOpId
            ..ops = ListBuilder([
              for (final op in ops)
                Gv2_PersonTagMemberOpInput(
                  (o) => o
                    ..tagId = op.tagId
                    ..personId = op.personId
                    ..op = op.add ? 'add' : 'remove'
                    ..source = op.source,
                ),
            ]),
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: 'PersonTagMembersApply'));

  @override
  Future<PersonAutoTag> personAutoTagPrefSet({
    required int kind,
    required bool showInFilters,
  }) => _remoteApiService
      .request(
        GPersonAutoTagPrefSetReq(
          (b) => b.vars
            ..kind = kind
            ..showInFilters = showInFilters,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonAutoTag(
          r
              .dataOrThrow(label: 'PersonAutoTagPrefSet')
              .personAutoTagPrefSet
              .toJson(),
        ),
      );

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) => _remoteApiService
      .request(
        GPersonTagSuggestionRecordReq(
          (b) => b.vars
            ..outcome = outcome
            ..clientOpId = clientOpId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => mapPersonTagSuggestionState(
          r
              .dataOrThrow(label: 'PersonTagSuggestionRecord')
              .personTagSuggestionRecord
              .toJson(),
        ),
      );
}
