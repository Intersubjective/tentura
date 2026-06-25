import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> confirmAndSignOut(BuildContext context) async {
  final l10n = L10n.of(context)!;
  final confirmed = await TenturaConfirmDialog.show(
    context: context,
    title: l10n.logoutConfirmTitle,
    content: l10n.logoutConfirmBody,
    confirmLabel: l10n.logout,
    cancelLabel: l10n.buttonCancel,
  );
  if (confirmed == true) {
    await GetIt.I<AuthCubit>().signOut();
  }
}
