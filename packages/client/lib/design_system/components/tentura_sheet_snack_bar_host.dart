import 'package:flutter/material.dart';

/// Keeps sheet feedback above the modal barrier without changing the sheet's
/// content-sized layout. The transparent scaffold fills the route; its body
/// retains the original sheet/dialog layout and outside-tap dismissal.
class TenturaSheetSnackBarHost extends StatefulWidget {
  const TenturaSheetSnackBarHost({
    required this.child,
    required this.isDismissible,
    this.ownerRoute,
    super.key,
  });

  final Widget child;
  final bool isDismissible;
  final ModalRoute<dynamic>? ownerRoute;

  static final _hosts = Expando<List<_TenturaSheetSnackBarHostState>>();

  /// Finds the current sheet opened from this route, including sheets on the
  /// root navigator. A popped sheet can remain mounted during its exit.
  static ScaffoldMessengerState? messengerFor(BuildContext context) {
    final owner = ModalRoute.of(context);
    final hosts = owner == null ? null : _hosts[owner];
    if (hosts == null) return null;
    for (final host in hosts.reversed) {
      final messenger = host._messengerKey.currentState;
      if (messenger != null && (host._route?.isCurrent ?? false)) {
        return messenger;
      }
    }
    return null;
  }

  @override
  State<TenturaSheetSnackBarHost> createState() =>
      _TenturaSheetSnackBarHostState();
}

class _TenturaSheetSnackBarHostState extends State<TenturaSheetSnackBarHost> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _register(widget.ownerRoute);
  }

  void _register(ModalRoute<dynamic>? owner) {
    if (owner == null) return;
    final hosts = TenturaSheetSnackBarHost._hosts;
    (hosts[owner] ??= []).add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(TenturaSheetSnackBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOwner = oldWidget.ownerRoute;
    if (oldOwner == widget.ownerRoute) return;
    _unregister(oldOwner);
    _register(widget.ownerRoute);
  }

  void _unregister(ModalRoute<dynamic>? owner) {
    if (owner != null) TenturaSheetSnackBarHost._hosts[owner]?.remove(this);
  }

  @override
  void dispose() {
    _unregister(widget.ownerRoute);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messengerKey,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.isDismissible
                ? () {
                    if (ModalRoute.of(context)?.isCurrent ?? false) {
                      Navigator.of(context).maybePop();
                    }
                  }
                : null,
            child: const SizedBox.expand(),
          ),
          widget.child,
        ],
      ),
    ),
  );
}
