import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_indicators.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// §9's "header + at most visibleCap mini-cards + footer + action row",
/// measured on compact (visibleCap 1) at 360 dp / 1.3x text with the worst
/// case this file builds: a two-line title, a near deadline, and a pinned
/// forward carrying a long note and its chips. Measured 458; the constant
/// leaves one line of headroom.
///
/// #189 rev 2 re-measured it at 504: the change line (a 48 dp tap target) and
/// the footer now always render, where `eventCap = 0` used to drop every
/// event — and «ещё N» with them — on a phone. Hiding nothing without a
/// visible hint costs those two lines.
///
/// The number is the floor of the guarantee, not the guarantee itself — what
/// §9 actually promises is that the height does not depend on how many events
/// the Request has, which the D-171-5b test asserts directly.
const double kCardCeiling360Scale13 = 528;

final _bai = Profile(id: 'u1', displayName: 'Bai Yue');
final _gleb = Profile(id: 'u2', displayName: 'Глеб');
final _mila = Profile(id: 'u3', displayName: 'Мила');
final _petr = Profile(id: 'u4', displayName: 'Пётр');

final _beacon = Beacon(
  id: 'b1',
  title: 'Наши требования',
  createdAt: DateTime.utc(2026, 6, 1),
  updatedAt: DateTime.utc(2026, 6, 18),
  author: const Profile(id: 'a1', displayName: 'Автор'),
  viewerCanForward: true,
);

AttentionReceipt _event({
  required String id,
  String kind = 'roomMessagePosted',
  String presentationKey = 'room_message_posted',
  String title = 'Мила',
  String body = 'Сообщение в комнате',
  String? actorUserId = 'u3',
  DateTime? createdAt,
  bool? personal,
  String? excerpt,
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: kind,
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: createdAt ?? DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: [
    '{"eventType":"$kind"',
    if (personal != null) ',"personal":$personal',
    if (excerpt != null) ',"excerpt":"$excerpt"',
    '}',
  ].join(),
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: actorUserId,
);

InboxProvenance _provenance({
  List<InboxForwardSender> senders = const [],
  int? total,
  InboxLatestNoteForward? pinned,
}) => InboxProvenance(
  senders: senders,
  totalDistinctSenders: total ?? senders.length,
  strongestNotePreview: '',
  latestNoteForward: pinned,
);

final _pinnedForward = InboxLatestNoteForward(
  forwardId: 'f1',
  senderId: 'u1',
  displayName: 'Bai Yue',
  notePreview: 'Ты же с этим возился, глянь',
  forwardedAt: DateTime.utc(2026, 6, 19, 14),
  reasonSlugs: const ['transport', 'tools'],
);

Widget _host(
  Widget child, {
  Locale locale = const Locale('ru'),
  double textScaler = 1,
  Size size = const Size(360, 800),
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

RequestAttentionCard _pinnedCard({
  InboxProvenance? provenance,
  Future<void> Function()? onCantHelp,
  VoidCallback? onOfferHelp,
  Map<String, Profile> actors = const {},
  // Deliberately non-none: "the pinned variant shows no chip" must be a
  // decision the variant makes, not the absence of a relation to show.
  RequestAttentionRelation relation = RequestAttentionRelation.helping,
  Beacon? beacon,
}) => RequestAttentionCard(
  beacon: beacon ?? _beacon,
  relation: relation,
  variant: RequestAttentionCardVariant.pinned,
  facts: const RequestAttentionFacts(
    requestId: 'b1',
    pendingForward: true,
  ),
  provenance: provenance ?? _provenance(pinned: _pinnedForward),
  actors: actors,
  onOpenBeacon: () {},
  onOpenTimeline: () {},
  onOfferHelp: onOfferHelp ?? () {},
  onForward: () {},
  onFollow: () {},
  onCantHelp: onCantHelp,
);

void main() {
  testWidgets('a forward note renders on the primary surface (A7 guard)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_pinnedCard(actors: {'u1': _bai})),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(find.text('Ты же с этим возился, глянь'), findsOneWidget);
    expect(find.text('Переслано: Bai Yue'), findsOneWidget);
  });

  testWidgets('capability chips sit inside the mini-card, never the header', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_pinnedCard(actors: {'u1': _bai})));
    await tester.pumpAndSettle();

    expect(find.byType(AttentionMiniCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AttentionMiniCard),
        matching: find.byType(ForwardCapabilityChips),
      ),
      findsOneWidget,
      reason: 'the chips belong to the forwarder, inside their mini-card',
    );
    expect(
      find.descendant(
        of: find.byKey(RequestAttentionCard.headerKey),
        matching: find.byType(ForwardCapabilityChips),
      ),
      findsNothing,
      reason: 'never in the header — they describe why that person chose you',
    );
  });

  testWidgets('the first slot is the latest note-bearing forward (D-171-5a)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          variant: RequestAttentionCardVariant.grouped,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            unclearedOptionalEvents: 2,
          ),
          // MR order puts a different sender first, and a newer note-less
          // event exists — neither may take the pinned slot.
          provenance: _provenance(
            senders: [
              const InboxForwardSender(id: 'u2', displayName: 'Глеб', mr: 9),
              const InboxForwardSender(id: 'u1', displayName: 'Bai Yue', mr: 1),
            ],
            pinned: _pinnedForward,
          ),
          eventTotal: 2,
          eventsPreview: [
            _event(id: 'e1', createdAt: DateTime.utc(2026, 6, 19, 18)),
          ],
          actors: {'u1': _bai, 'u2': _gleb, 'u3': _mila},
          onOpenBeacon: () {},
          onOpenTimeline: () {},
        ),
        size: const Size(900, 900),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byType(AttentionMiniCard);
    expect(cards, findsWidgets);
    final first = tester.widgetList<AttentionMiniCard>(cards).first;
    expect(first.kind, AttentionMiniCardKind.forward);
    expect(first.quotedBody, 'Ты же с этим возился, глянь');
    expect(first.actor?.id, 'u1');
  });

  testWidgets('note-less forwards coalesce; note-bearing ones do not (K6)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          facts: const RequestAttentionFacts(requestId: 'b1'),
          provenance: _provenance(
            senders: [
              const InboxForwardSender(
                id: 'u1',
                displayName: 'Bai Yue',
                mr: 4,
                notePreview: 'Ты же с этим возился, глянь',
              ),
              // A second note, from somebody other than the pinned sender:
              // it may never be folded into the count either.
              const InboxForwardSender(
                id: 'u2',
                displayName: 'Глеб',
                mr: 3,
                notePreview: 'Могу дать прицеп на выходных',
              ),
              const InboxForwardSender(id: 'u3', displayName: 'Мила', mr: 2),
              const InboxForwardSender(id: 'u4', displayName: 'Пётр', mr: 1),
            ],
            total: 5,
            pinned: _pinnedForward,
          ),
          actors: {'u1': _bai, 'u2': _gleb, 'u3': _mila, 'u4': _petr},
          onOpenBeacon: () {},
          onOpenTimeline: () {},
        ),
        size: const Size(900, 900),
      ),
    );
    await tester.pumpAndSettle();

    // Every note keeps its own mini-card — the pinned one and the other.
    expect(find.text('Ты же с этим возился, глянь'), findsOneWidget);
    expect(find.text('Могу дать прицеп на выходных'), findsOneWidget);
    // Two note-less senders plus the one the window never reached ⇒ one line,
    // and the two note-bearing senders are not in it.
    expect(
      find.byKey(RequestAttentionCard.moreForwardedKey),
      findsOneWidget,
    );
    expect(find.text('Переслали ещё 3'), findsOneWidget);
  });

  testWidgets('with no note above it, the line names the forwarder', (
    tester,
  ) async {
    Future<void> pump(List<InboxForwardSender> senders) => tester.pumpWidget(
      _host(
        RequestAttentionCard(
          key: ValueKey(senders.map((s) => s.id).join()),
          beacon: _beacon,
          facts: const RequestAttentionFacts(requestId: 'b1'),
          provenance: _provenance(senders: senders, total: senders.length),
          onOpenBeacon: () {},
          onOpenTimeline: () {},
        ),
      ),
    );

    await pump(const [
      InboxForwardSender(id: 'u3', displayName: 'Мила', mr: 2),
    ]);
    await tester.pumpAndSettle();
    // Not «ещё 1» — there is nothing above it to be more than.
    expect(find.text('Переслано: Мила'), findsOneWidget);

    await pump(const [
      InboxForwardSender(id: 'u3', displayName: 'Мила', mr: 2),
      InboxForwardSender(id: 'u4', displayName: 'Пётр', mr: 1),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Переслано: Мила и ещё 1'), findsOneWidget);

    // The author forwarding their own Request is already «От Автор».
    await pump(const [
      InboxForwardSender(id: 'a1', displayName: 'Автор', mr: 1),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(RequestAttentionCard.moreForwardedKey), findsNothing);
    expect(find.textContaining('Автор', findRichText: true), findsOneWidget);
  });

  testWidgets('«Ещё N в хронологии» opens the Timeline and never grows the '
      'card (D-171-5b)', (tester) async {
    var timeline = 0;
    Widget build() => _host(
      RequestAttentionCard(
        beacon: _beacon,
        facts: const RequestAttentionFacts(
          requestId: 'b1',
          unclearedOptionalEvents: 5,
        ),
        eventTotal: 5,
        eventsPreview: [
          _event(id: 'e1'),
          _event(id: 'e2'),
          _event(id: 'e3'),
        ],
        actors: {'u3': _mila},
        onOpenBeacon: () {},
        onOpenTimeline: () => timeline++,
        onClearEvent: (_) {},
      ),
    );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byType(RequestAttentionCard)).height;
    final more = find.byKey(RequestAttentionCard.footerTimelineKey);
    expect(more, findsOneWidget);
    // Three general events make one change line; the other four are hidden.
    expect(find.text('Ещё 4 в хронологии ›'), findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(timeline, 1);
    expect(
      tester.getSize(find.byType(RequestAttentionCard)).height,
      before,
      reason: 'it leaves for the Timeline instead of expanding in place',
    );
  });

  testWidgets('height ceiling holds at 360 dp and 1.3x text (§9)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon.copyWith(
            title:
                'Нужен прицеп и пара рук на выходных, иначе всё встанет '
                'совсем — помогите пожалуйста кто может',
            endAt: DateTime.now().add(const Duration(hours: 6)),
          ),
          variant: RequestAttentionCardVariant.pinned,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            pendingForward: true,
            unclearedOptionalEvents: 3,
          ),
          provenance: _provenance(pinned: _pinnedForward),
          eventTotal: 4,
          eventsPreview: [
            _event(id: 'e1'),
            _event(id: 'e2'),
          ],
          actors: {'u1': _bai, 'u3': _mila},
          onOpenBeacon: () {},
          onOpenTimeline: () {},
          onOfferHelp: () {},
          onForward: () {},
          onFollow: () {},
        ),
        textScaler: 1.3,
        size: const Size(360, 1200),
      ),
    );
    await tester.pumpAndSettle();

    // Positive first: a fixture that rendered nothing would satisfy a ceiling.
    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(find.byType(AttentionMiniCard), findsWidgets);
    expect(find.byKey(RequestAttentionCard.overflowKey), findsOneWidget);
    expect(tester.takeException(), isNull);

    final height = tester.getSize(find.byType(RequestAttentionCard)).height;
    expect(height, lessThanOrEqualTo(kCardCeiling360Scale13));
  });

  testWidgets('the pinned card has no ×; declining is a named ⋮ action', (
    tester,
  ) async {
    var declined = 0;
    await tester.pumpWidget(
      _host(
        _pinnedCard(onCantHelp: () async => declined++, actors: {'u1': _bai}),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing on the pinned card offers the quiet private gesture.
    expect(find.byKey(AttentionMiniCard.dismissKey), findsNothing);
    expect(find.byKey(RequestAttentionCard.clearAllKey), findsNothing);

    await tester.tap(find.byKey(RequestAttentionCard.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Не могу помочь'));
    await tester.pumpAndSettle();
    expect(declined, 1);
  });

  testWidgets('a post card has no follow action (#247)', (tester) async {
    await tester.pumpWidget(
      _host(
        _pinnedCard(
          actors: {'u1': _bai},
          beacon: _beacon.copyWith(kind: BeaconKind.post),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(find.byKey(RequestAttentionCard.followKey), findsNothing);
  });

  testWidgets('the pinned card offers help, forward and follow', (
    tester,
  ) async {
    var helped = 0;
    await tester.pumpWidget(
      _host(_pinnedCard(onOfferHelp: () => helped++, actors: {'u1': _bai})),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RequestAttentionCard.offerHelpKey), findsOneWidget);
    expect(find.byKey(RequestAttentionCard.forwardKey), findsOneWidget);
    expect(find.byKey(RequestAttentionCard.followKey), findsOneWidget);
    // Pinned means no relation yet, so no relation chip (§6.1).
    expect(find.byType(TenturaRelationChip), findsNothing);

    await tester.tap(find.byKey(RequestAttentionCard.offerHelpKey));
    await tester.pumpAndSettle();
    expect(helped, 1);
  });

  testWidgets('a grouped card wears its relation and carries no action row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          relation: RequestAttentionRelation.helping,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            unclearedOptionalEvents: 1,
          ),
          eventTotal: 1,
          eventsPreview: [_event(id: 'e1')],
          actors: {'u3': _mila},
          onOpenBeacon: () {},
          onOpenTimeline: () {},
          onClearEvent: (_) {},
          onClearAll: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // #189: the relation is a word on the sub-line, never a chip.
    expect(find.byType(TenturaRelationChip), findsNothing);
    expect(
      find.textContaining('Помогаю · Автор', findRichText: true),
      findsOneWidget,
    );
    expect(find.byKey(RequestAttentionCard.offerHelpKey), findsNothing);
    expect(find.byKey(RequestAttentionCard.followKey), findsNothing);
    // «Разобрано» shows whenever anything is dismissible, one event included.
    expect(find.byKey(RequestAttentionCard.clearAllKey), findsOneWidget);
    expect(find.byKey(RequestAttentionIndicators.dotKey), findsOneWidget);
  });

  testWidgets('Разобрано appears whenever there is an event', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            unclearedOptionalEvents: 2,
          ),
          eventTotal: 2,
          eventsPreview: [
            _event(id: 'e1'),
            _event(id: 'e2'),
          ],
          onOpenBeacon: () {},
          onOpenTimeline: () {},
          onClearEvent: (_) {},
          onClearAll: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RequestAttentionCard.clearAllKey), findsOneWidget);
  });

  testWidgets('Разобрано disappears when nothing is left to clear', (
    tester,
  ) async {
    var timeline = 0;
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          relation: RequestAttentionRelation.following,
          facts: const RequestAttentionFacts(requestId: 'b1'),
          onOpenBeacon: () {},
          onOpenTimeline: () => timeline++,
          onClearAll: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RequestAttentionCard.clearAllKey), findsNothing);
    expect(find.byKey(RequestAttentionIndicators.dotKey), findsNothing);
    // The Timeline is always one tap away, from the footer and from ⋮.
    expect(find.text('Хронология ›'), findsOneWidget);
    expect(find.textContaining('Слежу', findRichText: true), findsOneWidget);

    await tester.tap(find.byKey(RequestAttentionCard.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Журнал'));
    await tester.pumpAndSettle();
    expect(timeline, 1);
  });

  testWidgets('the header names the Request bare and attributes its author', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          facts: const RequestAttentionFacts(requestId: 'b1'),
          onOpenBeacon: () {},
          onOpenTimeline: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Same order as a My Work card: bare title, then who it is from.
    expect(find.text('Наши требования'), findsOneWidget);
    expect(find.textContaining('Автор', findRichText: true), findsWidgets);
    expect(find.textContaining('«'), findsNothing);
    // §6.1: the header carries nothing else — no category, no "updated N ago".
    expect(find.textContaining('обновлен'), findsNothing);
  });

  testWidgets('a user-headlined event is a bare name, a system one a bare '
      'label (§12.10)', (tester) async {
    for (final (kind, expected) in const [
      ('mutualConnectionFormed', 'Автор'),
      ('staleReminder', 'Наши требования'),
    ]) {
      await tester.pumpWidget(
        _host(
          RequestAttentionCard(
            key: ValueKey(kind),
            beacon: _beacon,
            representative: _event(id: 'r', kind: kind),
            facts: const RequestAttentionFacts(requestId: 'b1'),
            onOpenBeacon: () {},
            onOpenTimeline: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(expected), findsWidgets, reason: kind);
      expect(find.text('«Наши требования»'), findsNothing, reason: kind);
    }
  });

  testWidgets('the semantics label is the whole sentence (§11)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RequestAttentionCard(
          beacon: _beacon,
          relation: RequestAttentionRelation.helping,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            unclearedOptionalEvents: 2,
          ),
          eventTotal: 2,
          eventsPreview: [
            _event(id: 'e1'),
            _event(id: 'e2'),
          ],
          actors: {'u3': _mila},
          onOpenBeacon: () {},
          onOpenTimeline: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(
      find.byKey(RequestAttentionCard.semanticsKey),
    );
    expect(semantics.label, contains('Наши требования'));
    expect(semantics.label, contains('Автор'));
    expect(semantics.label, contains('2 новых события'));
    expect(semantics.label, contains('Помогаю'));
  });

  testWidgets('in a list at 360 dp and 2x text, the row below still builds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(
        SizedBox(
          height: 1600,
          child: ListView(
            children: [
              // The worst case the card can present, not the smallest: long RU
              // title, a deadline, a pinned forward with a note, and events
              // behind it. A minimal fixture passes this test whatever the
              // header does, which is the failure mode the test exists for —
              // U16a's verify pass caught it built that way.
              RequestAttentionCard(
                beacon: _beacon.copyWith(
                  title:
                      'Нужен прицеп и пара рук на выходных, иначе всё встанет '
                      'совсем — помогите пожалуйста кто может',
                  endAt: DateTime.now().add(const Duration(hours: 6)),
                ),
                variant: RequestAttentionCardVariant.pinned,
                facts: const RequestAttentionFacts(
                  requestId: 'b1',
                  pendingForward: true,
                  unclearedOptionalEvents: 3,
                ),
                provenance: _provenance(pinned: _pinnedForward),
                eventTotal: 4,
                eventsPreview: [
                  _event(id: 'e1'),
                  _event(id: 'e2'),
                ],
                actors: {'u1': _bai, 'u3': _mila},
                onOpenBeacon: () {},
                onOpenTimeline: () {},
                onOfferHelp: () {},
                onForward: () {},
                onFollow: () {},
              ),
              const Text('следующая строка', key: ValueKey('next')),
            ],
          ),
        ),
        textScaler: 2,
        size: const Size(360, 1600),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RequestAttentionCard), findsOneWidget);
    expect(find.byType(AttentionMiniCard), findsOneWidget);
    expect(find.byKey(const ValueKey('next')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('#189 rev 2 — the «вам» zone and one change line', () {
    RequestAttentionCard grouped({
      required List<AttentionReceipt> events,
      int? total,
      InboxProvenance? provenance,
      ValueChanged<String>? onClearEvent,
      VoidCallback? onClearAll,
    }) => RequestAttentionCard(
      beacon: _beacon,
      relation: RequestAttentionRelation.following,
      facts: RequestAttentionFacts(
        requestId: 'b1',
        unclearedOptionalEvents: total ?? events.length,
      ),
      provenance: provenance ?? InboxProvenance.empty,
      eventTotal: total ?? events.length,
      eventsPreview: events,
      actors: {'u1': _bai, 'u2': _gleb, 'u3': _mila, 'u4': _petr},
      onOpenBeacon: () {},
      onOpenTimeline: () {},
      onClearEvent: onClearEvent ?? (_) {},
      onClearAll: onClearAll ?? () {},
    );

    // Built per test, not at declaration: a bundled CI run declares every
    // file's tests up front, and a minute later "40 мин" reads "41 мин".
    late DateTime now;
    late AttentionReceipt olgaOld;
    late AttentionReceipt olgaNew;
    late AttentionReceipt gleb;
    late AttentionReceipt status;
    setUp(() {
      now = DateTime.now().toUtc();
      olgaOld = _event(
        id: 'm1',
        personal: true,
        excerpt: 'Доски привезу к 10',
        createdAt: now.subtract(const Duration(hours: 3)),
      );
      olgaNew = _event(
        id: 'm2',
        personal: true,
        excerpt: 'А ворота кто откроет?',
        createdAt: now.subtract(const Duration(hours: 2)),
      );
      gleb = _event(
        id: 'm3',
        actorUserId: 'u2',
        personal: true,
        excerpt: 'Я с тачкой',
        createdAt: now.subtract(const Duration(hours: 1)),
      );
      status = _event(
        id: 's1',
        kind: 'blockerOpened',
        presentationKey: 'blocker_opened',
        actorUserId: 'u4',
        personal: false,
        excerpt: 'нет ключа от ворот',
        createdAt: now.subtract(const Duration(minutes: 40)),
      );
    });

    testWidgets('on a phone: one sender row, the others named, and the '
        'change line still shows (the old eventCap = 0 bug)', (tester) async {
      await tester.pumpWidget(
        _host(grouped(events: [status, gleb, olgaNew, olgaOld], total: 6)),
      );
      await tester.pumpAndSettle();

      // Newest sender first, in their own words, with a short age.
      expect(find.text('Глеб: Я с тачкой'), findsOneWidget);
      expect(find.text('Мила: А ворота кто откроет?'), findsNothing);
      expect(find.text('↳ ещё вам: Мила'), findsOneWidget);
      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
      expect(find.text('Блокер: нет ключа от ворот'), findsOneWidget);
      expect(find.text('40 мин'), findsOneWidget);
      // Shown: Gleb's one message and the change line; 4 left in the Timeline.
      expect(find.text('Ещё 4 в хронологии ›'), findsOneWidget);
      // E19: @, not the dot, when something is addressed to you.
      expect(
        find.byKey(RequestAttentionCard.forYouIndicatorKey),
        findsOneWidget,
      );
      expect(find.byKey(RequestAttentionIndicators.dotKey), findsNothing);
    });

    testWidgets('a sender row shows their newest message and its × clears '
        'everything they sent', (tester) async {
      final cleared = <String>[];
      await tester.pumpWidget(
        _host(
          grouped(events: [olgaNew, olgaOld], onClearEvent: cleared.add),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Мила: А ворота кто откроет?'), findsOneWidget);
      expect(find.text('Мила: Доски привезу к 10'), findsNothing);
      await tester.tap(find.byKey(AttentionMiniCard.dismissKey));
      await tester.pumpAndSettle();
      expect(cleared, ['m2', 'm1']);
    });

    testWidgets('an author invite and its answers speak in the «вам» zone '
        '(budding)', (tester) async {
      for (final (kind, key, line) in const [
        (
          'authorInviteReceived',
          'author_invite_received',
          'Глеб зовёт вас помочь',
        ),
        (
          'authorInviteAccepted',
          'author_invite_accepted',
          'Глеб принял(а) приглашение',
        ),
        ('authorInviteDeclined', 'author_invite_declined', 'Глеб не сможет'),
      ]) {
        await tester.pumpWidget(
          _host(
            grouped(
              events: [
                _event(
                  id: kind,
                  kind: kind,
                  presentationKey: key,
                  actorUserId: 'u2',
                  personal: true,
                  createdAt: now.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(line), findsOneWidget, reason: kind);
        expect(
          find.byKey(RequestAttentionCard.forYouIndicatorKey),
          findsOneWidget,
          reason: kind,
        );
        expect(
          find.byKey(RequestAttentionCard.changeLineKey),
          findsNothing,
          reason: kind,
        );
      }
    });

    testWidgets('only general updates: the dot, no «вам» zone', (tester) async {
      await tester.pumpWidget(_host(grouped(events: [status])));
      await tester.pumpAndSettle();

      expect(find.byKey(RequestAttentionCard.forYouZoneKey), findsNothing);
      expect(find.byKey(RequestAttentionCard.forYouIndicatorKey), findsNothing);
      expect(find.byKey(RequestAttentionIndicators.dotKey), findsOneWidget);
      expect(find.text('Хронология ›'), findsOneWidget);
    });

    testWidgets('a forward awaiting your decision is addressed to you: @, '
        'even though forwards never ride the event preview', (tester) async {
      await tester.pumpWidget(_host(_pinnedCard()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(RequestAttentionCard.forYouIndicatorKey),
        findsOneWidget,
      );
      expect(find.byKey(RequestAttentionIndicators.dotKey), findsNothing);
    });

    testWidgets('a note from the author says «(автор)» and the author leaves '
        'the sub-line', (tester) async {
      await tester.pumpWidget(
        _host(
          grouped(
            events: [status],
            provenance: _provenance(
              pinned: InboxLatestNoteForward(
                forwardId: 'f9',
                senderId: 'a1',
                displayName: 'Автор',
                notePreview: 'Приходи, нужен второй ведущий',
                forwardedAt: now.subtract(const Duration(hours: 1)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Переслано: Автор (автор)'), findsOneWidget);
      final subLine = tester.widget<Text>(
        find.byKey(RequestAttentionCard.subLineKey),
      );
      expect(subLine.textSpan!.toPlainText(), 'Слежу');
      // The note took the only phone slot; the change line is still there.
      expect(find.byKey(RequestAttentionCard.changeLineKey), findsOneWidget);
    });

    testWidgets('notes past the cap fold into «ещё N записок», which opens '
        'all of them', (tester) async {
      await tester.pumpWidget(
        _host(
          grouped(
            events: [status],
            provenance: _provenance(
              senders: const [
                InboxForwardSender(
                  id: 'u2',
                  displayName: 'Глеб',
                  mr: 2,
                  notePreview: 'Могу дать прицеп',
                ),
                InboxForwardSender(
                  id: 'u4',
                  displayName: 'Пётр',
                  mr: 1,
                  notePreview: 'Есть перчатки',
                ),
              ],
              pinned: _pinnedForward,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ещё 2 записки ›'), findsOneWidget);
      await tester.tap(find.byKey(RequestAttentionCard.moreNotesKey));
      await tester.pumpAndSettle();
      expect(find.byKey(RequestAttentionCard.notesSheetKey), findsOneWidget);
      expect(find.text('Есть перчатки'), findsOneWidget);
    });

    testWidgets('Разобрано clears the card and names the count', (
      tester,
    ) async {
      var clearedAll = 0;
      await tester.pumpWidget(
        _host(
          grouped(
            events: [status, gleb],
            total: 2,
            onClearAll: () => clearedAll++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Разобрано'), findsOneWidget);
      await tester.tap(find.byKey(RequestAttentionCard.clearAllKey));
      await tester.pump();
      expect(clearedAll, 1);
      expect(find.text('Убрано 2 события'), findsOneWidget);
    });
  });
}
