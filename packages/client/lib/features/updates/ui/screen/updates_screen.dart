import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

@RoutePage()
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Scaffold(
      appBar: AppBar(
        actions: [
          Tooltip(
            message: l10n.markAllAsRead,
            child: TenturaTextAction(
              label: l10n.markAllAsRead,
              onPressed: () => showSnackBar(
                context,
                isFloating: true,
                text: l10n.notImplementedYet,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        minimum: kPaddingSmallH,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: Text(
              l10n.labelNothingHere,
              style: Theme.of(context).textTheme.displaySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
