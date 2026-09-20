import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_event_classification.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';

import '../../domain/entity/inbox_provenance.dart';
import 'activity_event_subcard_block.dart';
import 'attention_mini_card.dart';
import 'request_attention_indicators.dart';

/// Which shape of the one card this is (spec §9 state matrix).
enum RequestAttentionCardVariant {
  /// An unanswered forward: the action row is the whole point, and there is
  /// deliberately **no** × (E17).
  pinned,

  /// Already answered: events under the header, no action row, and the
  /// footer's «Очистить всё» instead.
  grouped,
}

/// The viewer's standing relation to the Request, worn as a first-person chip.
enum RequestAttentionRelation { none, helping, following }

/// The unified For You card (issue-171 spec §6): one Request, headed by what
/// is being asked, with its events as mini-cards underneath.
///
/// Everything on it is evidence for one decision — take it / pass it on /
/// later / no — ranked by weight (§2): the forward note first, then the title,
/// then why me, then urgency, then who is involved. Category, "updated N ago"
/// and non-terminal status lines are deliberately absent.
class RequestAttentionCard extends StatelessWidget {
  const RequestAttentionCard({
    required this.beacon,
    required this.facts,
    required this.onOpenBeacon,
    required this.onOpenTimeline,
    this.variant = RequestAttentionCardVariant.grouped,
    this.relation = RequestAttentionRelation.none,
    this.provenance = InboxProvenance.empty,
    this.representative,
    this.eventTotal = 0,
    this.eventsPreview = const [],
    this.actors = const {},
    this.onClearEvent,
    this.onClearAll,
    this.onOfferHelp,
    this.onForward,
    this.onFollow,
    this.onCantHelp,
    this.onForwardsGraph,
    this.onComplaint,
    super.key,
  });

  static const semanticsKey = Key('request-attention-card');
  static const headerKey = Key('request-attention-card-header');
  static const overflowKey = Key('request-attention-card-overflow');
  static const timelineKey = Key('request-attention-card-timeline');
  static const clearAllKey = Key('request-attention-card-clear-all');

  /// The Offer Help control's key **is** the stable `TestIds.inboxOfferHelp`
  /// key, not a card-private one.
  ///
  /// The retired `CardTriageActionRow` carried `TestIds.inboxOfferHelp` as
  /// both its key and its semantics identifier, and the browser acceptance
  /// journeys drive For You through it (plan §7.3: "use real UI entry points
  /// and stable `TestIds`"). When this card replaced that row the identifier
  /// went with it, and every journey that offers help from triage began
  /// timing out on a button that was on screen — found in U19, the first time
  /// the web e2e gate was run after the redesign. Keep these equal.
  static final offerHelpKey = TestIds.key(TestIds.inboxOfferHelp);
  static const forwardKey = Key('request-attention-card-forward');
  static const followKey = Key('request-attention-card-follow');

  /// The coalesced note-less-forward line (§7.3).
  static const moreForwardedKey = Key('request-attention-card-more-forwarded');

  final Beacon beacon;

  /// The one rule behind the dot and the count (M1) — the same facts the
  /// surface indicator asks, so a card cannot disagree with its tab.
  final RequestAttentionFacts facts;

  final RequestAttentionCardVariant variant;
  final RequestAttentionRelation relation;

  /// Forward provenance for this Request. Its [InboxProvenance.latestNoteForward]
  /// is what the first collapsed slot is pinned to (D-171-5a) — never
  /// `senders.first`, which is MR-ranked and cannot answer "which note is
  /// newest".
  final InboxProvenance provenance;

  /// The receipt whose classification decides how the headline is written
  /// (§6.1). Null — the ordinary case on For You — means the card is headed by
  /// its Request, which is also what an unreadable event type falls back to.
  final AttentionReceipt? representative;

  final int eventTotal;
  final List<AttentionReceipt> eventsPreview;
  final Map<String, Profile> actors;

  final VoidCallback onOpenBeacon;

  /// «ещё N» and «Хронология» both land here (D-171-5b, E30).
  final VoidCallback onOpenTimeline;

  final ValueChanged<String>? onClearEvent;
  final VoidCallback? onClearAll;
  final VoidCallback? onOfferHelp;
  final VoidCallback? onForward;
  final VoidCallback? onFollow;

  /// «Не могу помочь». Lives in the overflow menu and opens the rejection
  /// dialog: declining is a social act, and must never wear the quiet private
  /// gesture (E17).
  final Future<void> Function()? onCantHelp;

  final VoidCallback? onForwardsGraph;
  final VoidCallback? onComplaint;

  bool get _isPinned => variant == RequestAttentionCardVariant.pinned;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleCap = context.windowClass == WindowClass.compact ? 1 : 3;

    final forwards = _forwardSlots(visibleCap);
    final eventCap = visibleCap - forwards.length;
    final hasClearable = requestHasDot(facts);

    return Semantics(
      key: semanticsKey,
      container: true,
      label: _semanticsLabel(l10n),
      child: Material(
        color: tt.surface,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          onTap: onOpenBeacon,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(tt.cardRadius),
              border: Border.all(color: tt.borderSubtle),
            ),
            padding: tt.cardPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, l10n, tt),
                SizedBox(height: tt.rowGap),
                for (final forward in forwards) forward,
                if (eventCap > 0 && eventsPreview.isNotEmpty)
                  ActivityEventSubcardBlock(
                    eventTotal: eventTotal,
                    eventsPreview: eventsPreview,
                    beaconId: beacon.id,
                    actors: actors,
                    visibleCap: eventCap,
                    // D-171-5b: the card's hard maximum height *is* this — the
                    // block leaves for the Timeline instead of growing.
                    overflowPolicy: AttentionBlockOverflowPolicy.timeline,
                    onOpenTimeline: onOpenTimeline,
                    onClearEvent: _isPinned ? null : onClearEvent,
                    quotedBodyOf: _quotedBodyOf,
                  ),
                _coalescedForwards(l10n, tt),
                SizedBox(height: tt.tightGap),
                _footerMeta(l10n, tt, hasClearable: hasClearable),
                if (_isPinned) ...[
                  TenturaHairlineDivider(),
                  SizedBox(height: tt.tightGap),
                  _actionRow(l10n, tt),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context, L10n l10n, TenturaTokens tt) {
    final deadline = _deadline(l10n);
    final author = beacon.author.shownName.trim();
    final subLine = [
      if (author.isNotEmpty) author,
      if (deadline != null) deadline.text,
    ].join(' · ');

    return Row(
      key: headerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeaconIdentityTile(beacon: beacon, size: tt.avatarSize),
        SizedBox(width: tt.avatarTextGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _headline(l10n),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.titleSmall(tt.text),
              ),
              if (subLine.isNotEmpty)
                deadline?.urgent ?? false
                    ? TenturaStatusText(subLine, tone: TenturaTone.danger)
                    : Text(
                        subLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TenturaText.bodySmall(tt.textMuted),
                      ),
            ],
          ),
        ),
        if (_relationChip(l10n) case final chip?) ...[
          SizedBox(width: tt.tightGap),
          chip,
        ],
        SizedBox(width: tt.tightGap),
        RequestAttentionIndicators(facts: facts),
        BeaconOverflowMenu(
          key: overflowKey,
          beacon: beacon,
          onCantHelp: onCantHelp,
          onForwardsGraph: onForwardsGraph,
          onActivityLog: onOpenTimeline,
          onComplaint: onComplaint,
        ),
      ],
    );
  }

  /// §6.1 — how the title is written, taken from the contract classification
  /// mirror rather than re-decided here.
  String _headline(L10n l10n) {
    final treatment = classifyAttentionEventPayload(
      representative?.presentationPayloadJson,
    ).headlineTreatment;
    return switch (treatment) {
      // The Request is the subject: quoted, per locale.
      AttentionHeadlineTreatment.beacon => l10n.attentionCardQuotedTitle(
        beacon.title,
      ),
      // A person is the subject: their bare name.
      AttentionHeadlineTreatment.user => beacon.author.shownName,
      // The system is the subject: a bare label.
      AttentionHeadlineTreatment.system => beacon.title,
    };
  }

  /// Rendered only while near or overdue (§6.1) — a far-off date carries no
  /// decision weight and is header noise.
  ({String text, bool urgent})? _deadline(L10n l10n) {
    final endAt = beacon.endAt;
    if (endAt == null) return null;
    final remaining = endAt.difference(DateTime.now());
    if (remaining > kScheduleAbsoluteThreshold) return null;
    return compactDeadlineLabel(l10n, endAt);
  }

  Widget? _relationChip(L10n l10n) {
    // The pinned variant has no relation yet, by definition (§6.1).
    if (_isPinned) return null;
    return switch (relation) {
      RequestAttentionRelation.none => null,
      RequestAttentionRelation.helping => TenturaRelationChip(
        label: l10n.attentionRelationHelping,
        tone: TenturaRelationTone.helping,
      ),
      RequestAttentionRelation.following => TenturaRelationChip(
        label: l10n.inboxWatching,
        tone: TenturaRelationTone.following,
      ),
    };
  }

  // ------------------------------------------------------------ mini-cards

  /// Forward mini-cards, pinned slot first (D-171-5a), then the remaining
  /// note-bearing senders. Note-less forwards never take a slot — they
  /// coalesce (§7.3).
  List<Widget> _forwardSlots(int visibleCap) {
    final pinned = provenance.latestNoteForward;
    final rest = provenance.senders.where(
      (s) => s.notePreview.trim().isNotEmpty && s.id != pinned?.senderId,
    );
    final slots = <Widget>[];
    if (pinned != null) slots.add(_pinnedForwardCard(pinned));
    for (final sender in rest) {
      if (slots.length >= visibleCap) break;
      slots.add(_senderForwardCard(sender));
    }
    return slots.take(visibleCap).toList(growable: false);
  }

  Widget _pinnedForwardCard(InboxLatestNoteForward forward) =>
      AttentionMiniCard(
        key: ValueKey('forward:${forward.forwardId}'),
        kind: AttentionMiniCardKind.forward,
        receipt: _forwardReceipt(
          id: 'forward:${forward.forwardId}',
          senderId: forward.senderId,
          at: forward.forwardedAt,
        ),
        actor: _profileOf(
          forward.senderId,
          forward.displayName,
          forward.imageId,
        ),
        quotedBody: forward.notePreview,
        capabilitySlugs: forward.reasonSlugs,
        onTap: onOpenBeacon,
      );

  Widget _senderForwardCard(InboxForwardSender sender) => AttentionMiniCard(
    key: ValueKey('forward-sender:${sender.id}'),
    kind: AttentionMiniCardKind.forward,
    receipt: _forwardReceipt(
      id: 'forward-sender:${sender.id}',
      senderId: sender.id,
      at: null,
    ),
    actor: _profileOf(sender.id, sender.displayName, sender.imageId),
    quotedBody: sender.notePreview,
    capabilitySlugs: sender.reasonSlugs,
    onTap: onOpenBeacon,
  );

  /// Provenance is not a receipt — it comes from `inbox_provenance_data` — so
  /// the mini-card is handed the minimum receipt it needs to render a forward.
  /// `relayReceived` is the event type the server writes for exactly this, and
  /// it is the one the classification mirror reads as never-coalescible (K6).
  AttentionReceipt _forwardReceipt({
    required String id,
    required String senderId,
    required DateTime? at,
  }) => AttentionReceipt(
    id: id,
    category: 'forward',
    kind: 'relayReceived',
    priority: 'normal',
    title: '',
    body: '',
    actionUrl: '/#/',
    createdAt: at ?? beacon.updatedAt,
    collapsedCount: 1,
    presentationKey: 'relay_received',
    presentationPayloadJson: '{"eventType":"relayReceived"}',
    surface: AttentionSurface.activity,
    beaconId: beacon.id,
    actorUserId: senderId,
  );

  Profile _profileOf(String id, String displayName, String? imageId) {
    final resolved = actors[id];
    if (resolved != null) return resolved;
    final hasImage = imageId != null && imageId.isNotEmpty && imageId != 'null';
    return Profile(
      id: id,
      displayName: displayName,
      contactName: contactNameOf(id),
      image: hasImage ? ImageEntity(id: imageId, authorId: id) : null,
    );
  }

  /// The mini-card prefers the body only when an actor profile resolved, so
  /// the excerpt is handed over explicitly.
  String? _quotedBodyOf(AttentionReceipt receipt) {
    final body = receipt.body.trim();
    return body.isEmpty || body == receipt.title.trim() ? null : body;
  }

  /// §7.3 — note-less forwards fold into one line with overlapping avatars.
  /// Forwards carrying a note never do: the note exists nowhere else on the
  /// card, so folding it destroys it (K6, `coalescible: false`).
  Widget _coalescedForwards(L10n l10n, TenturaTokens tt) {
    final pinned = provenance.latestNoteForward;
    final noteLess = provenance.senders
        .where((s) => s.notePreview.trim().isEmpty && s.id != pinned?.senderId)
        .toList(growable: false);
    // Senders the server's window never reached still count — they forwarded.
    final unwindowed =
        provenance.totalDistinctSenders - provenance.senders.length;
    final count = noteLess.length + (unwindowed > 0 ? unwindowed : 0);
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      key: moreForwardedKey,
      padding: EdgeInsets.only(top: tt.tightGap),
      child: Row(
        children: [
          CompactForwarderAvatars(
            profiles: [
              for (final sender in noteLess)
                _profileOf(sender.id, sender.displayName, sender.imageId),
            ],
            overflowCount: unwindowed > 0 ? unwindowed : 0,
          ),
          SizedBox(width: tt.iconTextGap),
          Flexible(
            child: Text(
              l10n.attentionCardMoreForwarded(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.bodySmall(tt.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- footer

  Widget _footerMeta(
    L10n l10n,
    TenturaTokens tt, {
    required bool hasClearable,
    // A Wrap, not a Row: at RU width «Хронология» and «Очистить всё» together
    // overflow 360 dp, and a meta line is exactly the thing that may reflow.
  }) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: tt.rowGap,
    runSpacing: tt.tightGap,
    children: [
      // E30 / A4: with «ещё N» gone to the Timeline, this is the entry point
      // that must exist on every card, always.
      TenturaTextAction(
        key: timelineKey,
        label: l10n.labelTimeline,
        onPressed: onOpenTimeline,
      ),
      if (!_isPinned && hasClearable && onClearAll != null)
        TenturaTextAction(
          key: clearAllKey,
          label: l10n.attentionCardClearAll,
          onPressed: onClearAll,
        ),
    ],
  );

  // ------------------------------------------------------------ action row

  /// A `Wrap` hands its children unbounded width, so at 2x text «Предложить
  /// помощь» is wider than the card and overflows the run it sits in. Each
  /// action is capped to the row's own width instead, and wraps inside itself.
  Widget _actionRow(L10n l10n, TenturaTokens tt) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: tt.rowGap,
      runSpacing: tt.tightGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final action in _actions(l10n, tt))
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: action,
          ),
      ],
    ),
  );

  List<Widget> _actions(L10n l10n, TenturaTokens tt) => [
    if (onOfferHelp != null)
      Semantics(
        identifier: TestIds.inboxOfferHelp,
        button: true,
        child: FilledButton.tonal(
          key: offerHelpKey,
          onPressed: onOfferHelp,
          style: FilledButton.styleFrom(
            minimumSize: Size(0, tt.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.symmetric(
              horizontal: tt.rowGap,
              vertical: tt.tightGap,
            ),
          ),
          child: Text(l10n.labelOfferHelp, textAlign: TextAlign.center),
        ),
      ),
    if (onForward != null && beacon.allowsForward)
      TenturaTextAction(
        key: forwardKey,
        label: l10n.labelForward,
        onPressed: onForward,
      ),
    if (onFollow != null)
      TenturaTextAction(
        key: followKey,
        label: l10n.beaconHeaderWatch,
        onPressed: onFollow,
      ),
  ];

  /// §11 — the whole sentence, so no state is carried by a chip alone.
  String _semanticsLabel(L10n l10n) {
    final events = facts.unclearedOptionalEvents + facts.unclearedOutcomes;
    return [
      l10n.attentionCardA11yRequest(beacon.title, beacon.author.shownName),
      if (events > 0) l10n.attentionCardA11yEvents(events),
      switch (relation) {
        RequestAttentionRelation.helping => l10n.attentionRelationHelping,
        RequestAttentionRelation.following => l10n.inboxWatching,
        RequestAttentionRelation.none => null,
      },
    ].nonNulls.join(', ');
  }
}
