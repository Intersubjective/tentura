import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/home_activation_cubit.dart';

/// Binds [HomeActivationCubit] to the raw auth account id from [HomeScreen].
class HomeActivationBinder extends StatefulWidget {
  const HomeActivationBinder({
    required this.accountId,
    required this.child,
    super.key,
  });

  final String accountId;
  final Widget child;

  @override
  State<HomeActivationBinder> createState() => _HomeActivationBinderState();
}

class _HomeActivationBinderState extends State<HomeActivationBinder> {
  @override
  void initState() {
    super.initState();
    unawaited(
      context.read<HomeActivationCubit>().bindAccount(widget.accountId),
    );
  }

  @override
  void didUpdateWidget(HomeActivationBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accountId != oldWidget.accountId) {
      unawaited(
        context.read<HomeActivationCubit>().bindAccount(widget.accountId),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
