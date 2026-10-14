import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/closure_author_cubit.dart';
import '../bloc/closure_helper_cubit.dart';
import 'closure_author_screen.dart';
import 'closure_helper_screen.dart';

/// Opens the wrap-up review of a Request in "Wrapping up": the author's
/// «Sum up» (outcomes, split, Close now / Extend / Return to work) or a
/// member's view (support colleagues, marks). Completes when the page closes.
Future<void> openClosureReview(
  StackRouter router, {
  required String beaconId,
  required ClosureRole role,
  required String viewerId,
  required ClosureMember author,
}) => router.pushWidget<void>(
  ClosureReviewPage(
    beaconId: beaconId,
    role: role,
    viewerId: viewerId,
    author: author,
  ),
);

/// Page host for [ClosureAuthorView] / [ClosureHelperView] (B028).
class ClosureReviewPage extends StatelessWidget {
  const ClosureReviewPage({
    required this.beaconId,
    required this.role,
    required this.viewerId,
    required this.author,
    this.authorCubit,
    this.helperCubit,
    super.key,
  });

  final String beaconId;
  final ClosureRole role;
  final String viewerId;
  final ClosureMember author;

  /// Test seams; default to cubits built from DI.
  final ClosureAuthorCubit? authorCubit;
  final ClosureHelperCubit? helperCubit;

  bool get _isAuthor => role == ClosureRole.author;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        title: Text(
          _isAuthor ? l10n.closureAuthorTitle : l10n.closureHelperTitle,
        ),
      ),
      body: _isAuthor
          ? _provide<ClosureAuthorCubit>(
              value: authorCubit,
              create: () => ClosureAuthorCubit.fromGetIt(beaconId: beaconId),
              child: BlocListener<ClosureAuthorCubit, ClosureAuthorState>(
                // Close now finalizes the epoch; Return to work cancels it
                // (the state then reads as not found). Either way the review
                // is over: go back to the Request, which reloads.
                listenWhen: (p, c) =>
                    p.data != null &&
                    (c.data?.status != p.data?.status ||
                        (p.loadError == null && c.loadError != null)),
                listener: (context, _) => Navigator.of(context).maybePop(),
                child: const ClosureAuthorView(),
              ),
            )
          : _provide<ClosureHelperCubit>(
              value: helperCubit,
              create: () => ClosureHelperCubit.fromGetIt(
                beaconId: beaconId,
                viewerId: viewerId,
                author: author,
              ),
              child: const ClosureHelperView(),
            ),
    );
  }

  /// The page owns (and closes) a cubit it creates, not one handed in.
  static Widget _provide<T extends StateStreamableSource<Object?>>({
    required T? value,
    required T Function() create,
    required Widget child,
  }) => value == null
      ? BlocProvider<T>(create: (_) => create(), child: child)
      : BlocProvider<T>.value(value: value, child: child);
}
