import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/evaluation/ui/bloc/received_reviews_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/received_review_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

@RoutePage()
class ReceivedReviewsScreen extends StatelessWidget implements AutoRouteWrapper {
  const ReceivedReviewsScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => ReceivedReviewsCubit.fromGetIt(beaconId: id),
    child: this,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<ReceivedReviewsCubit>();

    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        leading: const AutoLeadingButton(),
        title: BlocSelector<ReceivedReviewsCubit, ReceivedReviewsState, String?>(
          bloc: cubit,
          selector: (state) => state.data?.beaconTitle,
          builder: (context, beaconTitle) {
            final title = beaconTitle == null || beaconTitle.isEmpty
                ? l10n.evaluationReceivedScreenTitleGeneric
                : l10n.evaluationReceivedScreenTitle(beaconTitle);
            return Text(title);
          },
        ),
        progress: BlocSelector<ReceivedReviewsCubit, ReceivedReviewsState, bool>(
          bloc: cubit,
          selector: (state) => state.isLoading,
          builder: TenturaTopBar.loadingBar,
        ),
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: const ReceivedReviewsView(),
        ),
      ),
    );
  }
}

/// Body of [ReceivedReviewsScreen] — extracted for widget tests (no AutoRouter).
class ReceivedReviewsView extends StatelessWidget {
  const ReceivedReviewsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ReceivedReviewsCubit>();

    return BlocBuilder<ReceivedReviewsCubit, ReceivedReviewsState>(
      builder: (context, state) {
        if (state.isLoading && state.data == null) {
          return const Center(
            child: CircularProgressIndicator.adaptive(),
          );
        }
        if (state.hasError && state.data == null) {
          return Center(
            child: Padding(
              padding: tt.cardPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: tt.iconSize * 2,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  SizedBox(height: tt.sectionGap),
                  FilledButton(
                    onPressed: () => unawaited(cubit.fetch()),
                    child: Text(l10n.myWorkRetry),
                  ),
                ],
              ),
            ),
          );
        }

        final data = state.data;
        if (data == null) {
          return const SizedBox.shrink();
        }

        if (!data.windowClosed) {
          return _ReceivedReviewsMessage(
            icon: Icons.schedule_outlined,
            message: l10n.evaluationReceivedEmptyWindowOpen,
            actionLabel: l10n.evaluationReceivedSeeReviewWindowStatus,
            onAction: () => Navigator.of(context).maybePop(),
          );
        }

        if (data.rows.isEmpty) {
          return _ReceivedReviewsMessage(
            icon: Icons.chat_bubble_outline,
            message: l10n.evaluationReceivedEmptyNoReviews,
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return ListView.builder(
              padding: tt.cardPadding,
              itemCount: data.rows.length,
              itemBuilder: (context, index) {
                final row = data.rows[index];
                return ReceivedReviewTile(
                  row: row,
                  showDivider: index < data.rows.length - 1,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ReceivedReviewsMessage extends StatelessWidget {
  const _ReceivedReviewsMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Center(
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: tt.iconSize * 2,
              color: tt.textMuted,
            ),
            SizedBox(height: tt.sectionGap),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TenturaText.body(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: tt.sectionGap),
              TenturaTextAction(
                label: actionLabel!,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
