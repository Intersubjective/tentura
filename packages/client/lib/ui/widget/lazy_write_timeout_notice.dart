import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shows a non-blocking snackbar whenever [notices] emits; never takes part
/// in the gestures of [child].
class LazyWriteTimeoutNotice extends StatefulWidget {
  const LazyWriteTimeoutNotice({
    required this.notices,
    required this.child,
    super.key,
  });

  final Stream<LazyWriteNotice> notices;
  final Widget child;

  @override
  State<LazyWriteTimeoutNotice> createState() => _LazyWriteTimeoutNoticeState();
}

class _LazyWriteTimeoutNoticeState extends State<LazyWriteTimeoutNotice> {
  StreamSubscription<LazyWriteNotice>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(LazyWriteTimeoutNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notices != widget.notices) {
      unawaited(_subscription?.cancel());
      _subscribe();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.notices.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context)!.lazyWriteAckOverdue),
          showCloseIcon: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
