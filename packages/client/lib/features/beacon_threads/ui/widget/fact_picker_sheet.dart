import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_copy_destination_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Plan §7.3: search is shown only once the listed facts exceed this count.
const _kFactPickerSearchThreshold = 5;

/// Fact picker for the composer's attach-menu "Fact" item (plan §7.2 B).
///
/// Lists every live (non-removed) fact from the room's fact cards; tapping
/// one sets it as the room's pending quoted fact and closes.
///
/// A writable room adds a «Saved» tab with the viewer's saved facts (plan
/// D19, D20, §6.3): one from elsewhere is copied here, then quoted.
///
/// [onAddFact] opens the host's Add-fact form; when given, an empty picker
/// offers "Pin your first fact" instead of a dead end (#481).
Future<void> showFactPickerSheet(
  BuildContext context, {
  required RoomCubit cubit,
  VoidCallback? onAddFact,
  bool isPost = false,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) =>
        FactPickerSheet(cubit: cubit, onAddFact: onAddFact, isPost: isPost),
  );
}

class FactPickerSheet extends StatefulWidget {
  const FactPickerSheet({
    required this.cubit,
    this.onAddFact,
    this.isPost = false,
    super.key,
  });

  final RoomCubit cubit;

  /// Lists a Post's own facts, headed «In this Post» (plan D5).
  final bool isPost;

  /// Closes the picker first, then is called once (#481).
  final VoidCallback? onAddFact;

  @override
  State<FactPickerSheet> createState() => _FactPickerSheetState();
}

class _FactPickerSheetState extends State<FactPickerSheet> {
  static const _savedTab = 1;

  final _searchController = TextEditingController();
  String _query = '';
  int _tab = 0;

  /// Null until the Saved tab is first opened (then loading).
  Future<void>? _savedLoad;
  List<BeaconSavedFact>? _saved;
  bool _savedFailed = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addFirstFact() {
    final onAddFact = widget.onAddFact;
    Navigator.of(context).pop();
    onAddFact?.call();
  }

  void _select(BeaconFactCard fact) {
    widget.cubit.setPendingQuotedFact(fact);
    Navigator.of(context).pop();
  }

  void _selectTab(int index) {
    _searchController.clear();
    setState(() {
      _tab = index;
      _query = '';
      if (index == _savedTab) _savedLoad ??= _loadSaved();
    });
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await GetIt.I<BeaconThreadsCase>().savedFacts();
      if (mounted) setState(() => _saved = saved);
    } on Object {
      if (mounted) setState(() => _savedFailed = true);
    }
  }

  /// A saved fact of this episode is quoted as it is; one from elsewhere is
  /// brought here first.
  Future<void> _pickSaved(BeaconSavedFact saved) async {
    for (final fact in activePinnedFacts(widget.cubit.state.factCards)) {
      if (fact.id == saved.factCardId) return _select(fact);
    }
    final l10n = L10n.of(context)!;
    try {
      await widget.cubit.quoteFactFromElsewhere(saved.factCardId);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e, st) {
      if (!mounted) return;
      if (e is BeaconFactCopySourceUnavailableException) {
        setState(() => _replaceSaved(saved, _unavailable(saved)));
      }
      showSnackBar(
        context,
        isError: true,
        text: factCopyFailureText(l10n, e),
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _unsave(BeaconSavedFact saved) async {
    try {
      await GetIt.I<BeaconThreadsCase>().unsaveFact(
        factCardId: saved.factCardId,
      );
      if (mounted) setState(() => _replaceSaved(saved, null));
    } on Object catch (e, st) {
      if (!mounted) return;
      showSnackBar(
        context,
        isError: true,
        text: L10n.of(context)!.errorGenericAction,
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Replaces [old] in the Saved list with [next], or drops it when null.
  void _replaceSaved(BeaconSavedFact old, BeaconSavedFact? next) => _saved = [
    for (final s in _saved ?? const <BeaconSavedFact>[])
      if (s.factCardId != old.factCardId) s else ?next,
  ];

  static BeaconSavedFact _unavailable(BeaconSavedFact s) => (
    factCardId: s.factCardId,
    available: false,
    beaconId: null,
    beaconKind: null,
    factText: null,
    attachmentsJson: null,
  );

  Widget _savedList(L10n l10n, String query) {
    final tt = context.tt;
    final saved = _saved;
    if (saved == null) {
      return _savedFailed
          ? Text(l10n.errorGenericAction)
          : const Center(child: TenturaCircularProgress());
    }
    if (saved.isEmpty) {
      return Text(
        l10n.beaconRoomFactPickerSavedEmpty,
        style: TenturaText.bodyMedium(tt.textMuted),
      );
    }
    final visible = query.isEmpty
        ? saved
        : saved
              .where(
                (s) => (s.factText ?? '').toLowerCase().contains(query),
              )
              .toList(growable: false);
    return ListView.separated(
      shrinkWrap: true,
      itemCount: visible.length,
      separatorBuilder: (_, _) => SizedBox(height: tt.rowGap / 2),
      itemBuilder: (_, index) {
        final s = visible[index];
        final text = s.factText;
        final available = s.available && text != null;
        return ListTile(
          leading: Icon(
            available ? Icons.bookmark : Icons.bookmark_border,
            size: tt.iconSize,
          ),
          title: Text(
            available ? text : l10n.beaconRoomFactPickerSavedUnavailable,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: available ? null : TenturaText.bodyMedium(tt.textMuted),
          ),
          // An unavailable row offers only removal (plan §6.3).
          trailing: available
              ? PopupMenuButton<void>(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (_) => [
                    PopupMenuItem<void>(
                      onTap: () => unawaited(_unsave(s)),
                      child: Text(l10n.beaconRoomFactPickerRemoveSaved),
                    ),
                  ],
                )
              : IconButton(
                  tooltip: l10n.beaconRoomFactPickerRemoveSaved,
                  icon: Icon(Icons.close, size: tt.iconSize),
                  onPressed: () => unawaited(_unsave(s)),
                ),
          onTap: available ? () => unawaited(_pickSaved(s)) : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final facts = activePinnedFacts(widget.cubit.state.factCards);
    // Picking a saved fact may copy it here: not in a read-only room.
    final hasSavedTab = widget.cubit.state.canWriteDiscussion;
    final onSavedTab = hasSavedTab && _tab == _savedTab;
    final showSearch =
        (onSavedTab ? _saved?.length ?? 0 : facts.length) >
        _kFactPickerSearchThreshold;
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? facts
        : facts
              .where((f) => f.factText.toLowerCase().contains(query))
              .toList(growable: false);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.tightGap * 2,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: Column(
            // Size to content (capped by maxHeight): an empty or short
            // list opened a near-full-screen sheet (UI review).
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A way out besides the scrim (#497).
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // With tabs, the first tab names the episode.
                      widget.isPost && !hasSavedTab
                          ? l10n.beaconRoomFactPickerTitlePost
                          : l10n.beaconRoomFactPickerTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.buttonClose,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close, size: tt.iconSize),
                  ),
                ],
              ),
              if (hasSavedTab)
                TenturaUnderlineTabs(
                  tabs: [
                    if (widget.isPost)
                      l10n.beaconRoomFactPickerTitlePost
                    else
                      l10n.beaconRoomFactPickerTabRequest,
                    l10n.beaconRoomFactPickerTabSaved,
                  ],
                  selectedIndex: _tab,
                  onChanged: _selectTab,
                ),
              SizedBox(height: tt.rowGap),
              if (showSearch) ...[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: MaterialLocalizations.of(
                      context,
                    ).searchFieldLabel,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                SizedBox(height: tt.rowGap),
              ],
              Flexible(
                child: onSavedTab
                    ? _savedList(l10n, query)
                    : facts.isEmpty
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.beaconFactsSheetEmpty,
                            style: TenturaText.bodyMedium(tt.textMuted),
                          ),
                          if (widget.onAddFact != null) ...[
                            SizedBox(height: tt.rowGap),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TenturaCommandButton(
                                label: l10n.beaconRoomFactPickerPinFirst,
                                onPressed: _addFirstFact,
                              ),
                            ),
                          ],
                        ],
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: tt.rowGap / 2),
                        itemBuilder: (_, index) {
                          final fact = visible[index];
                          final images = fact.attachments
                              .where((a) => a.isImage && a.imageId.isNotEmpty)
                              .toList();
                          final title = fact.factText.trim().isNotEmpty
                              ? fact.factText
                              : (images.isNotEmpty
                                    ? l10n.beaconRoomPinFactAttachmentBodyFallback
                                    : fact.factText);
                          return ListTile(
                            leading: images.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      TenturaRadii.cardDense,
                                    ),
                                    child: SizedBox(
                                      width: tt.avatarSize,
                                      height: tt.avatarSize,
                                      child: roomAttachmentAlbumThumbnail(
                                        context,
                                        images.first,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.fact_check_outlined,
                                    size: tt.iconSize,
                                  ),
                            title: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _select(fact),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
