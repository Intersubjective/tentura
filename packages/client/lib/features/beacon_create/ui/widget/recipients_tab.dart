import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Recipients tab on beacon create — routing banner + embedded forward picker.
class BeaconRecipientsTab extends StatelessWidget {
  const BeaconRecipientsTab({
    required this.beaconId,
    required this.onSendRequest,
    super.key,
  });

  final String beaconId;
  final VoidCallback onSendRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(tt.cardPadding.top),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.send_outlined,
                  size: tt.iconSize,
                  color: scheme.onSurfaceVariant,
                ),
                SizedBox(width: tt.tightGap * 2),
                Expanded(
                  child: Text(
                    l10n.beaconRoutingBanner,
                    style: TenturaText.body(scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: tt.rowGap),
        BlocSelector<ForwardCubit, ForwardState, (Set<String>, String?)>(
          selector: (state) {
            final dropped = state.droppedPreselectedIds;
            if (dropped.isEmpty) return (const <String>{}, null);
            final id = dropped.first;
            final byId = {
              for (final c in [...state.candidates, ...state.lineageSuggestions])
                c.id: c,
            };
            return (dropped, byId[id]?.profile.shownName);
          },
          builder: (context, rec) {
            final (droppedIds, droppedName) = rec;
            if (droppedIds.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(bottom: tt.rowGap),
              child: Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(tt.cardRadius),
                child: Padding(
                  padding: EdgeInsets.all(tt.cardPadding.top),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: tt.iconSize,
                        color: scheme.onSurfaceVariant,
                      ),
                      SizedBox(width: tt.tightGap * 2),
                      Expanded(
                        child: Text(
                          l10n.beaconRecipientsPreselectDropped(
                            droppedName ?? droppedIds.first,
                          ),
                          style: TenturaText.bodySmall(
                            scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(
          child: BlocSelector<
            BeaconCreateCubit,
            BeaconCreateState,
            ({bool canTryToPublish, bool isLoading})
          >(
            selector: (s) => (
              canTryToPublish: s.canTryToPublish,
              isLoading: s.isLoading,
            ),
            builder: (context, createState) {
              return BlocSelector<ForwardCubit, ForwardState, bool>(
                selector: (s) => s.selectedIds.isNotEmpty,
                builder: (context, hasRecipients) {
                  final sendEnabled =
                      createState.canTryToPublish &&
                      hasRecipients &&
                      !createState.isLoading;
                  return ForwardRecipientPicker(
                    key: ValueKey(beaconId),
                    beaconId: beaconId,
                    embedded: true,
                    onSendPressed: onSendRequest,
                    sendEnabled: sendEnabled,
                    externalActionLoading: createState.isLoading,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Recipients tab placeholder shown until required fields are filled.
///
/// Important: this is intentionally non-interactive so actions like
/// “invite new person” cannot be used before a draft exists.
class BeaconRecipientsBlockedTab extends StatelessWidget {
  const BeaconRecipientsBlockedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(tt.cardPadding.top),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: tt.iconSize,
                  color: scheme.onErrorContainer,
                ),
                SizedBox(width: tt.tightGap * 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.beaconRecipientsBlockedBannerTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: tt.tightGap),
                      Text(
                        l10n.beaconRecipientsBlockedBannerBody,
                        style: TenturaText.bodySmall(scheme.onErrorContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: tt.rowGap),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Text(
                l10n.beaconRecipientsBlockedBannerBody,
                textAlign: TextAlign.center,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
