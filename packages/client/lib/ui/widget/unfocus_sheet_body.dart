import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Wraps modal sheet content and clears primary focus after the first paint.
///
/// Web/desktop often land focus on the first `FilterChip` when a sheet opens,
/// which looks like a faint selected state even when the chip is not selected.
class UnfocusSheetBody extends StatefulWidget {
  const UnfocusSheetBody({required this.child, super.key});

  final Widget child;

  @override
  State<UnfocusSheetBody> createState() => _UnfocusSheetBodyState();
}

class _UnfocusSheetBodyState extends State<UnfocusSheetBody> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
