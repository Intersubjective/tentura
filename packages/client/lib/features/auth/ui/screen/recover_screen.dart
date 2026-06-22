import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/auth_cubit.dart';

@RoutePage()
class RecoverScreen extends StatefulWidget implements AutoRouteWrapper {
  const RecoverScreen({
    @QueryParam('invite') this.invite,
    super.key,
  });

  /// Optional invite code from the landing page (`/recover?invite=I…`).
  final String? invite;

  @override
  Widget wrappedRoute(BuildContext context) {
    final inviteCode = _normalizedInviteCode(invite);
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (previous, current) =>
          previous.isNotAuthenticated && current.isAuthenticated,
      listener: (context, state) {
        if (state.isAuthenticated) {
          if (inviteCode != null) {
            unawaited(
              context.router.replaceAll([
                AcceptInviteRoute(id: inviteCode),
              ]),
            );
          } else {
            unawaited(context.router.replaceAll([const HomeRoute()]));
          }
        }
      },
      child: BlocListener<AuthCubit, AuthState>(
        listener: commonScreenBlocListener,
        child: this,
      ),
    );
  }

  static String? _normalizedInviteCode(String? raw) {
    final code = raw?.trim() ?? '';
    if (code.isEmpty || !kInvitationCodeRegExp.hasMatch(code)) {
      return null;
    }
    return code;
  }

  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _seedController = TextEditingController();

  var _hasScanResult = false;

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _recover(String seed) async {
    final trimmed = seed.trim();
    if (trimmed.isEmpty) return;
    await context.read<AuthCubit>().recoverAndSignIn(trimmed);
  }

  void _handleBarcode(BarcodeCapture captured) {
    if (_hasScanResult || captured.barcodes.isEmpty) return;
    final value = captured.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _hasScanResult = true;
    _seedController.text = value;
    unawaited(_recover(value));
  }

  Future<void> _confirmResetLocal(BuildContext context, L10n l10n) async {
    final authCubit = context.read<AuthCubit>();
    final seedWarning = await authCubit.hasSeedOnlyLocalAccounts();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.authRecoveryResetLocalTitle),
        content: Text(
          seedWarning
              ? '${l10n.authRecoveryResetLocalBody}\n\n'
                    '${l10n.authRecoveryResetSeedWarning}'
              : l10n.authRecoveryResetLocalBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.authRecoveryResetLocalTitle),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await authCubit.resetLocalAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final authCubit = context.read<AuthCubit>();
    final theme = Theme.of(context);
    final tt = context.tt;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.authRecoveryHubTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<AuthCubit, AuthState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: authCubit,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(tt.screenHPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.authSessionProblemBanner,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: kSpacingMedium),
              FilledButton(
                onPressed: authCubit.signInAgain,
                child: Text(l10n.authRecoverySignInAgain),
              ),
              const SizedBox(height: kSpacingSmall),
              OutlinedButton(
                onPressed: () => _confirmResetLocal(context, l10n),
                child: Text(l10n.authRecoveryResetLocalTitle),
              ),
              const SizedBox(height: kSpacingLarge),
              Text(
                l10n.recoverFromSeedHint,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: kSpacingMedium),
              LayoutBuilder(
                builder: (context, constraints) {
                  final viewportH = MediaQuery.sizeOf(context).height;
                  final qrHeight = (viewportH * 0.28).clamp(180.0, 320.0);
                  return SizedBox(
                    height: qrHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      child: MobileScanner(onDetect: _handleBarcode),
                    ),
                  );
                },
              ),
              const SizedBox(height: kSpacingMedium),
              TextField(
                controller: _seedController,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.recoverFromSeedFieldLabel,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _recover,
              ),
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.recoverFromSeedPrivacyNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: kSpacingMedium),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty && mounted) {
                        _seedController.text = text;
                      }
                    },
                    icon: const Icon(Icons.paste_rounded),
                    label: Text(l10n.buttonPaste),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _recover(_seedController.text),
                    child: Text(l10n.recoverFromSeedAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
