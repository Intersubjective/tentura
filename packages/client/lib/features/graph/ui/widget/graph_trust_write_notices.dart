import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/lazy_write_timeout_notice.dart';

import '../../domain/use_case/graph_trust_write_case.dart';
import '../bloc/graph_person_context_cubit.dart';

/// Shared trust feedback for both graph presentations.
class GraphTrustWriteNotices extends StatelessWidget {
  const GraphTrustWriteNotices({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GraphPersonContextCubit>();
    return LazyWriteTimeoutNotice(
      notices: cubit.lazyWriteNotices,
      child: BlocListener<GraphPersonContextCubit, GraphPersonContextState>(
        listenWhen: (previous, current) =>
            previous.trustError != current.trustError &&
            current.trustError != null,
        listener: (context, state) {
          final error = state.trustError;
          if (error is! GraphTrustRevert) return;
          final l10n = L10n.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.graphTrustNotSaved),
              // Not blocking: auto-dismiss despite the action (#470).
              persist: false,
              action: SnackBarAction(
                label: l10n.graphTrustRetry,
                onPressed: () => unawaited(cubit.retryTrust(error)),
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }
}
