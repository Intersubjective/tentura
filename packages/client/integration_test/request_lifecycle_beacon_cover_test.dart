import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
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
    // capabilities this request asks for. Source actions are icon buttons
    // (tooltip only) — tap by key, not by visible "Symbol" label.
    await tapAndSettle(tester, find.byKey(const Key('BeaconCover.SourceSymbol')));
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
    await tapAndSettle(tester, find.byIcon(Icons.close_rounded).first);

    // Publish to the recipient and verify the author's My Desk.
    // Next: Recipients runs async prepare/flush before swapping the step;
    // wait for the recipients chrome (Make live) rather than racing an
    // offstage IndexedStack child (recipients are no longer built early).
    await tapAndSettle(
      tester,
      find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
    );
    await pumpUntilVisible(
      tester,
      find.byKey(TestIds.key(TestIds.requestMakeLive)),
      timeout: const Duration(seconds: 60),
      label: 'recipients step',
    );
    final selectRecipient = find.byKey(
      TestIds.key(TestIds.forwardRecipientCheckbox(fixture.helperUserId)),
    );
    await pumpUntilVisible(tester, selectRecipient);
    await tapAndSettle(tester, selectRecipient);
    final forwardSubmit = find.byKey(TestIds.key(TestIds.forwardSubmit));
    await pumpUntil(
      tester,
      () =>
          finderHasMatch(forwardSubmit) &&
          tester.widget<OutlinedButton>(forwardSubmit).onPressed != null,
      timeout: const Duration(seconds: 30),
      label: 'enabled forward submit',
    );
    await tapAndSettle(tester, forwardSubmit);
    await confirmUncoveredForwardNoteIfPresent(tester);
    await pumpUntilVisible(
      tester,
      find.byType(BeaconSendConfirmationDialog),
      timeout: const Duration(seconds: 60),
      label: 'send confirmation',
    );
    await dismissOkDialogIfPresent(tester);

    await goToPath(tester, kPathMyWork);
    await _expectListIdentitySymbol(tester, title);

    // The recipient sees the forward on Activity (title only); identity is on detail.
    await logout(tester);
    await loginAs(tester, fixture.helperEmail);
    await goToPath(tester, kPathInbox);
    await pumpUntilVisible(tester, find.text(title));

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

Future<void> _expectListIdentitySymbol(WidgetTester tester, String title) async {
  await pumpUntilVisible(tester, find.text(title));
  await pumpUntil(
    tester,
    () => _listIdentityBesideTitle(tester, title) != null,
    label: 'identity glyph beside list title',
  );
  expect(_listIdentityBesideTitle(tester, title), 'symbol');
}

/// Identity glyph on the desk/triage card row that owns [title], not an offstage
/// tab's first [BeaconIdentityTile] (which may omit chrome or lack paint).
String? _listIdentityBesideTitle(WidgetTester tester, String title) {
  final titleFinder = find.text(title);
  if (!finderHasMatch(titleFinder)) {
    return null;
  }
  final headerRow = find.ancestor(
    of: titleFinder.first,
    matching: find.byType(BeaconCardHeaderRow),
  );
  if (!finderHasMatch(headerRow)) {
    return null;
  }
  final tile = find.descendant(
    of: headerRow,
    matching: find.byType(BeaconIdentityTile),
  );
  if (!finderHasMatch(tile)) {
    return null;
  }
  try {
    return _identityOf(tester, tile.first);
  } on StateError {
    return null;
  }
}

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
