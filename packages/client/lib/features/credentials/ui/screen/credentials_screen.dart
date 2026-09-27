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

import '../../domain/entity/credential_entity.dart';
import '../../domain/entity/credential_types.dart';
import '../bloc/credentials_cubit.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';

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
    return HomeRailFrame(
      selectedTab: HomeTab.me,
      child: Scaffold(
        appBar: TenturaTopBar.of(
          context,
          leading: const AutoLeadingButton(),
          title: Text(l10n.signInMethods),
          progress: BlocSelector<CredentialsCubit, CredentialsState, bool>(
            selector: (state) => state.isLoading,
            builder: TenturaTopBar.loadingBar,
          ),
        ),
        body: SafeArea(
          child: BlocBuilder<CredentialsCubit, CredentialsState>(
            builder: (context, state) {
              return TenturaContentColumn(
                child: RefreshIndicator.adaptive(
                  onRefresh: () => context.read<CredentialsCubit>().fetch(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      tt.screenHPadding,
                      tt.rowGap,
                      tt.screenHPadding,
                      tt.sectionGap,
                    ),
                    children: _sections(context, l10n, theme, state),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Existing methods, then the ones that can be added — each a titled
  /// group on the menu keyline, so "Add sign-in method" no longer reads as
  /// one more existing method.
  List<Widget> _sections(
    BuildContext context,
    L10n l10n,
    ThemeData theme,
    CredentialsState state,
  ) {
    final tt = context.tt;
    final onlyOne = state.credentials.length == 1;
    return [
      if (state.credentials.isEmpty && !state.isLoading)
        Padding(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Text(
            l10n.signInMethodsEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        )
      else if (state.credentials.isNotEmpty)
        TenturaMenuGroup(
          title: l10n.signInMethodsYours,
          children: [
            for (final credential in state.credentials)
              TenturaMenuTile(
                icon: _iconForType(credential.type),
                title: _typeLabel(l10n, credential.type),
                subtitle: _subtitle(context, l10n, credential),
                opensPage: false,
                enabled: true,
                // Removing the last method would lock the account.
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: onlyOne
                      ? l10n.signInMethodsLastOne
                      : l10n.buttonRemove,
                  onPressed: state.isLoading || onlyOne
                      ? null
                      : () => _confirmRemove(context, l10n, credential),
                ),
              ),
          ],
        ),
      if (state.showAddSection) ...[
        TenturaMenuGroup(
          title: l10n.addSignInMethod,
          children: [
            if (state.canAddGoogle)
              TenturaMenuTile(
                icon: Icons.g_mobiledata,
                title: l10n.credentialGoogle,
                trailing: Icon(Icons.add, color: tt.info),
                onTap: state.isLoading ? null : () => _linkGoogle(context),
              ),
            if (state.canAddEmail)
              TenturaMenuTile(
                icon: Icons.mail_outline,
                title: l10n.credentialEmail,
                trailing: Icon(Icons.add, color: tt.info),
                onTap: state.isLoading ? null : () => _linkEmail(context, l10n),
              ),
            if (state.canAddRecoverySeed)
              TenturaMenuTile(
                // Not the device-key glyph: a seed phrase is a different
                // thing to have.
                icon: Icons.password_outlined,
                title: l10n.credentialRecoverySeed,
                trailing: Icon(Icons.add, color: tt.info),
                onTap: state.isLoading ? null : () => _linkSeed(context, l10n),
              ),
          ],
        ),
      ],
    ];
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
    final email = await showTenturaAdaptiveSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final tt = sheetContext.tt;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDirty = controller.text.trim().isNotEmpty;
            return TenturaSheetDismissGuard(
              isDirty: isDirty,
              child: Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  right: tt.screenHPadding,
                  top: tt.sectionGap,
                  bottom:
                      MediaQuery.viewInsetsOf(sheetContext).bottom +
                      tt.sectionGap,
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
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    SizedBox(height: tt.sectionGap),
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(sheetContext).pop(controller.text),
                      child: Text(l10n.linkEmailSend),
                    ),
                  ],
                ),
              ),
            );
          },
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

  String _subtitle(
    BuildContext context,
    L10n l10n,
    CredentialEntity credential,
  ) {
    // Key hashes are shortened; an email address is shown whole — cut to 16
    // characters it read "elena-ux@test.te…" on a 650 dp row.
    final identifier =
        credential.type != CredentialTypes.emailOtp &&
            credential.identifier.length > 16
        ? '${credential.identifier.substring(0, 16)}…'
        : credential.identifier;
    final created = credential.createdAt;
    if (created == null) return identifier;
    final now = DateTime.now();
    final relative = compactRelativeTimeAgo(
      when: created,
      now: now,
      l10n: l10n,
    );
    if (now.difference(created).inDays < 7) {
      return '$identifier · $relative';
    }
    final locale = l10n.localeName;
    final formatted = DateFormat.yMMMd(locale).format(created.toLocal());
    return '$identifier · $formatted';
  }
}
