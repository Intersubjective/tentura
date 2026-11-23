import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_tag_lens_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_filter_bar.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_rearrange_preview_bar.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/fake_people_tags_repository.dart';
import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
import 'fixtures/constellation_arrange_harness.dart';
import 'fixtures/constellation_field_test_harness.dart';

const _desktop = Size(1280, 800);
const _toolbarKey = Key('constellation.arranging.toolbar');
const _moreKey = Key('constellation.arranging.more');
const _peersCappedKey = Key('constellation.notice.peers_capped');

const _contacts = {'p1': 'Анна', 'p2': 'Борис', 'p3': 'Вера'};

Map<String, dynamic> _fieldResponse({required bool withNotice}) => {
  '__typename': 'query_root',
  'constellationField': {
    '__typename': 'v2_ConstellationField',
    'loadedAt': '2026-11-09T12:00:00.000Z',
    'context': '',
    'peersCapped': withNotice,
    'requestsCapped': false,
    'directContactIds': _contacts.keys.toList(),
    'peers': [
      for (final MapEntry(:key, :value) in _contacts.entries)
        {
          '__typename': 'v2_ConstellationPeer',
          'id': key,
          'displayName': value,
          'contactOnly': false,
          'presence': 'visible',
          'isNew': false,
          'bondContexts': <dynamic>[],
        },
    ],
    'edges': [
      for (final id in _contacts.keys)
        {
          '__typename': 'v2_ConstellationEdge',
          'src': 'ego',
          'dst': id,
          'tier': 1,
        },
    ],
    'requests': <dynamic>[],
    'posts': <dynamic>[],
    'memberWebs': <dynamic>[],
    'anchorProjection': {
      '__typename': 'v2_ConstellationAnchorProjection',
      'revision': '0',
      'anchors': <dynamic>[],
      'pinnedPeers': <dynamic>[],
      'pinnedRequests': <dynamic>[],
      'supportPeers': <dynamic>[],
      'supportEdges': <dynamic>[],
      'serverFilteredBeaconIds': <dynamic>[],
      'serverFilteredBeaconCount': 0,
    },
  },
};

Future<ArrangeHarness> _wireArrangeHarness({required bool withNotice}) async {
  late final ArrangeHarness harness;
  await withRemoteWire(
    {'ConstellationFieldFetch': _fieldResponse(withNotice: withNotice)},
    [],
    (remote) async {
      harness = await arrangeHarness(
        fieldRepository: ConstellationRepository(remote),
      );
    },
  );
  return harness;
}

Rect _visibleFieldChrome(WidgetTester tester, Finder bar, Size surface) {
  final body = find.byType(ConstellationBody);
  final bounds = tester.getRect(body);
  final cap = tester.element(body).tt.fieldTopChromeMaxFraction;
  var visible = (Offset.zero & surface).intersect(
    Rect.fromLTWH(bounds.left, bounds.top, bounds.width, bounds.height * cap),
  );

  // Include the actual viewport clip without requiring the preview to live
  // inside a specific Scrollable.
  var child = tester.renderObject<RenderObject>(bar);
  for (var parent = child.parent; parent != null; parent = parent.parent) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      visible = visible.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    child = parent;
  }
  return visible;
}

Future<List<String>> _checkPreview(
  WidgetTester tester, {
  required Size surface,
  bool withNotice = false,
}) async {
  final phone = surface == kPhoneSurface;
  if (phone) {
    await usePhoneSurface(tester);
  }
  final harness = await _wireArrangeHarness(withNotice: withNotice);
  ConstellationTagLensCubit? tagLens;
  if (phone && !withNotice) {
    // Exercise the normal Field tag controls and enlarged system text in
    // the no-notice case. The toolbar's second row is reachable by tapping.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final tags = await PeopleTagsTestRig.create(FakePeopleTagsRepository());
    final lens = ConstellationTagLensCubit();
    tagLens = lens;
    GetIt.I.registerSingleton<PeopleTagsCase>(tags.peopleTags);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await lens.close();
      await GetIt.I.unregister<PeopleTagsCase>();
      await tags.dispose();
    });
  }
  await pumpArrangeBody(
    tester,
    harness.cubit,
    arrangeV2Enabled: true,
    tagLens: tagLens,
    locale: const Locale('ru'),
    surface: surface,
  );
  expect(tester.getSize(find.byType(Scaffold)), surface);

  final ru = L10nRu();
  await tapConstellationArrangeOverflowAction(
    tester,
    ru.constellationRearrangeEveryone,
  );
  final preview = harness.cubit.state.rearrangePreview;
  expect(preview, isNotNull);

  final bar = find.byType(ConstellationRearrangePreviewBar);
  final toolbar = find.byKey(_toolbarKey);
  final more = find.descendant(of: toolbar, matching: find.byKey(_moreKey));
  final summary = find.descendant(
    of: bar,
    matching: find.text(ru.constellationRearrangePreview(preview!.movingCount)),
  );
  final notices = find.byType(ConstellationFieldNotices);
  final notice = find.descendant(
    of: notices,
    matching: find.byKey(_peersCappedKey),
  );
  expect(
    notice,
    withNotice ? findsOneWidget : findsNothing,
  );
  if (!withNotice) {
    expect(tester.getSize(notices).height, 0);
  }
  expect(more, findsOneWidget);
  expect(summary, findsOneWidget);
  expect(
    tester.renderObject<RenderParagraph>(summary).didExceedMaxLines,
    isFalse,
  );

  final cancel = find.byKey(const Key('constellation-rearrange-cancel'));
  final apply = find.byKey(const Key('constellation-rearrange-apply'));
  final cancelLabel = find.descendant(
    of: cancel,
    matching: find.text(ru.buttonCancel),
  );
  final applyLabel = find.descendant(
    of: apply,
    matching: find.text(ru.planEditApply),
  );
  expect(cancelLabel, findsOneWidget);
  expect(applyLabel, findsOneWidget);

  final barRect = tester.getRect(bar);
  final toolbarRect = tester.getRect(toolbar);
  final summaryRect = tester.getRect(summary);
  final visibleChrome = _visibleFieldChrome(tester, bar, surface);

  // Report all occluded elements in one run and exercise Cancel even when
  // there is a geometry regression elsewhere in the bar.
  final problems = [
    if (summaryRect.intersect(barRect) != summaryRect)
      'Summary $summaryRect extends outside the preview bar $barRect',
    if (summaryRect.top < toolbarRect.bottom)
      'Summary $summaryRect starts under the arranging toolbar $toolbarRect',
    if (phone && barRect.overlaps(toolbarRect))
      'Preview bar $barRect overlaps the arranging toolbar $toolbarRect',
    if (phone && summaryRect.intersect(visibleChrome) != summaryRect)
      'Summary $summaryRect is clipped by the visible Field chrome $visibleChrome',
    if (withNotice && tester.getRect(notice).overlaps(summaryRect))
      'Field notice overlaps the summary',
  ];

  if (phone) {
    for (final (action, label) in [
      (cancel, cancelLabel),
      (apply, applyLabel),
    ]) {
      final name = tester.widget<Text>(label).data;
      final rect = tester.getRect(action);
      if (rect.intersect(barRect) != rect) {
        problems.add('$name $rect extends outside the preview bar $barRect');
      }
      if (tester.getRect(label).intersect(rect) != tester.getRect(label)) {
        problems.add('$name label extends outside its button $rect');
      }
      if (rect.overlaps(toolbarRect)) {
        problems.add('$name $rect overlaps the arranging toolbar $toolbarRect');
      }
      if (rect.intersect(visibleChrome) != rect) {
        problems.add(
          '$name $rect is clipped by the visible Field chrome $visibleChrome',
        );
      }
    }

    await tester.tap(cancel, warnIfMissed: false);
    await tester.pumpAndSettle();
    if (harness.cubit.state.rearrangePreview != null ||
        bar.evaluate().isNotEmpty) {
      problems.add('Tapping Cancel leaves the rearrangement preview open');
    }
  }
  return problems;
}

void main() {
  testWidgets(
    'Russian preview keeps its summary and actions visible without a notice',
    (tester) async {
      expect(await _checkPreview(tester, surface: _desktop), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await _checkPreview(tester, surface: kPhoneSurface), isEmpty);
    },
  );

  testWidgets('Russian phone preview stays visible with a Field notice', (
    tester,
  ) async {
    expect(
      await _checkPreview(tester, surface: kPhoneSurface, withNotice: true),
      isEmpty,
    );
  });
}
