import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/person_list_meta_record.dart';
import 'package:tentura_server/domain/port/people_list_meta_repository_port.dart';

import '_use_case_base.dart';

/// Sort keys for the People tab: for every person the viewer trusts, when the
/// relationship became new (and why) and when the two last interacted.
@Singleton(order: 2)
final class PeopleListMetaCase extends UseCaseBase {
  PeopleListMetaCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final PeopleListMetaRepositoryPort _repository;

  Future<List<PersonListMetaRecord>> fetch({required String viewerId}) =>
      _repository.fetchPeopleListMeta(viewerId: viewerId);
}
