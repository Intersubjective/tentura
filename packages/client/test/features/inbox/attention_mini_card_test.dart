import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Ceiling asserted at 360 dp / 1.3x text (spec §9, overseer addition 4).
/// Measured worst case (forward + 3-line note + 3 capability chips): see the
/// journal entry for U14a; the constant leaves one line of headroom.
const double kMiniCardCeiling360Scale13 = 224;

const _anna = Profile(id: 'u1', displayName: 'Anna');

AttentionReceipt _receipt({
  String id = 'e1',
  String title = 'Offered help',
  String body = 'Body',
  String? actorUserId = 'u1',
  String presentationKey = 'help_offer_submitted',
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: actorUserId,
);

Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  double textScaler = 1,
  Size size = const Size(360, 640),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaler),
    ),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  ),
);

/// Minimal list host: removes the row only when the mini-card says so.
class _DismissHost extends StatefulWidget {
  const _DismissHost({required this.ids, this.onDismissed});

  final List<String> ids;
  final ValueChanged<String>? onDismissed;

  @override
  State<_DismissHost> createState() => _DismissHostState();
}

class _DismissHostState extends State<_DismissHost> {
  late final List<String> _ids = List<String>.of(widget.ids);

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final id in _ids)
        AttentionMiniCard(
          key: ValueKey(id),
          receipt: _receipt(id: id, actorUserId: null),
          actor: null,
          onDismiss: () {
            widget.onDismissed?.call(id);
            setState(() => _ids.remove(id));
          },
        ),
    ],
  );
}

void main() {
  testWidgets('forward kind renders event line, quoted note and chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AttentionMiniCard(
          receipt: _receipt(presentationKey: 'relay_received'),
          kind: AttentionMiniCardKind.forward,
          actor: _anna,
          quotedBody: 'Ты же с этим возился, глянь',
          capabilitySlugs: const ['transport', 'tools'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Anna'), findsWidgets);
    expect(find.text('Ты же с этим возился, глянь'), findsOneWidget);
    expect(find.byType(TenturaRelationChip), findsNothing);
    // Capability chips live inside the mini-card, under the note.
    final noteY = tester
        .getTopLeft(
          find.text('Ты же с этим возился, глянь'),
        )
        .dy;
    final chipY = tester.getTopLeft(find.text('Transport')).dy;
    expect(chipY, greaterThan(noteY));
  });

  testWidgets('quoted body is left-aligned behind the rule', (tester) async {
    await tester.pumpWidget(
      _host(
        AttentionMiniCard(
          receipt: _receipt(),
          kind: AttentionMiniCardKind.forward,
          actor: _anna,
          quotedBody: 'short',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('short'));
    expect(text.textAlign, anyOf(isNull, TextAlign.start, TextAlign.left));
    final rule = tester.getRect(find.byKey(AttentionMiniCard.quoteRuleKey));
    expect(
      tester.getTopLeft(find.text('short')).dx,
      greaterThan(rule.right - 1),
    );
  });

  testWidgets('age carries the absolute time in a tooltip', (tester) async {
    await tester.pumpWidget(
      _host(AttentionMiniCard(receipt: _receipt(), actor: _anna)),
    );
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(
      find.byKey(AttentionMiniCard.ageTooltipKey),
    );
    expect(tooltip.message, contains('2026'));
  });

  testWidgets('dismiss is a labelled button with a >=48dp target', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        AttentionMiniCard(
          receipt: _receipt(),
          actor: _anna,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byKey(AttentionMiniCard.dismissKey));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    final label = lookupL10n(const Locale('en')).attentionEventDismiss;
    final node = tester.getSemantics(find.bySemanticsLabel(label));
    expect(node.label, label);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('no dismiss control when onDismiss is null', (tester) async {
    await tester.pumpWidget(
      _host(AttentionMiniCard(receipt: _receipt(), actor: _anna)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AttentionMiniCard.dismissKey), findsNothing);
  });

  testWidgets('layout height is held until pointer-up (E32)', (tester) async {
    final dismissed = <String>[];
    await tester.pumpWidget(
      _host(_DismissHost(ids: const ['a', 'b'], onDismissed: dismissed.add)),
    );
    await tester.pumpAndSettle();

    final firstFinder = find.byKey(const ValueKey('a'));
    final initialHeight = tester.getSize(firstFinder).height;
    final secondTop = tester.getTopLeft(find.byKey(const ValueKey('b'))).dy;
    final dismissCentre = tester.getCenter(
      find.descendant(
        of: firstFinder,
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
    );

    final gesture = await tester.startGesture(dismissCentre);
    await tester.pump();
    // Pointer still down: nothing removed, nothing moved under the thumb.
    expect(dismissed, isEmpty);
    expect(tester.getSize(firstFinder).height, initialHeight);
    expect(tester.getTopLeft(find.byKey(const ValueKey('b'))).dy, secondTop);

    await gesture.up();
    await tester.pump();
    // First frame after pointer-up: the row is still at full height and the
    // parent has not been told to remove it yet.
    expect(dismissed, isEmpty);
    expect(tester.getSize(firstFinder).height, initialHeight);

    await tester.pumpAndSettle();
    expect(dismissed, ['a']);
    expect(find.byKey(const ValueKey('a')), findsNothing);
  });

  testWidgets('removal animates through a shrinking placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _DismissHost(ids: ['a', 'b'])));
    await tester.pumpAndSettle();

    final firstFinder = find.byKey(const ValueKey('a'));
    final initialHeight = tester.getSize(firstFinder).height;
    await tester.tap(
      find.descendant(
        of: firstFinder,
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final midHeight = tester.getSize(firstFinder).height;
    expect(midHeight, lessThan(initialHeight));
    expect(midHeight, greaterThan(0));

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('a')), findsNothing);
  });

  testWidgets('removal is announced to screen readers', (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message! as Map<Object?, Object?>;
        if (map['type'] == 'announce') {
          final data = map['data']! as Map<Object?, Object?>;
          announcements.add(data['message']! as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await tester.pumpWidget(_host(const _DismissHost(ids: ['a', 'b'])));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('a')),
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(announcements, isNotEmpty);
  });

  testWidgets('focus moves to the next row, not to the top', (tester) async {
    await tester.pumpWidget(_host(const _DismissHost(ids: ['a', 'b', 'c'])));
    await tester.pumpAndSettle();

    FocusNode nodeOf(String id) => tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byKey(AttentionMiniCard.dismissButtonKey),
          ),
        )
        .focusNode!;

    nodeOf('a').requestFocus();
    await tester.pump();
    expect(nodeOf('a').hasFocus, isTrue);
    final nextNode = nodeOf('b');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('a')),
        matching: find.byKey(AttentionMiniCard.dismissKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('a')), findsNothing);
    expect(nextNode.hasFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(nextNode));
  });

  testWidgets('secondary tap dismisses on pointer devices', (tester) async {
    final dismissed = <String>[];
    await tester.pumpWidget(
      _host(_DismissHost(ids: const ['a', 'b'], onDismissed: dismissed.add)),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(dismissed, ['a']);
  });

  testWidgets('long-press alone never dismisses', (tester) async {
    final dismissed = <String>[];
    await tester.pumpWidget(
      _host(_DismissHost(ids: const ['a', 'b'], onDismissed: dismissed.add)),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();

    expect(dismissed, isEmpty);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
  });

  testWidgets('height ceiling holds at 360 dp and 1.3x text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        AttentionMiniCard(
          receipt: _receipt(
            title: 'Anna',
            body: 'Пересылаю тебе этот запрос, потому что ты этим занимался',
          ),
          kind: AttentionMiniCardKind.forward,
          actor: _anna,
          quotedBody:
              'Ты же с этим возился прошлой весной, глянь пожалуйста — '
              'нужен прицеп и пара рук на выходных, иначе всё встанет.',
          capabilitySlugs: const ['transport', 'tools', 'physical_help'],
          onDismiss: () {},
        ),
        locale: const Locale('ru'),
        textScaler: 1.3,
        size: const Size(360, 800),
      ),
    );
    await tester.pumpAndSettle();

    final height = tester.getSize(find.byType(AttentionMiniCard)).height;
    expect(height, lessThanOrEqualTo(kMiniCardCeiling360Scale13));
  });
}
