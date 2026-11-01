import 'package:flutter/material.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_event_classification.dart';
import 'package:tentura/domain/attention/closed_request_attention.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/attention/request_card_zones.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/utils/beacon_schedule_presenter.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/one_node_button.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';

import '../../domain/entity/inbox_provenance.dart';
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
    this.onEventTap,
    this.onClearAll,
    this.onOfferHelp,
    this.onForward,
    this.onFollow,
    this.onCantHelp,
    this.cantHelpLabel,
    this.onForwardsGraph,
    this.onComplaint,
    super.key,
  });

  static const semanticsKey = Key('request-attention-card');
  static const headerKey = Key('request-attention-card-header');
  static const overflowKey = Key('request-attention-card-overflow');
  static const clearAllKey = Key('request-attention-card-clear-all');

  /// #189 rev 2 — the card's zones.
  static const subLineKey = Key('request-attention-card-sub-line');
  static const forYouZoneKey = Key('request-attention-card-for-you-zone');
  static const forYouIndicatorKey = Key('request-attention-card-for-you');
  static const alsoToYouKey = Key('request-attention-card-also-to-you');
  static const moreNotesKey = Key('request-attention-card-more-notes');
  static const notesSheetKey = Key('request-attention-card-notes-sheet');
  static const changeLineKey = Key('request-attention-card-change-line');
  static const footerTimelineKey = Key('request-attention-card-timeline');

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

  /// «ещё N» and the ⋮ «Журнал» action both land here (D-171-5b).
  final VoidCallback onOpenTimeline;

  final ValueChanged<String>? onClearEvent;

  /// Opens the selected receipt, preserving its source-message destination.
  final ValueChanged<AttentionReceipt>? onEventTap;
  final VoidCallback? onClearAll;
  final VoidCallback? onOfferHelp;
  final VoidCallback? onForward;
  final VoidCallback? onFollow;

  /// «Не могу помочь». Lives in the overflow menu and opens the rejection
  /// dialog: declining is a social act, and must never wear the quiet private
  /// gesture (E17).
  final Future<void> Function()? onCantHelp;

  /// #725: the menu words for [onCantHelp] when they are not «Can't help»
  /// (an invited viewer's «Can't make it»).
  final String? cantHelpLabel;

  final VoidCallback? onForwardsGraph;
  final VoidCallback? onComplaint;

  bool get _isPinned => variant == RequestAttentionCardVariant.pinned;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleCap = context.windowClass == WindowClass.compact ? 1 : 3;

    final rawZones = RequestCardZones.fromPreview(eventsPreview);
    // One status for the whole row (#740): a closed Request is not a call
    // to action. A stale invitation in the preview is not «something for
    // you»; a person's message, or the viewer's own result, still is.
    final closed = _surfaceClosed;
    final zones = closed
        ? RequestCardZones(
            personalRows: [
              for (final row in rawZones.personalRows)
                if (attentionAddressedAfterClose(row.newest)) row,
            ],
            changeLine: rawZones.changeLine,
          )
        : rawZones;
    final notes = _noteForwards();
    // CAP (#189): the cap counts «вам» rows only and is absolute. Notes come
    // first (D-171-5a, K7), then one row per sender, newest first; what does
    // not fit is *named* below — never silently dropped, and never a reason
    // to drop the change line or the footer (the old `eventCap = 0` bug).
    final shownNotes = notes.take(visibleCap).toList(growable: false);
    final hiddenNotes = notes.length - shownNotes.length;
    final personalCap = visibleCap - shownNotes.length;
    final shownPersonal = zones.personalRows
        .take(personalCap < 0 ? 0 : personalCap)
        .toList(growable: false);
    final hiddenPersonal = zones.personalRows
        .skip(shownPersonal.length)
        .toList(growable: false);
    final shownEvents =
        shownPersonal.fold(0, (sum, row) => sum + row.receipts.length) +
        (zones.changeLine == null ? 0 : 1);
    final hiddenEvents = eventTotal - shownEvents;
    final hasClearable = requestHasDot(facts);

    return Semantics(
      key: semanticsKey,
      container: true,
      label: _semanticsLabel(l10n, zones),
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
                _header(context, l10n, tt, zones),
                SizedBox(height: tt.rowGap),
                if (shownNotes.isNotEmpty ||
                    shownPersonal.isNotEmpty ||
                    hiddenNotes > 0 ||
                    hiddenPersonal.isNotEmpty)
                  _ForYouZone(
                    key: forYouZoneKey,
                    children: [
                      for (final note in shownNotes) _noteRow(l10n, note),
                      for (final row in shownPersonal)
                        _personalRow(context, l10n, row),
                      if (hiddenNotes > 0)
                        _zoneLink(
                          tt,
                          key: moreNotesKey,
                          label: l10n.attentionCardMoreNotes(hiddenNotes),
                          onTap: () => _showNotesSheet(context, l10n, notes),
                        ),
                      if (hiddenPersonal.isNotEmpty)
                        _zoneLink(
                          tt,
                          key: alsoToYouKey,
                          label: _alsoToYou(l10n, hiddenPersonal),
                          onTap: onOpenBeacon,
                        ),
                    ],
                  ),
                _coalescedForwards(
                  l10n,
                  tt,
                  hasNoteSlots: notes.isNotEmpty,
                ),
                if (zones.changeLine case final change?)
                  _ChangeLine(
                    key: changeLineKey,
                    receipt: change,
                    text: _changeText(l10n, change),
                    carriesReason: _changeCarriesReason(change),
                    onTap: onEventTap == null
                        ? null
                        : () => onEventTap!(change),
                  )
                else if (closed)
                  _ChangeLine(
                    key: changeLineKey,
                    receipt: _closedOutcomeReceipt(),
                    text: _closedOutcome(l10n),
                  ),
                if (_isPinned) ...[
                  if (hiddenEvents > 0)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TenturaTextAction(
                        key: footerTimelineKey,
                        label: l10n.attentionCardFooterMore(hiddenEvents),
                        flushStart: true,
                        onPressed: onOpenTimeline,
                      ),
                    ),
                  const TenturaHairlineDivider(),
                  SizedBox(height: tt.tightGap),
                  _actionRow(l10n, tt),
                ] else
                  _footer(
                    context,
                    l10n,
                    tt,
                    hiddenEvents: hiddenEvents,
                    canClear: hasClearable && eventTotal > 0,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  /// Title, then one sub-line «relation · author · deadline if near».
  /// The relation is a word, never a chip or a colour alone (§11); the author
  /// drops out when they are the forwarder the note row already names.
  Widget _header(
    BuildContext context,
    L10n l10n,
    TenturaTokens tt,
    RequestCardZones zones,
  ) {
    final deadline = _deadline(l10n);
    final author = beacon.author.shownName.trim();
    final authorIsForwarder =
        provenance.latestNoteForward?.senderId == beacon.author.id;
    final muted = TenturaText.bodySmall(tt.textMuted);
    final parts = <InlineSpan>[
      if (_relationWord(l10n) case final relation?) TextSpan(text: relation),
      if (author.isNotEmpty &&
          !authorIsForwarder &&
          _headlineTreatment != AttentionHeadlineTreatment.user)
        TextSpan(text: author),
      if (deadline != null)
        TextSpan(
          text: deadline.text,
          // The one danger colour For You allows: an overdue header deadline.
          style: deadline.urgent ? TenturaText.bodySmall(tt.danger) : null,
        ),
    ];

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
              if (parts.isNotEmpty)
                Text.rich(
                  key: subLineKey,
                  TextSpan(
                    style: muted,
                    children: [
                      for (var i = 0; i < parts.length; i++) ...[
                        if (i > 0) const TextSpan(text: ' · '),
                        parts[i],
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        SizedBox(width: tt.tightGap),
        // E19: the slot holds @ (something addressed to you) or the dot
        // (only general updates), never both. A forward awaiting your
        // decision is addressed to you too, though the server keeps
        // `relay_received` out of the preview and the card shows it from
        // provenance instead.
        if (_hasPersonal(zones))
          const _ForYouIndicator()
        else
          RequestAttentionIndicators(facts: facts),
        BeaconOverflowMenu(
          key: overflowKey,
          beacon: beacon,
          onCantHelp: onCantHelp,
          cantHelpActionLabel: cantHelpLabel,
          onForwardsGraph: onForwardsGraph,
          onActivityLog: onOpenTimeline,
          onComplaint: onComplaint,
        ),
      ],
    );
  }

  /// §6.1 — how the title is written, taken from the contract classification
  /// mirror rather than re-decided here.
  AttentionHeadlineTreatment get _headlineTreatment =>
      classifyAttentionEventPayload(
        representative?.presentationPayloadJson,
      ).headlineTreatment;

  String _headline(L10n l10n) {
    return switch (_headlineTreatment) {
      // The Request is the subject. Bare, like every other Request card —
      // the quotes only set this surface apart from My Work.
      AttentionHeadlineTreatment.beacon => beacon.title,
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

  String? _relationWord(L10n l10n) {
    // The pinned variant has no relation yet, by definition (§6.1).
    if (_isPinned) return null;
    return switch (relation) {
      RequestAttentionRelation.none => null,
      RequestAttentionRelation.helping => l10n.attentionRelationHelping,
      RequestAttentionRelation.following => l10n.inboxWatching,
    };
  }

  // ------------------------------------------------------------ «вам» zone

  /// Every note-bearing forward, newest note first (D-171-5a) — never
  /// `senders.first`, which is MR-ranked. A note is never folded (K6).
  List<_NoteForward> _noteForwards() {
    final pinned = provenance.latestNoteForward;
    return [
      if (pinned != null)
        _NoteForward(
          id: 'forward:${pinned.forwardId}',
          senderId: pinned.senderId,
          displayName: pinned.displayName,
          imageId: pinned.imageId,
          note: pinned.notePreview,
          reasonSlugs: pinned.reasonSlugs,
          at: pinned.forwardedAt,
        ),
      for (final sender in provenance.senders)
        if (sender.notePreview.trim().isNotEmpty &&
            sender.id != pinned?.senderId)
          _NoteForward(
            id: 'forward-sender:${sender.id}',
            senderId: sender.id,
            displayName: sender.displayName,
            imageId: sender.imageId,
            note: sender.notePreview,
            reasonSlugs: sender.reasonSlugs,
          ),
    ];
  }

  Widget _noteRow(L10n l10n, _NoteForward note) {
    final actor = _profileOf(note.senderId, note.displayName, note.imageId);
    final name = profileWithContactOverlay(actor).shownName;
    return AttentionMiniCard(
      key: ValueKey(note.id),
      kind: AttentionMiniCardKind.forward,
      receipt: _forwardReceipt(
        id: note.id,
        senderId: note.senderId,
        at: note.at,
      ),
      actor: actor,
      eventLine: note.senderId == beacon.author.id
          ? l10n.attentionCardForwardedByAuthor(name)
          : l10n.attentionCardForwardedBy(name),
      quotedBody: note.note,
      capabilitySlugs: note.reasonSlugs,
      compactAge: true,
      onTap: onOpenBeacon,
    );
  }

  /// One sender, in their own words; the × clears everything they sent.
  Widget _personalRow(
    BuildContext context,
    L10n l10n,
    PersonalSenderRow row,
  ) {
    final receipt = row.newest;
    final actor = actors[receipt.actorUserId ?? ''];
    final name = actor == null
        ? ''
        : profileWithContactOverlay(actor).shownName.trim();
    final dismiss = _isPinned ? null : onClearEvent;
    return AttentionMiniCard(
      key: ValueKey('personal:${row.senderId}:${receipt.id}'),
      receipt: receipt,
      actor: actor,
      eventLine: _personalLine(l10n, receipt, name),
      requestTitle: beacon.title,
      compactAge: true,
      dismissLabel: name.isEmpty ? null : l10n.attentionCardDismissRow(name),
      onTap: onEventTap == null ? null : () => onEventTap!(receipt),
      onDismiss: dismiss == null
          ? null
          : () {
              for (final event in row.receipts) {
                dismiss(event.id);
              }
            },
    );
  }

  /// The sender's own words (§ Тексты). Null leaves the mini-card's own
  /// localized copy for the event.
  String? _personalLine(L10n l10n, AttentionReceipt receipt, String name) {
    if (name.isEmpty) return null;
    final payload = receipt.presentationPayloadJson;
    final words = excerptFromPresentationPayload(payload) ?? '';
    return switch (attentionEventTypeOf(payload)) {
      'roomMessagePosted' when words.isNotEmpty =>
        l10n.attentionCardMessageToYou(name, words),
      'needsMe' when words.isNotEmpty => l10n.attentionCardAsksYou(name, words),
      'promiseMade' when words.isNotEmpty => l10n.attentionCardPromisesYou(
        name,
        words,
      ),
      'offerAccepted' => l10n.attentionCardOfferAccepted(name),
      'offerDeclined' when words.isNotEmpty && words != beacon.title =>
        l10n.attentionCardOfferDeclinedWithReason(name, words),
      'offerDeclined' => l10n.attentionCardOfferDeclined(name),
      'postFirstResponse' => l10n.attentionCardPostFirstReply(name),
      'authorInviteReceived' => l10n.attentionCardInviteReceived(name),
      'authorInviteAccepted' => l10n.attentionCardInviteAccepted(name),
      'authorInviteDeclined' => l10n.attentionCardInviteDeclined(name),
      'blockerOpened' when words.isNotEmpty =>
        l10n.attentionCardBlockerOnYourItem(words),
      _ => null,
    };
  }

  /// «↳ ещё вам: Ольга, Иван и ещё 2» — at most two names, then a number
  /// with no noun after it.
  String _alsoToYou(L10n l10n, List<PersonalSenderRow> hidden) {
    final names = [
      for (final row in hidden)
        if (actors[row.senderId] case final actor?)
          profileWithContactOverlay(actor).shownName.trim(),
    ].where((n) => n.isNotEmpty).toList(growable: false);
    final shown = names.take(2).join(', ');
    final rest = hidden.length - names.take(2).length;
    if (shown.isEmpty) return l10n.attentionCardAlsoToYou('$rest');
    return rest > 0
        ? l10n.attentionCardAlsoToYouMore(shown, rest)
        : l10n.attentionCardAlsoToYou(shown);
  }

  Widget _zoneLink(
    TenturaTokens tt, {
    required Key key,
    required String label,
    required VoidCallback onTap,
  }) => Padding(
    padding: EdgeInsets.only(left: tt.avatarSize + tt.avatarTextGap),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: TenturaTextAction(
        key: key,
        label: label,
        flushStart: true,
        onPressed: onTap,
      ),
    ),
  );

  Future<void> _showNotesSheet(
    BuildContext context,
    L10n l10n,
    List<_NoteForward> notes,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final tt = sheetContext.tt;
      return SafeArea(
        child: ListView(
          key: notesSheetKey,
          shrinkWrap: true,
          padding: tt.cardPadding,
          children: [
            Text(
              l10n.attentionCardNotesSheetTitle,
              style: TenturaText.titleSmall(tt.text),
            ),
            for (final note in notes) _noteRow(l10n, note),
          ],
        ),
      );
    },
  );

  // ----------------------------------------------------------- change line

  /// The newest general event as one line: glyph, text, age. Items churn
  /// reads as one «Пункты обновлены» whatever moved.
  String _changeText(L10n l10n, AttentionReceipt receipt) {
    final payload = receipt.presentationPayloadJson;
    final words = excerptFromPresentationPayload(payload) ?? '';
    final actor = actors[receipt.actorUserId ?? ''];
    final name = actor == null
        ? ''
        : profileWithContactOverlay(actor).shownName.trim();
    final scoped = requestScopedEventCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: payload,
      requestTitle: beacon.title,
      actorName: name,
      l10n: l10n,
    );
    return switch (whoDidWhatEventTypeOf(payload) ??
        attentionEventTypeOf(payload)) {
      'blockerOpened' when words.isNotEmpty => l10n.attentionCardChangeBlocker(
        words,
      ),
      'offerDeclined' when words.isNotEmpty && words != beacon.title =>
        l10n.attentionCardChangeOfferDeclined(words),
      'offerRemoved' when words.isNotEmpty && words != beacon.title =>
        l10n.attentionCardChangeOfferRemoved(words),
      'commitmentReleased' when words.isNotEmpty && words != beacon.title =>
        l10n.attentionCardChangeCommitmentReleased(words),
      'helpOfferSubmitted' when name.isNotEmpty =>
        l10n.attentionCardChangeHelpOffered(name),
      // Who withdrew or can't help, and why, with their note and the
      // next-step flag (#516, #685, #486): `whoDidWhatReceiptDisplayCopy`.
      'helpWithdrawn' || 'forwardDeclined' =>
        scoped.excerpt.isEmpty
            ? scoped.event
            : '${scoped.event} · ${scoped.excerpt.replaceAll('\n', ' · ')}',
      'coordinationChanged' ||
      'promiseMade' ||
      'promiseWithdrawn' ||
      'commitmentAccepted' ||
      'commitmentResolved' ||
      'commitmentCancelled' ||
      'commitmentRedirected' => l10n.attentionCardChangeItemsUpdated,
      _ => scoped.event,
    };
  }

  /// The author's own words ride the line (a decline, removal or release
  /// reason), so it wraps instead of cutting the reason off at one line.
  bool _changeCarriesReason(AttentionReceipt receipt) {
    final payload = receipt.presentationPayloadJson;
    // A withdrawal or «Can't help» line names the person and their reason.
    if (whoDidWhatEventTypeOf(payload) != null) return true;
    final words = excerptFromPresentationPayload(payload) ?? '';
    if (words.isEmpty || words == beacon.title) return false;
    return switch (attentionEventTypeOf(payload)) {
      'offerDeclined' || 'offerRemoved' || 'commitmentReleased' => true,
      _ => false,
    };
  }

  // ---------------------------------------------------------------- footer

  /// «Ещё N в хронологии ›» (or «Хронология ›») — always the Timeline, never
  /// an expansion (D-171-5b) — and «✓ Разобрано» at the far end.
  Widget _footer(
    BuildContext context,
    L10n l10n,
    TenturaTokens tt, {
    required int hiddenEvents,
    required bool canClear,
  }) => Padding(
    padding: EdgeInsets.only(top: tt.tightGap),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TenturaTextAction(
              key: footerTimelineKey,
              label: hiddenEvents > 0
                  ? l10n.attentionCardFooterMore(hiddenEvents)
                  : l10n.attentionCardFooterTimeline,
              flushStart: true,
              onPressed: onOpenTimeline,
            ),
          ),
        ),
        if (canClear && onClearAll != null) ...[
          SizedBox(width: tt.rowGap),
          TenturaTextAction(
            key: clearAllKey,
            label: l10n.attentionCardDone,
            // On a phone the ✓ costs the width «Ещё N в хронологии ›» needs
            // to stay whole; the word alone carries the action.
            icon: context.windowClass == WindowClass.compact
                ? null
                : Icon(Icons.check, size: tt.iconSize),
            onPressed: () {
              final cleared = eventTotal;
              onClearAll!();
              showSnackBar(context, text: l10n.attentionCardCleared(cleared));
            },
          ),
        ],
      ],
    ),
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

  /// §7.3 — note-less forwards fold into one line with overlapping avatars.
  /// Forwards carrying a note never do: the note exists nowhere else on the
  /// card, so folding it destroys it (K6, `coalescible: false`).
  ///
  /// With no note-bearing forward above it the line is not "more" of
  /// anything: it names the forwarder, and says nothing at all when that is
  /// the author the header already names.
  Widget _coalescedForwards(
    L10n l10n,
    TenturaTokens tt, {
    required bool hasNoteSlots,
  }) {
    final pinned = provenance.latestNoteForward;
    final noteLess = provenance.senders
        .where((s) => s.notePreview.trim().isEmpty && s.id != pinned?.senderId)
        .toList(growable: false);
    // Senders the server's window never reached still count — they forwarded.
    final unwindowed =
        provenance.totalDistinctSenders - provenance.senders.length;
    final count = noteLess.length + (unwindowed > 0 ? unwindowed : 0);
    if (count <= 0) return const SizedBox.shrink();
    final String label;
    if (hasNoteSlots || noteLess.isEmpty) {
      label = l10n.attentionCardMoreForwarded(count);
    } else {
      final first = noteLess.first;
      if (count == 1 && first.id == beacon.author.id) {
        return const SizedBox.shrink();
      }
      final name = _profileOf(
        first.id,
        first.displayName,
        first.imageId,
      ).shownName;
      label = count == 1
          ? l10n.attentionCardForwardedBy(name)
          : l10n.attentionCardForwardedByMany(name, count - 1);
    }
    return Padding(
      key: moreForwardedKey,
      // In the card's text column, like the event rows above it: the avatars
      // are part of the line, not a second leading column.
      padding: EdgeInsets.only(
        top: tt.tightGap,
        left: tt.avatarSize + tt.avatarTextGap,
      ),
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
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.bodySmall(tt.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ action row

  /// A `Wrap` hands its children unbounded width, so at 2x text «Предложить
  /// помощь» is wider than the card and overflows the run it sits in. Each
  /// action is capped to the row's own width instead, and wraps inside itself.
  /// Right-aligned with the primary last, like the My Work footer.
  Widget _actionRow(L10n l10n, TenturaTokens tt) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      alignment: WrapAlignment.end,
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

  /// Offer help and Forward share this. A closed Request offers neither.
  bool get _offersHelpOrForward => !_surfaceClosed;

  bool get _surfaceClosed => attentionSurfaceIsClosed(
    beacon: beacon,
    representative: representative,
    eventsPreview: eventsPreview,
  );

  List<Widget> _actions(L10n l10n, TenturaTokens tt) => [
    if (_offersHelpOrForward && onForward != null && beacon.viewerCanForward)
      TenturaTextAction(
        key: forwardKey,
        label: l10n.labelForward,
        onPressed: onForward,
      ),
    if (onFollow != null && beacon.isRequest)
      TenturaTextAction(
        key: followKey,
        label: l10n.beaconHeaderWatch,
        onPressed: onFollow,
      ),
    if (_offersHelpOrForward && onOfferHelp != null)
      // #723: one node carries the name, the tap and the identifier.
      OneNodeButton(
        identifier: TestIds.inboxOfferHelp,
        enabled: true,
        label: l10n.labelOfferHelp,
        onTap: onOfferHelp,
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
  ];

  /// An undismissed «вам» item: a personal receipt, or a forward still
  /// awaiting the viewer's decision. A closed Request keeps the mark only
  /// for a live address (a message, the viewer's own result).
  bool _hasPersonal(RequestCardZones zones) {
    if (_surfaceClosed) {
      return zones.hasPersonal ||
          attentionPreviewHasOwnOutcome([
            ?representative,
            ...eventsPreview,
          ]);
    }
    return zones.hasPersonal || facts.pendingForward;
  }

  AttentionReceipt _closedOutcomeReceipt() => AttentionReceipt(
    id: 'closed:${beacon.id}',
    category: 'requestProgress',
    kind: 'roomActivityLowPriority',
    priority: 'low',
    title: beacon.title,
    body: '',
    actionUrl: '/#/',
    createdAt: beacon.statusChangedAt ?? beacon.updatedAt,
    collapsedCount: 1,
    presentationKey: 'request_status_changed',
    presentationPayloadJson:
        '{"eventType":"requestStatusChanged","toStatus":"${beacon.status.name}"}',
    surface: AttentionSurface.activity,
    beaconId: beacon.id,
  );

  String _closedOutcome(L10n l10n) => l10n.attentionEventStatusChanged(
    switch (beacon.status) {
      BeaconStatus.cancelled => l10n.requestStatusActivityCancelled,
      BeaconStatus.deleted => l10n.beaconHudBeaconUnavailable,
      _ => l10n.requestStatusActivityClosed,
    },
  );

  /// §11 — the whole sentence, so no state is carried by a chip alone.
  String _semanticsLabel(L10n l10n, RequestCardZones zones) {
    final events = facts.unclearedOptionalEvents + facts.unclearedOutcomes;
    final personal =
        zones.personalRows.fold(0, (sum, row) => sum + row.receipts.length) +
        (facts.pendingForward ? 1 : 0);
    return [
      l10n.attentionCardA11yRequest(beacon.title, beacon.author.shownName),
      if (events > 0) l10n.attentionCardA11yEvents(events),
      if (personal > 0) l10n.attentionCardA11yPersonal(personal),
      switch (relation) {
        RequestAttentionRelation.helping => l10n.attentionRelationHelping,
        RequestAttentionRelation.following => l10n.inboxWatching,
        RequestAttentionRelation.none => null,
      },
    ].nonNulls.join(', ');
  }
}

/// A note-bearing forward, from provenance (not a receipt).
class _NoteForward {
  const _NoteForward({
    required this.id,
    required this.senderId,
    required this.displayName,
    required this.imageId,
    required this.note,
    required this.reasonSlugs,
    this.at,
  });

  final String id;
  final String senderId;
  final String displayName;
  final String? imageId;
  final String note;
  final List<String> reasonSlugs;
  final DateTime? at;
}

/// The «вам» zone: what people sent you personally, behind an accent rule so
/// it reads as one block apart from the change line under it.
class _ForYouZone extends StatelessWidget {
  const _ForYouZone({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: tt.attentionHighlight,
            width: TenturaSpacing.tight,
          ),
        ),
      ),
      padding: EdgeInsets.only(left: tt.iconTextGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// E19's other state: «@», there is something addressed to you on this card.
class _ForYouIndicator extends StatelessWidget {
  const _ForYouIndicator();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      key: RequestAttentionCard.forYouIndicatorKey,
      label: L10n.of(context)!.attentionCardForYouIndicator,
      container: true,
      excludeSemantics: true,
      child: Text(
        '@',
        style: TenturaText.titleSmall(tt.attentionHighlight),
      ),
    );
  }
}

/// How many lines a change line carrying the author's reason may wrap to
/// (#601). The server caps the reason at a short excerpt, so this is room for
/// all of it, not a new cut.
const kChangeLineReasonMaxLines = 4;

/// The card's one change line: glyph, text, age. No ×, no avatar, no count.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine({
    required this.receipt,
    required this.text,
    this.carriesReason = false,
    this.onTap,
    super.key,
  });

  final AttentionReceipt receipt;
  final String text;

  /// A reason (at most a short excerpt) wraps to a few lines; every other
  /// change line stays one line.
  final bool carriesReason;
  final VoidCallback? onTap;

  // The age, and the spoken line carrying it, follow the shared clock, so
  // "2m ago" keeps counting while the card stays open (#532). The line is
  // small: rebuilding it on a tick is cheaper than splitting it.
  @override
  Widget build(BuildContext context) =>
      RelativeTimestampTicker(builder: _buildLine);

  Widget _buildLine(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final now = RelativeTimestampTicker.now();
    final age = cardRelativeAge(when: receipt.createdAt, now: now, l10n: l10n);
    final spoken = cardRelativeAgeSpoken(
      when: receipt.createdAt,
      now: now,
      l10n: l10n,
    );
    final style = TenturaText.bodySmall(tt.textMuted);
    // Its own node (#694): without `container`, a line with no tap handler
    // was folded into the card's labelled node and screen readers skipped it.
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$text · $spoken',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: LayoutBuilder(
            builder: (context, rowConstraints) => Row(
              children: [
                SizedBox(
                  width: tt.avatarSize,
                  child: Icon(
                    updatesFeedGlyphFor(receipt, tt).icon,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                ),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Text(
                    text,
                    maxLines: carriesReason ? kChangeLineReasonMaxLines : 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                SizedBox(width: tt.iconTextGap),
                // #609: a dated age ("Sat, Oct 31, 2025") at 2x text is wider
                // than a 360 dp line; capped like the mini card's age;
                // past the cap it wraps rather than losing the year.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: rowConstraints.maxWidth * kMiniCardAgeWidthShare,
                  ),
                  child: Text(
                    age,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.withTabular(style),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
