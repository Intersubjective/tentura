import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';

import 'fake_people_tags_repository.dart';

final class CountingPeopleTagsRepository implements PeopleTagsRepositoryPort {
  CountingPeopleTagsRepository(this.store);
  final FakePeopleTagsRepository store;
  int tagsCalls = 0;
  int membershipCalls = 0;

  @override
  Future<List<PersonTag>> personTags() async {
    tagsCalls++;
    return store.personTags();
  }

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async {
    membershipCalls++;
    return store.personTagMemberships();
  }

  @override
  Future<List<PersonAutoTag>> personAutoTags() => store.personAutoTags();

  @override
  Future<PersonTagsOf> personTagsOf(String personId) =>
      store.personTagsOf(personId);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
