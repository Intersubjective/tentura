import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import 'support/e2e_test_helpers.dart';

/// Web coverage for the resolved request identity (plan §9.6).
///
/// Driven here: authoring a request with capabilities, the persisted
/// photo/symbol preference, symbol selection limited to the request's own
/// capabilities, canonical promotion after the selected primary is removed, and
/// the same resolved identity in the author's My Desk and the recipient's Inbox
/// and detail.
///
/// Not driven here, because the app exposes no seam for it: attaching photos
/// goes through `image_picker`, which opens a browser file dialog no widget test
/// can answer, so staged-photo cover marking, cover crop/replacement, a failed
/// stage with retry, and cover deletion are owned by
/// `test/features/beacon_create/beacon_create_case_test.dart` (staging,
/// reconciliation, partial-failure retry) and
/// `test/features/beacon_create/image_tab_cover_test.dart` (cover marking and
/// removal). An unreadable request's presentation needs a third
/// non-participant account the QA bootstrap does not create; it is owned by
/// `test/ui/widget/beacon_identity_tile_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the resolved request identity is the same on every surface', (
    tester,
  ) async {
    await launchApp(app.main);
    await tester.pumpAndSettle();

    final fixture = await bootstrapFixture(runId: uniqueRunId('beacon-cover'));
    final title = uniqueRequestTitle('IT cover');

    await logout(tester);
    await loginAs(tester, fixture.authorEmail);
    await goToPath(tester, kPathBeaconNew);

    final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
    await pumpUntilVisible(tester, titleField);
    await tester.enterText(titleField, title);
    await tester.enterText(
      find.byKey(TestIds.key(TestIds.requestDescription)),
      'Integration test cover request for $title',
    );
    syncBeaconCreateDraftFields(
      tester,
      title: title,
      description: 'Integration test cover request for $title',
    );
    await tester.pumpAndSettle();

    // Two capabilities: canonical order makes `transport` the primary and
    // `tools` the alternative the author can switch to.
    await _toggleLogisticsRequirements(tester, const ['tools', 'transport']);
    await tapAndSettle(tester, find.byKey(const Key('BeaconCreate.CoverRow')));
    await pumpUntilVisible(tester, _sourceControl());

    // With nothing attached, the photo preference still resolves to the
    // canonical primary symbol.
    expect(_previewIdentity(tester), 'symbol');
    expect(
      find.textContaining(_label(tester, 'transport')),
      findsWidgets,
      reason: 'the cover block names the canonical primary capability',
    );

    // Choosing the symbol preference opens the sheet, which offers only the
    // capabilities this request asks for.
    await tapAndSettle(tester, find.text(_l10n(tester).beaconCoverSourceSymbol));
    await pumpUntilVisible(tester, _symbolOption('tools'));
    expect(_symbolOption('housing'), findsNothing);
    await tapAndSettle(tester, _symbolOption('tools'));
    await pumpUntilVisible(
      tester,
      find.textContaining(_label(tester, 'tools')),
    );
    expect(_previewIdentity(tester), 'symbol');

    await tapAndSettle(tester, find.byIcon(Icons.close_rounded).first);

    // Removing the selected primary promotes the canonical next capability
    // instead of leaving a dangling selection.
    await _toggleLogisticsRequirements(tester, const ['tools']);
    await tapAndSettle(tester, find.byKey(const Key('BeaconCreate.CoverRow')));
    await pumpUntilVisible(tester, _sourceControl());
    await pumpUntilVisible(
      tester,
      find.textContaining(_label(tester, 'transport')),
    );
    expect(_previewIdentity(tester), 'symbol');

    // Publish to the recipient and verify the author's My Desk.
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
    );
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.forwardRecipient(fixture.helperUserId))),
    );
    await tapAndSettle(tester, find.byKey(TestIds.key(TestIds.forwardSubmit)));
    await confirmUncoveredForwardNoteIfPresent(tester);
    await dismissOkDialogIfPresent(tester);

    await goToPath(tester, kPathMyWork);
    await pumpUntilVisible(tester, find.text(title));
    expect(_listIdentity(tester), 'symbol');

    // The recipient's Inbox and detail resolve the same identity.
    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await goToPath(tester, kPathInbox);
    await pumpUntilVisible(tester, find.text(title));
    expect(_listIdentity(tester), 'symbol');

    await openRequestFromInbox(tester, requestTitle: title);
    await pumpUntilVisible(tester, find.byType(BeaconIdentityTile));
    expect(_identityOf(tester, find.byType(BeaconIdentityTile).first), 'symbol');
  });
}

Finder _sourceControl() => find.byKey(const Key('BeaconCover.SourceControl'));

Finder _symbolOption(String slug) =>
    find.byKey(Key('BeaconCover.Symbol.$slug'));

/// A [Scaffold] context, not the [MaterialApp] one: the app element sits above
/// the `Localizations` it installs, so `L10n.of` is null there.
L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(Scaffold).first))!;

String _label(WidgetTester tester, String slug) =>
    CapabilityTag.fromSlug(slug)!.labelOf(_l10n(tester));

/// Which identity branch a tile actually painted, so the assertion covers the
/// resolver and the paint rather than cubit state.
String _identityOf(WidgetTester tester, Finder tile) {
  if (finderHasMatch(
    find.descendant(of: tile, matching: find.byType(TenturaCapabilityGlyph)),
  )) {
    return 'symbol';
  }
  if (finderHasMatch(find.descendant(of: tile, matching: find.byType(Image)))) {
    return 'photo';
  }
  if (finderHasMatch(
    find.descendant(of: tile, matching: find.byIcon(Icons.campaign_outlined)),
  )) {
    return 'neutral';
  }
  throw StateError('no identity branch painted in the tile');
}

String _previewIdentity(WidgetTester tester) => _identityOf(
  tester,
  find
      .descendant(
        of: find.byKey(const Key('BeaconCover.Preview')),
        matching: find.byType(BeaconIdentityTile),
      )
      .first,
);

/// Identity of the only request tile on a list surface. The QA fixture creates
/// fresh accounts per run, so each list holds exactly this request.
String _listIdentity(WidgetTester tester) =>
    _identityOf(tester, find.byType(BeaconIdentityTile).first);

/// Toggles logistics capabilities in the requirements sheet. Groups are
/// accordion sections folded until something in them is selected, so the group
/// header is tapped only when the chips are not already on screen.
Future<void> _toggleLogisticsRequirements(
  WidgetTester tester,
  List<String> slugs,
) async {
  final l10n = _l10n(tester);
  await tapAndSettle(tester, find.text(l10n.beaconRequirementsTitle).first);
  final chips = [
    for (final slug in slugs) find.byKey(TestIds.key(TestIds.capabilityChip(slug))),
  ];
  if (!finderHasMatch(chips.first)) {
    await tapAndSettle(tester, find.text(l10n.capabilityGroupLogistics).first);
  }
  for (final chip in chips) {
    await tapAndSettle(tester, chip);
  }
  await tapAndSettle(tester, find.text(l10n.buttonSave).first);
}
