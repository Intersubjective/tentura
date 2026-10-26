import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tag_suggestion_event.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';

final class _FakeRepository implements PeopleTagsRepositoryPort {
  bool disabled = false;
  final recorded = <String>[];

  PersonTagSuggestionState get _state =>
      PersonTagSuggestionState(canSuggest: !disabled, disabled: disabled);

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async => _state;

  @override
  Future<PersonTagSuggestionState> personTagSuggestionRecord({
    required String outcome,
    required String clientOpId,
  }) async {
    recorded.add(outcome);
    if (outcome == 'disabled') disabled = true;
    if (outcome == 'enabled') disabled = false;
    return _state;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeRepository repository;
  late PeopleTagSuggestionCase suggestions;

  setUp(() {
    repository = _FakeRepository();
    suggestions = PeopleTagSuggestionCase(
      repository,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  group('people tag suggestion case enable', () {
    test('enable records the enabled outcome', () async {
      await suggestions.enable();

      expect(repository.recorded, ['enabled']);
    });

    test('suggestions show again after disable then enable', () async {
      await suggestions.disable();
      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('b1')),
        isFalse,
      );

      await suggestions.enable();

      expect(
        await suggestions.shouldShow(PeopleTagSuggestionEvent.closure('b2')),
        isTrue,
      );
    });
  });
}
