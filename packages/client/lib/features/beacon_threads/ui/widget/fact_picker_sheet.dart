import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Plan §7.3: search is shown only once the listed facts exceed this count.
const _kFactPickerSearchThreshold = 5;

/// Fact picker for the composer's attach-menu "Fact" item (plan §7.2 B).
///
/// Lists every live (non-removed) fact from the room's fact cards; tapping
/// one sets it as the room's pending quoted fact and closes.
///
/// [onAddFact] opens the host's Add-fact form; when given, an empty picker
/// offers "Pin your first fact" instead of a dead end (#481).
Future<void> showFactPickerSheet(
  BuildContext context, {
  required RoomCubit cubit,
  VoidCallback? onAddFact,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => FactPickerSheet(cubit: cubit, onAddFact: onAddFact),
  );
}

class FactPickerSheet extends StatefulWidget {
  const FactPickerSheet({required this.cubit, this.onAddFact, super.key});

  final RoomCubit cubit;

  /// Closes the picker first, then is called once (#481).
  final VoidCallback? onAddFact;

  @override
  State<FactPickerSheet> createState() => _FactPickerSheetState();
}

class _FactPickerSheetState extends State<FactPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final facts = activePinnedFacts(widget.cubit.state.factCards);
    final showSearch = facts.length > _kFactPickerSearchThreshold;
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
                      l10n.beaconRoomFactPickerTitle,
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
                child: facts.isEmpty
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
