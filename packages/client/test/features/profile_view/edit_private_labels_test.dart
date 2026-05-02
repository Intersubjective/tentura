import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/profile_view/ui/dialog/edit_private_labels_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

/// Fake capability repository that records calls and emits changes on demand.
class _FakeCapabilityRepository extends Fake
    implements CapabilityRepositoryPort {
  final _changesController = StreamController<void>.broadcast();

  // Configurable responses.
  List<String> privateLabelsResponse = [];
  PersonCapabilityCues cuesResponse = PersonCapabilityCues.empty;

  // Recorded arguments.
  String? lastSetSubjectId;
  List<String>? lastSetSlugs;
  int setPrivateLabelsCallCount = 0;

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  Future<List<String>> fetchMyPrivateLabelsForUser(String subjectId) async =>
      privateLabelsResponse;

  @override
  Future<void> setPrivateLabels({
    required String subjectId,
    required List<String> slugs,
  }) async {
    lastSetSubjectId = subjectId;
    lastSetSlugs = List.unmodifiable(slugs);
    setPrivateLabelsCallCount++;
  }

  @override
  Future<PersonCapabilityCues> fetchCues(String subjectId) async =>
      cuesResponse;

  @override
  Future<void> dispose() => _changesController.close();

  void emitChange() => _changesController.add(null);

  Future<void> closeStream() => _changesController.close();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in a minimal MaterialApp with l10n and theme.
Widget _appWrapper({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: child,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeCapabilityRepository capabilityRepo;

  setUp(() {
    capabilityRepo = _FakeCapabilityRepository();
    // Register the fake so GetIt.I<CapabilityRepositoryPort>() works inside
    // EditPrivateLabelsDialog (which calls GetIt directly).
    GetIt.I.registerSingleton<CapabilityRepositoryPort>(capabilityRepo);
  });

  tearDown(() async {
    await capabilityRepo.closeStream();
    await GetIt.I.reset();
  });

  // -----------------------------------------------------------------------
  // Test 1: dialog opens and shows Save button
  // -----------------------------------------------------------------------
  testWidgets('dialog opens and displays Save button', (tester) async {
    await tester.pumpWidget(
      _appWrapper(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => unawaited(
              EditPrivateLabelsDialog.show(
                context,
                subjectId: 'U-subject',
                onPrivateLabelsSaved: (_) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // Let the async fetchMyPrivateLabelsForUser future resolve and the
    // bottom-sheet animation finish.
    await tester.pumpAndSettle();

    expect(find.byType(EditPrivateLabelsDialog), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  // -----------------------------------------------------------------------
  // Test 2: chip selection → Save → setPrivateLabels is called
  // -----------------------------------------------------------------------
  testWidgets(
    'selecting a chip then tapping Save calls setPrivateLabels',
    (tester) async {
      await tester.pumpWidget(
        _appWrapper(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => unawaited(
                EditPrivateLabelsDialog.show(
                context,
                subjectId: 'U-subject',
                onPrivateLabelsSaved: (_) {},
              ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the first FilterChip (Transport) to select it.
      final chips = find.byType(FilterChip);
      expect(chips, findsWidgets);
      await tester.tap(chips.first);
      await tester.pumpAndSettle();

      // Tap Save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(capabilityRepo.setPrivateLabelsCallCount, 1);
      expect(capabilityRepo.lastSetSubjectId, 'U-subject');
      // Transport chip was tapped — it must be in the saved slugs.
      expect(capabilityRepo.lastSetSlugs, contains('transport'));
    },
  );

}
