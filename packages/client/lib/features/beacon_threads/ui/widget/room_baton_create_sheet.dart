import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

import 'room_message_reply_quote.dart';

/// Most people one «Who'll take it?» baton can ask.
const kBatonMaxCandidates = 12;

/// The message a baton started from a message's actions replies to.
typedef BatonReplyContext = ({String authorName, String excerpt});

/// What an edit starts from: the current ask and who is asked, with tiers.
typedef BatonEditInitial = ({String text, Map<String, int> tiers});

/// Opens the sheet where the author writes what needs doing and picks
/// [participants] to ask «Who'll take it?» (optionally with a 1/2/3 priority
/// each). With [replyTo] the baton replies to that message and the text may
/// stay empty. With [initial] the sheet edits an existing baton: it starts
/// filled in and submits with «Save». The sheet closes first, then [onAsk]
/// gets the trimmed text and `[{userId, tier}]`.
Future<void> showRoomBatonCreateSheet(
  BuildContext context, {
  required List<BeaconParticipant> participants,
  required void Function(
    String text,
    List<({String userId, int tier})> candidates,
  )
  onAsk,
  BatonReplyContext? replyTo,
  BatonEditInitial? initial,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (ctx) => Padding(
    // Keeps the text field above the soft keyboard.
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
    child: _CreateSheet(
      participants: participants,
      replyTo: replyTo,
      initial: initial,
      onAsk: (text, candidates) {
        Navigator.pop(ctx);
        onAsk(text, candidates);
      },
    ),
  ),
);

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({
    required this.participants,
    required this.onAsk,
    this.replyTo,
    this.initial,
  });

  final List<BeaconParticipant> participants;
  final BatonReplyContext? replyTo;
  final BatonEditInitial? initial;
  final void Function(
    String text,
    List<({String userId, int tier})> candidates,
  )
  onAsk;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _tiers = <String, int>{};
  final _text = TextEditingController();
  var _setPriority = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _text.text = initial.text;
      // Someone no longer admitted cannot stay asked; they drop out on save.
      final listed = {for (final p in widget.participants) p.userId};
      _tiers.addAll({
        for (final e in initial.tiers.entries)
          if (listed.contains(e.key)) e.key: e.value,
      });
      _setPriority = initial.tiers.values.any((tier) => tier != 1);
    }
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // Priority only means something with two or more people picked; with one,
  // the control is hidden and everyone is sent at priority 1.
  bool get _canOrder => _tiers.length >= 2;

  bool get _hasText => _text.text.trim().isNotEmpty;

  bool get _canAsk =>
      (_hasText || widget.replyTo != null) &&
      _tiers.isNotEmpty &&
      _tiers.length <= kBatonMaxCandidates;

  void _ask() {
    if (!_canAsk) return;
    widget.onAsk(_text.text.trim(), [
      for (final p in widget.participants)
        if (_tiers.containsKey(p.userId))
          (
            userId: p.userId,
            tier: _canOrder && _setPriority ? _tiers[p.userId]! : 1,
          ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final replyTo = widget.replyTo;
    final hPad = EdgeInsets.symmetric(horizontal: tt.screenHPadding);
    // A labelled container: without it a screen reader only hears a bare
    // «Dialog» for the sheet and has no name for the group of its controls.
    return Semantics(
      container: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.batonCreateTitle,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: hPad,
              child: Semantics(
                header: true,
                child: Text(
                  l10n.batonCreateTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap,
              ),
              child: Text(
                l10n.batonCreateHint,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
            if (replyTo != null)
              Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  bottom: tt.rowGap,
                ),
                child: RoomMessageReplyQuote(
                  authorName: replyTo.authorName,
                  excerpt: replyTo.excerpt,
                  unavailable: false,
                ),
              ),
            Padding(
              padding: hPad,
              child: TextField(
                controller: _text,
                autofocus: replyTo == null && widget.initial == null,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.batonCreateTextLabel,
                  helperText: replyTo == null
                      ? null
                      : l10n.batonCreateTextReplyHint,
                ),
              ),
            ),
            SizedBox(height: tt.rowGap),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in widget.participants) ...[
                    // Avatar first, checkbox at the end of the row.
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.trailing,
                      value: _tiers.containsKey(p.userId),
                      onChanged: (picked) => setState(() {
                        if (picked ?? false) {
                          _tiers[p.userId] = 1;
                        } else {
                          _tiers.remove(p.userId);
                        }
                      }),
                      // The name is in the title; the avatar's initials
                      // would be read out before it («BD Boris Driver»).
                      secondary: ExcludeSemantics(
                        child: coordinationLogParticipantAvatar(p),
                      ),
                      title: Text(p.displayLabel(l10n.unknownPerson)),
                    ),
                    // Kept outside the tile: CheckboxListTile merges its
                    // semantics, so a control in its subtitle would receive the
                    // row's tap (unpicking the person) instead of its own.
                    if (_canOrder &&
                        _setPriority &&
                        _tiers.containsKey(p.userId))
                      Padding(
                        padding: EdgeInsets.only(
                          left: tt.screenHPadding,
                          right: tt.screenHPadding,
                          bottom: tt.rowGap,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SegmentedButton<int>(
                            showSelectedIcon: false,
                            // Each segment says whose priority it sets: a bare
                            // «2» means nothing to a screen reader.
                            segments: [
                              for (final tier in const [1, 2, 3])
                                ButtonSegment(
                                  value: tier,
                                  label: Text(
                                    '$tier',
                                    semanticsLabel: l10n
                                        .batonCreateTierSemantics(
                                          p.displayLabel(l10n.unknownPerson),
                                          tier,
                                        ),
                                  ),
                                ),
                            ],
                            selected: {_tiers[p.userId]!},
                            onSelectionChanged: (s) =>
                                setState(() => _tiers[p.userId] = s.first),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            if (_canOrder)
              SwitchListTile(
                value: _setPriority,
                onChanged: (v) => setState(() => _setPriority = v),
                title: Text(l10n.batonCreateTiersToggle),
                subtitle: Text(l10n.batonCreateTiersHint),
              ),
            Padding(
              padding: EdgeInsets.only(
                left: tt.screenHPadding,
                right: tt.screenHPadding,
                bottom: tt.rowGap,
              ),
              child: FilledButton(
                onPressed: _canAsk ? _ask : null,
                child: Text(
                  widget.initial == null
                      ? l10n.batonCreateSubmit
                      : l10n.batonEditSubmit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
