import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// How many capability chips a mini-card renders before it caps.
///
/// The §9 height ceiling (224 dp at 360 dp / 1.3x text) holds to three chips
/// only: a fourth long RU label wraps to another chip run and measured 251 dp
/// (journal U14a). The remainder is not dropped silently — it is counted in a
/// `+N` marker next to the chips.
const int kMiniCardCapabilityChipCap = 3;

/// The most of the event-line row the age may occupy before it ellipsises.
///
/// The age is supposed to be compact («2 ч», «40 м», §7), and while it is, it
/// keeps its natural width and this share never binds. The RU day form is not
/// compact at all — «92 дн. назад» measures 156 dp at 1x and 312 dp at 2x —
/// and at 2x it overflowed this row inside a card. 0.7 is above the 1x and
/// 1.3x widths of that string and below its 2x width, so the clamp engages
/// exactly where the row would otherwise break.
const double kMiniCardAgeWidthShare = 0.7;

/// Which event a mini-card shows. Kinds differ by leading glyph/avatar and by
/// body — never by layout (issue-171 card spec §7).
enum AttentionMiniCardKind { event, forward }

/// One event under a Request card header: leading avatar or glyph, event line,
/// optional quoted body behind a left rule, capability chips attached to the
/// forwarder, age with the absolute time in a tooltip, and the dismiss ×.
///
/// Promoted out of the private `_EventSubcard` of
/// `activity_event_subcard_block.dart`; that block keeps its own copy until
/// U14b retires it.
class AttentionMiniCard extends StatefulWidget {
  const AttentionMiniCard({
    required this.receipt,
    this.kind = AttentionMiniCardKind.event,
    this.actor,
    this.quotedBody,
    this.capabilitySlugs = const [],
    this.onTap,
    this.onDismiss,
    this.dismissDuration = const Duration(milliseconds: 180),
    super.key,
  });

  /// Whole ≥48 dp dismiss target (tap / hit-test anchor in tests).
  static const dismissKey = Key('attention-mini-card-dismiss');

  /// The [IconButton] itself, which owns the focus node.
  static const dismissButtonKey = Key('attention-mini-card-dismiss-button');

  static const quoteRuleKey = Key('attention-mini-card-quote-rule');

  static const ageTooltipKey = Key('attention-mini-card-age');

  final AttentionReceipt receipt;
  final AttentionMiniCardKind kind;
  final Profile? actor;

  /// Note or message excerpt shown behind the quote rule. Left-aligned (K4).
  final String? quotedBody;

  /// Capability tags the forwarder attached. Rendered under [quotedBody],
  /// inside the mini-card — never in the card header. Capped to
  /// [kMiniCardCapabilityChipCap] on render.
  final List<String> capabilitySlugs;

  final VoidCallback? onTap;

  /// Clears this event. When null, no dismiss control is rendered.
  ///
  /// Called only after the removal animation completes, so the row keeps its
  /// layout height while the pointer is still down (E32).
  final VoidCallback? onDismiss;

  final Duration dismissDuration;

  @override
  State<AttentionMiniCard> createState() => _AttentionMiniCardState();
}

class _AttentionMiniCardState extends State<AttentionMiniCard>
    with SingleTickerProviderStateMixin {
  static const _pointerDevices = {
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: widget.dismissDuration,
    value: 1,
  );
  final FocusNode _dismissFocus = FocusNode(debugLabel: 'miniCardDismiss');
  bool _dismissing = false;
  bool _hovering = false;

  @override
  void dispose() {
    _collapse.dispose();
    _dismissFocus.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing || widget.onDismiss == null) return;
    setState(() => _dismissing = true);
    final announcement = L10n.of(context)!.attentionEventDismissed;
    final direction = Directionality.of(context);
    _collapse.reverse().whenComplete(() {
      if (!mounted) return;
      // Keep the reading position: hand focus to the next row before this one
      // leaves the tree, so it cannot fall back to the top of the list.
      if (_dismissFocus.hasFocus) {
        _dismissFocus.nextFocus();
      }
      SemanticsService.announce(announcement, direction);
      widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final copy = resolveUpdatesFeedRowCopy(
      title: widget.receipt.title,
      body: widget.receipt.body,
      presentationKey: widget.receipt.presentationKey,
      presentationPayloadJson: widget.receipt.presentationPayloadJson,
      l10n: l10n,
    );
    final profile = widget.actor == null
        ? null
        : profileWithContactOverlay(widget.actor!);
    final shownName = profile?.shownName.trim() ?? '';
    final eventLine = _eventLine(l10n, copy, shownName);
    final localCreatedAt = widget.receipt.createdAt.toLocal();
    final age = compactRelativeTimeAgo(
      when: widget.receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';
    final quoted = widget.quotedBody?.trim() ?? '';

    final leading = profile != null
        ? TenturaAvatar.medium(
            profile: profile,
            onTap: () => context.read<ScreenCubit>().showProfile(profile.id),
          )
        : SizedBox.square(
            dimension: tt.avatarSize,
            child: Builder(
              builder: (context) {
                final glyph = updatesFeedGlyphFor(widget.receipt, tt);
                return Icon(
                  glyph.icon,
                  size: tt.iconSize,
                  color: glyph.color,
                );
              },
            ),
          );

    final content = Padding(
      padding: EdgeInsets.only(top: tt.tightGap, bottom: tt.tightGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          SizedBox(width: tt.avatarTextGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, rowConstraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        // Spoken as one phrase: actor + event + age.
                        child: Semantics(
                          label: _semanticsLabel(eventLine, age),
                          excludeSemantics: true,
                          child: Text(
                            eventLine,
                            style: TenturaText.bodySmall(tt.textMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      SizedBox(width: tt.iconTextGap),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              rowConstraints.maxWidth * kMiniCardAgeWidthShare,
                        ),
                        child: Tooltip(
                          key: AttentionMiniCard.ageTooltipKey,
                          message: absoluteTime,
                          excludeFromSemantics: true,
                          child: Text(
                            age,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TenturaText.withTabular(
                              TenturaText.bodySmall(tt.textFaint),
                            ),
                            semanticsLabel: '',
                          ),
                        ),
                      ),
                      if (widget.onDismiss != null) ...[
                        SizedBox(width: tt.tightGap),
                        _DismissControl(
                          focusNode: _dismissFocus,
                          label: l10n.attentionEventDismiss,
                          emphasised: _hovering,
                          onPressed: _dismiss,
                        ),
                      ],
                    ],
                  ),
                ),
                if (quoted.isNotEmpty || widget.capabilitySlugs.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: tt.tightGap),
                    child: _QuotedBody(
                      body: quoted,
                      capabilitySlugs: widget.capabilitySlugs,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget interactive = content;
    if (widget.onTap != null) {
      interactive = InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        child: interactive,
      );
    }
    if (widget.onDismiss != null) {
      // Secondary tap is a second path to the same ×; long-press is never a
      // dismiss path at all (standing cross-platform rule).
      interactive = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        supportedDevices: _pointerDevices,
        onSecondaryTap: _dismiss,
        child: MouseRegion(
          onEnter: (_) => _setHovering(true),
          onExit: (_) => _setHovering(false),
          child: interactive,
        ),
      );
    }

    return SizeTransition(
      sizeFactor: _collapse,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _collapse,
        child: Material(
          color: Colors.transparent,
          child: interactive,
        ),
      ),
    );
  }

  void _setHovering(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  String _semanticsLabel(String eventLine, String age) =>
      [eventLine, age].where((p) => p.isNotEmpty).join(' · ');

  String _eventLine(L10n l10n, UpdatesFeedRowCopy copy, String shownName) {
    if (widget.kind == AttentionMiniCardKind.forward && shownName.isNotEmpty) {
      return l10n.attentionMiniCardForwarded(shownName);
    }
    final headline = copy.headline.trim();
    final body = copy.body.trim();
    // When the headline is just the actor name (server title for help-offer
    // receipts), prefer the body so the event itself shows.
    final event =
        shownName.isNotEmpty && headline == shownName && body.isNotEmpty
        ? body
        : (headline.isNotEmpty ? headline : body);
    if (shownName.isEmpty) return event;
    if (event.isEmpty || event == shownName) return shownName;
    return '$shownName · $event';
  }
}

class _QuotedBody extends StatelessWidget {
  const _QuotedBody({required this.body, required this.capabilitySlugs});

  final String body;
  final List<String> capabilitySlugs;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      key: AttentionMiniCard.quoteRuleKey,
      // The rule is a left border, so it always spans the whole quoted
      // block — note plus chips — without an intrinsic-height pass.
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tt.border, width: TenturaSpacing.tight),
        ),
      ),
      padding: EdgeInsets.only(left: tt.iconTextGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body.isNotEmpty)
            Text(
              body,
              textAlign: TextAlign.start,
              style: TenturaText.bodySmall(tt.textMuted),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          if (capabilitySlugs.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              child: _CappedCapabilityChips(slugs: capabilitySlugs),
            ),
        ],
      ),
    );
  }
}

/// [ForwardCapabilityChips] under the card's height ceiling: the first
/// [kMiniCardCapabilityChipCap] chips plus a `+N` for whatever is left, so the
/// cap is visible rather than a silent truncation.
class _CappedCapabilityChips extends StatelessWidget {
  const _CappedCapabilityChips({required this.slugs});

  final List<String> slugs;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final shown = slugs.take(kMiniCardCapabilityChipCap).toList();
    final hidden = slugs.length - shown.length;
    final chips = ForwardCapabilityChips(slugs: shown);
    if (hidden <= 0) return chips;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: chips),
        SizedBox(width: tt.tightGap),
        Text('+$hidden', style: TenturaText.labelSmall(tt.textFaint)),
      ],
    );
  }
}

class _DismissControl extends StatelessWidget {
  const _DismissControl({
    required this.focusNode,
    required this.label,
    required this.emphasised,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final String label;
  final bool emphasised;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SizedBox(
      key: AttentionMiniCard.dismissKey,
      width: kMinInteractiveDimension,
      height: kMinInteractiveDimension,
      child: IconButton(
        key: AttentionMiniCard.dismissButtonKey,
        focusNode: focusNode,
        onPressed: onPressed,
        tooltip: label,
        iconSize: tt.iconSize,
        padding: EdgeInsets.zero,
        color: emphasised ? tt.text : tt.textFaint,
        icon: Icon(Icons.close, semanticLabel: label),
      ),
    );
  }
}
