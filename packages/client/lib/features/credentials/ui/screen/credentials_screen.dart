import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/dialog/show_seed_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/credential_entity.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInMethods)),
      body: BlocConsumer<CredentialsCubit, CredentialsState>(
        listener: commonScreenBlocListener,
        builder: (context, state) {
          return ListView(
            padding: kPaddingV,
            children: [
              if (state.credentials.isEmpty && !state.isLoading)
                Padding(
                  padding: kPaddingAll,
                  child: Text(
                    l10n.signInMethodsEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ...state.credentials.map(
                (credential) => ListTile(
                  leading: Icon(_iconForType(credential.type)),
                  title: Text(_typeLabel(l10n, credential.type)),
                  subtitle: Text(
                    _subtitle(credential),
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.buttonRemove,
                    onPressed: state.isLoading
                        ? null
                        : () => _confirmRemove(context, l10n, credential),
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: kPaddingH,
                child: Text(
                  l10n.addSignInMethod,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.g_mobiledata),
                title: Text(l10n.credentialGoogle),
                enabled: !state.isLoading,
                onTap: state.isLoading ? null : () => _linkGoogle(context),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(l10n.credentialEmail),
                enabled: !state.isLoading,
                onTap: state.isLoading ? null : () => _linkEmail(context, l10n),
              ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(l10n.credentialRecoverySeed),
                enabled: !state.isLoading,
                onTap: state.isLoading ? null : () => _linkSeed(context, l10n),
              ),
            ],
          );
        },
      ),
    );
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
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: kSpacingMedium,
          right: kSpacingMedium,
          top: kSpacingMedium,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + kSpacingMedium,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.linkEmailTitle, style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: kSpacingSmall),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(hintText: l10n.linkEmailHint),
            ),
            const SizedBox(height: kSpacingMedium),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(controller.text),
              child: Text(l10n.linkEmailSend),
            ),
          ],
        ),
      ),
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
    await showAdaptiveDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(l10n.seedBackupTitle),
        content: Text(
          l10n.seedBackupBody,
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.seedBackupConfirm),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    L10n l10n,
    CredentialEntity credential,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeCredentialTitle),
        content: Text(l10n.removeCredentialBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.buttonRemove),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await context.read<CredentialsCubit>().remove(credential.id);
    }
  }

  IconData _iconForType(String type) => switch (type) {
    'ed25519_device' => Icons.vpn_key_outlined,
    'oidc:google' => Icons.g_mobiledata,
    'email_otp' => Icons.mail_outline,
    _ => Icons.key_outlined,
  };

  String _typeLabel(L10n l10n, String type) => switch (type) {
    'ed25519_device' => l10n.credentialDeviceKey,
    'oidc:google' => l10n.credentialGoogle,
    'email_otp' => l10n.credentialEmail,
    _ => type,
  };

  String _subtitle(CredentialEntity credential) {
    final identifier = credential.identifier.length > 16
        ? '${credential.identifier.substring(0, 16)}…'
        : credential.identifier;
    final created = credential.createdAt;
    return created == null
        ? identifier
        : '$identifier · ${created.toLocal().toString().split(' ').first}';
  }
}
