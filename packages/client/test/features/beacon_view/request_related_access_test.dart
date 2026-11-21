import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_view/domain/request_access_reason.dart';
import 'package:tentura/features/beacon_view/ui/widget/request_access_reason_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'interactive_descendants.dart';

const _english =
    'You can see this request because you take part in a related request.';
const _russian =
    'Вы видите этот запрос, потому что участвуете в связанном запросе.';
const _excerpt = 'Garden volunteers';
const _child = BeaconAccessReason.contextChild;
const _ancestor = BeaconAccessReason.contextAncestor;
const _observer = BeaconAccessLevel.observer;

Beacon _request(
  List<BeaconAccessReason> reasons, {
  BeaconAccessLevel level = _observer,
}) => Beacon.empty.copyWith(
  id: 'Brequest00001',
  kind: BeaconKind.request,
  accessLevel: level,
  accessReasons: BeaconAccessReason.encode(reasons),
);

void _expectContextReasonsForEveryMask() {
  final knownBits = BeaconAccessReason.encode(BeaconAccessReason.values);
  final competingBits =
      BeaconAccessReason.applied.bit | BeaconAccessReason.forwarded.bit;
  for (final level in [null, ...BeaconAccessLevel.values]) {
    for (var mask = 0; mask <= knownBits; mask++) {
      if (mask & ~knownBits != 0) continue;
      final request = _request(const []).copyWith(
        accessLevel: level,
        accessReasons: mask,
      );
      final eligible = level == _observer && mask & competingBits == 0;
      expect(
        (
          related: requestAccessViaRelated(request),
          parent: requestAccessViaParent(request),
        ),
        (
          related: eligible && mask & (_child.bit | _ancestor.bit) != 0,
          parent: eligible && mask & _child.bit != 0,
        ),
        reason: 'access level ${level?.name}, reason mask $mask',
      );
    }
  }
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Locale locale,
  required Beacon request,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: RequestAccessReasonBanner(
            beacon: request,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectRelatedBannerWithoutPostCopy(
  String relatedText, {
  required RegExp postCopy,
}) {
  final banner = find.byType(RequestAccessReasonBanner);
  final related = find.descendant(
    of: banner,
    matching: find.text(relatedText, findRichText: true),
  );
  final retired = find.descendant(
    of: banner,
    matching: find.textContaining(postCopy, findRichText: true),
  );
  expect(
    {
      'related Request explanation': related.evaluate().length,
      'Post-specific copy': retired.evaluate().length,
      'banner actions': findInteractiveDescendants(banner).evaluate().length,
    },
    {
      'related Request explanation': 1,
      'Post-specific copy': 0,
      'banner actions': 0,
    },
  );
}

void main() {
  testWidgets(
    'Request context explains observer access without naming a Post',
    (
      tester,
    ) async {
      _expectContextReasonsForEveryMask();
      const en = Locale('en');
      for (final (reasons, level, viaRelated) in [
        ([_child], _observer, true),
        ([_ancestor], _observer, true),
        ([_child, BeaconAccessReason.applied], _observer, false),
        ([_child, BeaconAccessReason.forwarded], _observer, false),
        ([_child], BeaconAccessLevel.member, false),
      ]) {
        final request = _request(reasons, level: level);
        await _pumpBanner(
          tester,
          locale: en,
          request: request,
        );
        if (viaRelated) {
          expect(find.text(_english), findsOneWidget, reason: '$reasons');
        } else {
          final banner = find.byType(RequestAccessReasonBanner);
          expect(tester.getSize(banner), Size.zero);
          expect(
            find.descendant(of: banner, matching: find.byType(Text)),
            findsNothing,
          );
        }
      }

      await _pumpBanner(
        tester,
        locale: en,
        request: _request([
          _child,
        ]).copyWith(lineageParentBeaconId: 'Bparent000001'),
      );
      _expectRelatedBannerWithoutPostCopy(
        _english,
        postCopy: RegExp(
          "you're in the post|it grew from|Open the post|$_excerpt",
        ),
      );
    },
  );

  testWidgets(
    'Russian ancestor and parent access explanations fit a 375×667 phone',
    (
      tester,
    ) async {
      await usePhoneSurface(tester);
      const ru = Locale('ru');
      final postCopy = RegExp(
        'участвуете в посте|из которого он вырос|Открыть пост|$_excerpt',
      );
      await _pumpBanner(
        tester,
        locale: ru,
        request: _request([_ancestor]),
      );
      _expectRelatedBannerWithoutPostCopy(_russian, postCopy: postCopy);
      expect(tester.takeException(), isNull);

      await _pumpBanner(
        tester,
        locale: ru,
        request: _request([
          _child,
        ]).copyWith(lineageParentBeaconId: 'Bparent000001'),
      );

      final banner = find.byType(RequestAccessReasonBanner);
      final body = find
          .descendant(of: banner, matching: find.byType(Text))
          .first;
      final paragraph = tester.renderObject<RenderParagraph>(body);
      expect(tester.takeException(), isNull);
      expect(paragraph.didExceedMaxLines, isFalse);
      _expectRelatedBannerWithoutPostCopy(_russian, postCopy: postCopy);
    },
  );
}
