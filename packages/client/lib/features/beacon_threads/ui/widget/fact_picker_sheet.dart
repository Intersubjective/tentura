import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/fact_picker_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_copy_destination_sheet.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/domain/util/beacon_pinned_facts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Fact picker for the composer's attach-menu "Fact" item (quote mode,
/// plan #1288 P10, P11).
///
/// Scopes «In this Request» / «In this Post», «Saved» and «All my facts»,
/// with an always-visible search. A fact of this episode is quoted; one from
/// elsewhere is copied here, then quoted. A read-only room offers only its
/// own facts (copy is impossible there).
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

/// The Facts lists' «Pick from available» (bring mode, plan #1288 P10,
/// P11): scopes «Saved» and «All my facts»; a tap copies the fact into
/// [beaconId], awaits [onBrought], closes and says «Fact added» (or
/// «Already there»). [isPost] is accepted for the hosts' symmetry; the bring
/// sheet names no episode.
Future<void> showFactPickFromAvailableSheet(
  BuildContext context, {
  required String beaconId,
  required bool isPost,
  required Future<void> Function() onBrought,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) =>
        FactPickerSheet.bring(beaconId: beaconId, onBrought: onBrought),
  );
}

typedef _Bring = ({String beaconId, Future<void> Function() onBrought});

class FactPickerSheet extends StatefulWidget {
  /// Quote mode over the room's [cubit].
  const FactPickerSheet({
    required RoomCubit this.cubit,
    this.onAddFact,
    this.isPost = false,
    super.key,
  }) : _bring = null;

  /// Bring mode: copies the picked fact into [beaconId].
  const FactPickerSheet.bring({
    required String beaconId,
    required Future<void> Function() onBrought,
    super.key,
  }) : cubit = null,
       onAddFact = null,
       isPost = false,
       _bring = (beaconId: beaconId, onBrought: onBrought);

  /// Set in quote mode only.
  final RoomCubit? cubit;

  /// Set in bring mode only.
  final _Bring? _bring;

  /// Lists a Post's own facts, headed «In this Post» (plan D5).
  final bool isPost;

  /// Closes the picker first, then is called once (#481).
  final VoidCallback? onAddFact;

  @override
  State<FactPickerSheet> createState() => _FactPickerSheetState();
}

class _FactPickerSheetState extends State<FactPickerSheet> {
  final _searchController = TextEditingController();

  late final FactPickerCubit _picker;

  /// This episode had no facts when the picker opened (#481 hand-off).
  late final bool _hereEmpty;

  @override
  void initState() {
    super.initState();
    final room = widget.cubit;
    _hereEmpty =
        room == null || activePinnedFacts(room.state.factCards).isEmpty;
    _picker =
        room?.factPicker() ??
        FactPickerCubit(
          threadsCase: GetIt.I<BeaconThreadsCase>(),
          destinationBeaconId: widget._bring!.beaconId,
          mode: FactPickerMode.bring,
        );
    unawaited(_picker.start());
  }

  @override
  void dispose() {
    _searchController.dispose();
    unawaited(_picker.close());
    super.dispose();
  }

  void _addFirstFact() {
    final onAddFact = widget.onAddFact;
    Navigator.of(context).pop();
    onAddFact?.call();
  }

  void _quote(RoomCubit room, BeaconFactCard fact) {
    room.setPendingQuotedFact(fact);
    Navigator.of(context).pop();
  }

  /// A saved fact or search hit: quoted in place when it is this episode's
  /// own (quote mode), otherwise copied here.
  Future<void> _pick(String factCardId) async {
    final room = widget.cubit;
    if (room != null) {
      for (final fact in activePinnedFacts(room.state.factCards)) {
        if (fact.id == factCardId) return _quote(room, fact);
      }
    }
    final l10n = L10n.of(context)!;
    try {
      if (room != null) {
        await room.quoteFactFromElsewhere(factCardId);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final bring = widget._bring!;
      final result = await _picker.bring(factCardId);
      final error = result.error;
      if (error != null) {
        Error.throwWithStackTrace(error, StackTrace.current);
      }
      await bring.onBrought();
      if (!mounted) return;
      showSnackBar(
        context,
        text: result.copyOutcome == BeaconFactCopyOutcome.alreadyThere
            ? l10n.beaconFactCopyAlreadyThere
            : l10n.factPickerFactAdded,
      );
      Navigator.of(context).pop();
    } on Object catch (e, st) {
      if (e is BeaconFactCopySourceUnavailableException) {
        _picker.markUnavailable(factCardId);
      }
      if (!mounted) return;
      showSnackBar(
        context,
        isError: true,
        text: factCopyFailureText(l10n, e),
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _unsave(String factCardId) async {
    try {
      await _picker.unsave(factCardId);
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

  String _scopeLabel(L10n l10n, FactPickerScope scope) => switch (scope) {
    FactPickerScope.here =>
      widget.isPost
          ? l10n.beaconRoomFactPickerTitlePost
          : l10n.beaconRoomFactPickerTabRequest,
    FactPickerScope.saved => l10n.beaconRoomFactPickerTabSaved,
    FactPickerScope.all => l10n.factPickerTabAll,
  };

  /// The one row of every scope: thumbnail or fact icon, ★ when saved,
  /// «No longer available» with removal when the fact cannot be copied.
  Widget _row(
    L10n l10n, {
    required String factCardId,
    required String? text,
    required List<RoomMessageAttachment> attachments,
    required bool saved,
    required bool available,
    required VoidCallback onTap,
    bool savedMenu = false,
  }) {
    final tt = context.tt;
    if (!available || text == null) {
      return ListTile(
        leading: Icon(Icons.fact_check_outlined, size: tt.iconSize),
        title: Text(
          l10n.beaconRoomFactPickerSavedUnavailable,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.bodyMedium(tt.textMuted),
        ),
        // An unavailable row offers only removal (plan §6.3).
        trailing: saved
            ? IconButton(
                tooltip: l10n.beaconRoomFactPickerRemoveSaved,
                icon: Icon(Icons.close, size: tt.iconSize),
                onPressed: () => unawaited(_unsave(factCardId)),
              )
            : null,
      );
    }
    final images = attachments
        .where((a) => a.isImage && a.imageId.isNotEmpty)
        .toList();
    final title = text.trim().isEmpty && images.isNotEmpty
        ? l10n.beaconRoomPinFactAttachmentBodyFallback
        : text;
    return ListTile(
      leading: images.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
              child: SizedBox(
                width: tt.avatarSize,
                height: tt.avatarSize,
                child: roomAttachmentAlbumThumbnail(context, images.first),
              ),
            )
          : Icon(Icons.fact_check_outlined, size: tt.iconSize),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: saved || savedMenu
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (saved)
                  Icon(
                    Icons.star,
                    size: tt.iconSize,
                    semanticLabel: l10n.beaconRoomFactPickerTabSaved,
                  ),
                if (savedMenu)
                  PopupMenuButton<void>(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (_) => [
                      PopupMenuItem<void>(
                        onTap: () => unawaited(_unsave(factCardId)),
                        child: Text(l10n.beaconRoomFactPickerRemoveSaved),
                      ),
                    ],
                  ),
              ],
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _list(List<Widget> rows) => ListView.separated(
    shrinkWrap: true,
    itemCount: rows.length,
    separatorBuilder: (_, _) => SizedBox(height: context.tt.rowGap / 2),
    itemBuilder: (_, index) => rows[index],
  );

  Widget _muted(String text) =>
      Text(text, style: TenturaText.bodyMedium(context.tt.textMuted));

  Widget _hereBody(L10n l10n, FactPickerState state) {
    final room = widget.cubit!;
    if (_hereEmpty) {
      final tt = context.tt;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _muted(l10n.beaconFactsSheetEmpty),
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
      );
    }
    return _list([
      for (final fact in state.hereRows)
        _row(
          l10n,
          factCardId: fact.id,
          text: fact.factText,
          attachments: fact.attachments,
          saved: state.savedIds.contains(fact.id),
          available: true,
          onTap: () => _quote(room, fact),
        ),
    ]);
  }

  Widget _savedBody(L10n l10n, FactPickerState state) {
    if (state.savedFailed) return Text(l10n.errorGenericAction);
    if (state.savedIds.isEmpty) {
      return _muted(l10n.beaconRoomFactPickerSavedEmpty);
    }
    return _list([
      for (final s in state.savedRows)
        _row(
          l10n,
          factCardId: s.factCardId,
          text: s.factText,
          attachments: parseRoomMessageAttachmentsJson(s.attachmentsJson ?? ''),
          saved: true,
          savedMenu: true,
          available:
              s.available && !state.unavailableIds.contains(s.factCardId),
          onTap: () => unawaited(_pick(s.factCardId)),
        ),
    ]);
  }

  Widget _allBody(L10n l10n, FactPickerState state) {
    if (state.showHint) return _muted(l10n.factPickerTypeMore);
    if (state.failed) return Text(l10n.errorGenericAction);
    if (state.results.isEmpty) {
      return state.searched
          ? _muted(l10n.capabilitySearchEmpty)
          : const Center(child: TenturaCircularProgress());
    }
    return _list([
      for (final hit in state.results)
        _row(
          l10n,
          factCardId: hit.factCardId,
          text: hit.factText,
          attachments: parseRoomMessageAttachmentsJson(hit.attachmentsJson),
          saved: hit.saved || state.savedIds.contains(hit.factCardId),
          available: !state.unavailableIds.contains(hit.factCardId),
          onTap: () => unawaited(_pick(hit.factCardId)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

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
          child: BlocBuilder<FactPickerCubit, FactPickerState>(
            bloc: _picker,
            builder: (context, state) {
              final scopes = state.scopes;
              return Column(
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
                          widget.cubit == null
                              ? l10n.factPickerTitleBring
                              // A single scope is named by the title.
                              : scopes.length == 1
                              ? _scopeLabel(l10n, scopes.single)
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
                  if (scopes.length > 1)
                    TenturaUnderlineTabs(
                      tabs: [for (final s in scopes) _scopeLabel(l10n, s)],
                      selectedIndex: scopes.indexOf(state.scope),
                      onChanged: (i) => unawaited(_picker.setScope(scopes[i])),
                    ),
                  SizedBox(height: tt.rowGap),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.factPickerSearchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: _picker.setQuery,
                  ),
                  SizedBox(height: tt.rowGap),
                  Flexible(
                    child: switch (state.scope) {
                      FactPickerScope.here => _hereBody(l10n, state),
                      FactPickerScope.saved => _savedBody(l10n, state),
                      FactPickerScope.all => _allBody(l10n, state),
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
