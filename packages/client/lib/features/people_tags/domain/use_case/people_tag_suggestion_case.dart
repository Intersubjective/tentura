import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/people_tag_suggestion_event.dart';
import '../port/people_tags_repository_port.dart';

/// Decides when a "Tag them?" card is shown and records what the viewer did
/// with it; the server state (`canSuggest`) decides, the client only keeps a
/// card from appearing twice for one event.
@singleton
final class PeopleTagSuggestionCase extends UseCaseBase {
  PeopleTagSuggestionCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final PeopleTagsRepositoryPort _repository;

  final _shown = <PeopleTagSuggestionEvent>{};
  final _uuid = const Uuid();

  /// True the first time [event] asks and while the server allows suggestions.
  Future<bool> shouldShow(PeopleTagSuggestionEvent event) async {
    if (!_shown.add(event)) return false;
    return (await _repository.personTagSuggestionState()).canSuggest;
  }

  Future<void> notNow(PeopleTagSuggestionEvent event) => _record('skipped');

  Future<void> accepted(PeopleTagSuggestionEvent event) => _record('accepted');

  Future<void> disable() => _record('disabled');

  Future<void> enable() => _record('enabled');

  Future<void> _record(String outcome) => _repository.personTagSuggestionRecord(
    outcome: outcome,
    clientOpId: _uuid.v4(),
  );
}
