import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tag_suggestion_case.dart';

import 'fake_people_tags_repository.dart';
import 'test_realtime_sync.dart';

/// Supplies an empty account-owned tag store for general surface tests.
/// Tag-specific harnesses retain their explicitly registered store.
void registerEmptyPeopleTags() {
  final getIt = GetIt.I;
  if (!getIt.isRegistered<PeopleTagSuggestionCase>()) {
    final suggestions = PeopleTagSuggestionCase(
      FakePeopleTagsRepository(),
      env: const Env(),
      logger: Logger('PeopleTagsWidgetHarness'),
    );
    getIt.registerSingleton<PeopleTagSuggestionCase>(suggestions);
    addTearDown(() async {
      if (getIt.isRegistered<PeopleTagSuggestionCase>() &&
          identical(getIt<PeopleTagSuggestionCase>(), suggestions)) {
        await getIt.unregister<PeopleTagSuggestionCase>();
      }
    });
  }
  if (getIt.isRegistered<PeopleTagsCase>()) return;
  final realtime = buildTestRealtimeSync();
  final peopleTags = PeopleTagsCase(
    FakePeopleTagsRepository(),
    realtime.case_,
    env: const Env(),
    logger: Logger('PeopleTagsWidgetHarness'),
  );
  getIt.registerSingleton<PeopleTagsCase>(peopleTags);
  addTearDown(() async {
    if (getIt.isRegistered<PeopleTagsCase>() &&
        identical(getIt<PeopleTagsCase>(), peopleTags)) {
      await getIt.unregister<PeopleTagsCase>();
    }
    await peopleTags.dispose();
    await realtime.port.dispose();
  });
}

/// Pumps an ordinary product surface with its phase-1 tag dependency present.
extension PeopleTagsWidgetHarness on WidgetTester {
  Future<void> pumpPeopleTagsWidget(
    Widget widget, {
    Duration? duration,
    EnginePhase phase = EnginePhase.sendSemanticsUpdate,
    bool wrapWithView = true,
  }) {
    registerEmptyPeopleTags();
    return pumpWidget(
      widget,
      duration: duration,
      phase: phase,
      wrapWithView: wrapWithView,
    );
  }
}
