import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/domain/pinned_facts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Plan §7.3: search is shown only once the listed facts exceed this count.
const _kFactPickerSearchThreshold = 5;

/// Fact picker for the composer's attach-menu "Fact" item (plan §7.2 B).
///
/// Lists every live (non-removed) fact from the room's fact cards; tapping
/// one sets it as the room's pending quoted fact and closes.
Future<void> showFactPickerSheet(
  BuildContext context, {
  required RoomCubit cubit,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => FactPickerSheet(cubit: cubit),
  );
}

class FactPickerSheet extends StatefulWidget {
  const FactPickerSheet({required this.cubit, super.key});

  final RoomCubit cubit;

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.beaconRoomFactPickerTitle,
                style: Theme.of(context).textTheme.titleSmall,
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
              Expanded(
                child: facts.isEmpty
                    ? Text(
                        l10n.beaconFactsSheetEmpty,
                        style: TenturaText.bodyMedium(tt.textMuted),
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: tt.rowGap / 2),
                        itemBuilder: (_, index) {
                          final fact = visible[index];
                          return ListTile(
                            title: Text(
                              fact.factText,
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
