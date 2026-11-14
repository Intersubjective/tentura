import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/message/discussion_read_only_message.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// More destinations than this get a search field (plan §6.2).
const _kSearchThreshold = 5;

/// Server codes the copy flow words for the person (plan §6.2).
const _kUnauthorizedCode = '1102';
const _kReadOnlyCode = '1301';

/// «Use in another Request or Post»: the fact, who will see the copy, and
/// the Requests and Posts it can go into. A tap copies at once; the result is a snackbar
/// on [pageContext]'s page, and a failure leaves the sheet open.
Future<void> showFactCopyDestinationSheet(
  BuildContext pageContext, {
  required BeaconFactCard fact,
}) => showTenturaAdaptiveSheet<void>(
  context: pageContext,
  useRootNavigator: true,
  builder: (_) => SafeArea(
    child: _FactCopyDestinationSheet(pageContext: pageContext, fact: fact),
  ),
);

class _FactCopyDestinationSheet extends StatefulWidget {
  const _FactCopyDestinationSheet({
    required this.pageContext,
    required this.fact,
  });

  final BuildContext pageContext;
  final BeaconFactCard fact;

  @override
  State<_FactCopyDestinationSheet> createState() =>
      _FactCopyDestinationSheetState();
}

class _FactCopyDestinationSheetState extends State<_FactCopyDestinationSheet> {
  late final Future<List<BeaconFactCopyDestination>> _destinations =
      GetIt.I<BeaconThreadsCase>().factCopyDestinations(
        sourceFactCardId: widget.fact.id,
      );

  String _query = '';

  Future<void> _copyTo(BeaconFactCopyDestination destination) async {
    final page = widget.pageContext;
    final l10n = L10n.of(page)!;
    try {
      final result = await GetIt.I<BeaconThreadsCase>().copyFact(
        sourceFactCardId: widget.fact.id,
        destinationBeaconId: destination.id,
      );
      if (!page.mounted) return;
      // The sheet would cover the snackbar and its «Open» action.
      if (mounted) Navigator.of(context).pop();
      showSnackBar(
        page,
        text: switch (result.outcome) {
          BeaconFactCopyOutcome.created => l10n.beaconFactCopyCopiedTo(
            destination.title,
          ),
          BeaconFactCopyOutcome.alreadyThere => l10n.beaconFactCopyAlreadyThere,
        },
        action: SnackBarAction(
          label: l10n.beaconRoomFactHistoryOpenOrigin,
          onPressed: () {
            if (!page.mounted) return;
            unawaited(
              page.router.root.navigatePath(
                '$kPathBeaconView/${destination.id}',
              ),
            );
          },
        ),
      );
    } on Object catch (e, st) {
      if (!page.mounted) return;
      showSnackBar(
        page,
        isError: true,
        text: _failureText(l10n, e),
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final padding = EdgeInsets.symmetric(horizontal: context.tt.screenHPadding);
    return FutureBuilder<List<BeaconFactCopyDestination>>(
      future: _destinations,
      builder: (context, snapshot) {
        final all = snapshot.data;
        final shown = all
            ?.where(
              (d) => d.title.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: padding.copyWith(top: context.tt.rowGap),
              child: Text(
                l10n.beaconRoomFactCardActionUseElsewhere,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: padding.copyWith(top: context.tt.rowGap / 2),
              child: Text(
                widget.fact.factText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: padding.copyWith(
                top: context.tt.rowGap / 2,
                bottom: context.tt.rowGap,
              ),
              child: Text(
                l10n.beaconFactCopyNote,
                style: TenturaText.status(theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (all != null && all.length > _kSearchThreshold)
              Padding(
                padding: padding.copyWith(bottom: context.tt.rowGap / 2),
                child: TextField(
                  decoration: tenturaFormFieldDecoration(
                    context,
                    hintText: l10n.beaconFactCopySearchHint,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            if (all != null && all.isEmpty)
              Padding(
                padding: padding.copyWith(bottom: context.tt.rowGap),
                child: Text(l10n.beaconFactCopyEmpty),
              )
            else if (shown != null)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in shown)
                      ListTile(
                        title: Text(
                          d.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Only a Post has a lifetime (plan §6.2).
                        subtitle: switch (d.expiresAt) {
                          final at? when d.kind == BeaconKind.post.value =>
                            Text(
                              postRemainingLabel(
                                l10n,
                                at.difference(DateTime.now()),
                              ),
                            ),
                          _ => null,
                        },
                        onTap: () => unawaited(_copyTo(d)),
                      ),
                  ],
                ),
              )
            else if (snapshot.hasError)
              Padding(
                padding: padding.copyWith(bottom: context.tt.rowGap),
                child: Text(l10n.errorGenericAction),
              )
            else
              Padding(
                padding: EdgeInsets.all(context.tt.screenHPadding),
                child: const Center(child: TenturaCircularProgress()),
              ),
          ],
        );
      },
    );
  }
}

/// The person-facing words for a failed copy (plan §6.2).
String _failureText(L10n l10n, Object error) => switch (error) {
  BeaconFactCopySourceUnavailableException() => l10n.beaconFactCopyUnavailable,
  RemoteApiException(code: _kUnauthorizedCode) => l10n.beaconFactCopyNotAllowed,
  RemoteApiException(code: _kReadOnlyCode) =>
    const DiscussionReadOnlyMessage().toL10n(l10n.localeName),
  BeaconFactRateLimitedException() => l10n.planErrorRateLimited,
  final Localizable e => e.toL10n(l10n.localeName),
  _ => l10n.errorGenericAction,
};
