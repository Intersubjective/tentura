import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/updates_feed_cubit.dart';
import '../widget/updates_feed_pane.dart';

@RoutePage()
/// Standalone Updates route (legacy deep links redirect into Inbox receipts).
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => UpdatesFeedCubit(),
      child: Scaffold(
        backgroundColor: context.tt.bg,
        body: const SafeArea(
          child: UpdatesFeedPane(showTitleRow: true),
        ),
      ),
    );
  }
}
