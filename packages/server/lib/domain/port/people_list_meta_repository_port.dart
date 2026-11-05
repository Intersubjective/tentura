import 'package:tentura_server/domain/entity/person_list_meta_record.dart';

// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class PeopleListMetaRepositoryPort {
  /// One record per person [viewerId] trusts, read in a single statement.
  /// Blank [viewerId] yields an empty list.
  Future<List<PersonListMetaRecord>> fetchPeopleListMeta({
    required String viewerId,
  });
}
