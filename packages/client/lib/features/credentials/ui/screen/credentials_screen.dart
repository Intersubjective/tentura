import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/entity/credential_entity.dart';
import '../../domain/entity/credential_types.dart';
import '../bloc/credentials_cubit.dart';

@RoutePage()
class CredentialsScreen extends StatefulWidget implements AutoRouteWrapper {
  const CredentialsScreen({
    @QueryParam(kQueryCredentialLinked) this.linked,
    super.key,
  });

  final String? linked;

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
    create: (_) => GetIt.I<CredentialsCubit>(),
    child: this,
  );

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleLinkedQuery());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<CredentialsCubit>().fetch());
    }
  }

  void _handleLinkedQuery() {
    final linked = widget.linked?.trim();
    if (linked == null || linked.isEmpty || !mounted) return;
    final cubit = context.read<CredentialsCubit>();
    if (linked == 'conflict' || linked == 'error') {
      final l10n = L10n.of(context)!;
      showSnackBar(context, isError: true, text: l10n.credentialLinkConflict);
      return;
    }
    cubit.notifyLinkedFromRedirect(linked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.signInMethods),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(LinearPiActive.height),
          child: BlocSelector<CredentialsCubit, CredentialsState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
          ),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<CredentialsCubit, CredentialsState>(
          builder: (context, state) {
            final itemCount = _listItemCount(state);
            final maxW = tt.contentMaxWidth;
            final listView = RefreshIndicator.adaptive(
              onRefresh: () => context.read<CredentialsCubit>().fetch(),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.symmetric(vertical: tt.sectionGap),
                itemCount: itemCount,
                itemBuilder: (context, index) =>
                    _listItemAt(context, l10n, theme, state, index),
              ),
            );
            if (maxW == null) return listView;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: listView,
              ),
            );
          },
        ),
      ),
    );
  }

  int _listItemCount(CredentialsState state) {
    var count = 0;
    if (state.credentials.isEmpty && !state.isLoading) {
      count++;
    }
    count += state.credentials.length;
    if (state.showAddSection) {
      count++; // divider
      count++; // section header
      if (state.canAddGoogle) count++;
      if (state.canAddEmail) count++;
      if (state.canAddRecoverySeed) count++;
    }
    return count;
  }

  Widget _listItemAt(
    BuildContext context,
    L10n l10n,
    ThemeData theme,
    CredentialsState state,
    int index,
  ) {
    var i = index;
    if (state.credentials.isEmpty && !state.isLoading) {
      if (i == 0) {
        final tt = context.tt;
        return Padding(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Text(
            l10n.signInMethodsEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        );
      }
      i--;
    }
    if (i < state.credentials.length) {
      final credential = state.credentials[i];
      return ListTile(
        leading: Icon(_iconForType(credential.type)),
        title: Text(_typeLabel(l10n, credential.type)),
        subtitle: Text(
          _subtitle(context, l10n, credential),
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.buttonRemove,
          onPressed: state.isLoading
              ? null
              : () => _confirmRemove(context, l10n, credential),
        ),
      );
    }
    i -= state.credentials.length;
    if (!state.showAddSection) {
      return const SizedBox.shrink();
    }
    if (i == 0) {
      return const TenturaHairlineDivider();
    }
    if (i == 1) {
      final tt = context.tt;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: Text(
          l10n.addSignInMethod,
          style: theme.textTheme.titleSmall,
        ),
      );
    }
    i -= 2;
    if (state.canAddGoogle) {
      if (i == 0) {
        return ListTile(
          leading: const Icon(Icons.g_mobiledata),
          title: Text(l10n.credentialGoogle),
          enabled: !state.isLoading,
          onTap: state.isLoading ? null : () => _linkGoogle(context),
        );
      }
      i--;
    }
    if (state.canAddEmail) {
      if (i == 0) {
        return ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(l10n.credentialEmail),
          enabled: !state.isLoading,
          onTap: state.isLoading ? null : () => _linkEmail(context, l10n),
        );
      }
      i--;
    }
    if (state.canAddRecoverySeed && i == 0) {
      return ListTile(
        leading: const Icon(Icons.vpn_key_outlined),
        title: Text(l10n.credentialRecoverySeed),
        enabled: !state.isLoading,
        onTap: state.isLoading ? null : () => _linkSeed(context, l10n),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _linkGoogle(BuildContext context) async {
    final cubit = context.read<CredentialsCubit>();
    if (kIsWeb) {
      await cubit.linkGoogleWeb();
    } else {
      await cubit.linkGoogleNative();
    }
  }

  Future<void> _linkEmail(BuildContext context, L10n l10n) async {
    final controller = TextEditingController();
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final tt = sheetContext.tt;
        return Padding(
          padding: EdgeInsets.only(
            left: tt.screenHPadding,
            right: tt.screenHPadding,
            top: tt.sectionGap,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + tt.sectionGap,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.linkEmailTitle,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(hintText: l10n.linkEmailHint),
              ),
              SizedBox(height: tt.sectionGap),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(controller.text),
                child: Text(l10n.linkEmailSend),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (email == null || email.trim().isEmpty || !context.mounted) return;
    await context.read<CredentialsCubit>().startEmailLink(email);
  }

  Future<void> _linkSeed(BuildContext context, L10n l10n) async {
    final seed = await context.read<CredentialsCubit>().linkRecoverySeed();
    if (seed == null || !context.mounted) return;
    await ShowSeedDialog.show(context, seed: seed);
    if (!context.mounted) return;
    await TenturaConfirmDialog.show(
      context: context,
      title: l10n.seedBackupTitle,
      content: l10n.seedBackupBody,
      confirmLabel: l10n.seedBackupConfirm,
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    L10n l10n,
    CredentialEntity credential,
  ) async {
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.removeCredentialTitle,
      content: l10n.removeCredentialBody,
      confirmLabel: l10n.buttonRemove,
      cancelLabel: l10n.buttonCancel,
    );
    if ((confirmed ?? false) && context.mounted) {
      await context.read<CredentialsCubit>().remove(credential.id);
    }
  }

  IconData _iconForType(String type) => switch (type) {
    CredentialTypes.ed25519Device => Icons.vpn_key_outlined,
    CredentialTypes.oidcGoogle => Icons.g_mobiledata,
    CredentialTypes.emailOtp => Icons.mail_outline,
    _ => Icons.key_outlined,
  };

  String _typeLabel(L10n l10n, String type) => switch (type) {
    CredentialTypes.ed25519Device => l10n.credentialDeviceKey,
    CredentialTypes.oidcGoogle => l10n.credentialGoogle,
    CredentialTypes.emailOtp => l10n.credentialEmail,
    _ => type,
  };

  String _subtitle(BuildContext context, L10n l10n, CredentialEntity credential) {
    final identifier = credential.identifier.length > 16
        ? '${credential.identifier.substring(0, 16)}…'
        : credential.identifier;
    final created = credential.createdAt;
    if (created == null) return identifier;
    final now = DateTime.now();
    final relative = compactRelativeTimeAgo(when: created, now: now, l10n: l10n);
    if (now.difference(created).inDays < 7) {
      return '$identifier · $relative';
    }
    final locale = l10n.localeName;
    final formatted = DateFormat.yMMMd(locale).format(created.toLocal());
    return '$identifier · $formatted';
  }
}
