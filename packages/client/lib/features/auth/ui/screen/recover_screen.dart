import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:tentura/app/sentry/auth_telemetry.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/invitation/domain/invite_code.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/auth_cubit.dart';

@RoutePage()
class RecoverScreen extends StatefulWidget implements AutoRouteWrapper {
  const RecoverScreen({
    @QueryParam('invite') this.invite,
    @QueryParam('auth_attempt_id') this.authAttemptId,
    super.key,
  });

  /// Optional invite code from the landing page (`/recover?invite=I…`).
  final String? invite;

  /// Funnel correlation id from the landing recover CTA (optional).
  final String? authAttemptId;

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
      child: this,
    );
  }

  static String? _normalizedInviteCode(String? raw) {
    final code = normalizeInviteCode(raw ?? '');
    if (code.isEmpty || !isValidInviteCode(code)) {
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
  final _scanLiveRegionKey = GlobalKey();

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  Future<void> _recover(String seed) async {
    final trimmed = seed.trim();
    if (trimmed.isEmpty) return;
    final attemptId = widget.authAttemptId?.trim();
    if (attemptId != null && attemptId.isNotEmpty) {
      await tagClientAuthAttempt(authAttemptId: attemptId, authMethod: 'seed');
      await emitClientAuthOutcome(
        'seed_recovery_started',
        authOutcome: 'started',
        authAttemptId: attemptId,
        authMethod: 'seed',
      );
    }
    await context.read<AuthCubit>().recoverAndSignIn(
      trimmed,
      authAttemptId: attemptId,
    );
  }

  void _handleBarcode(BarcodeCapture captured) {
    if (_hasScanResult || captured.barcodes.isEmpty) return;
    final value = captured.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _hasScanResult = true;
    _seedController.text = value;
    if (mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        L10n.of(context)!.recoverFromSeedAction,
        TextDirection.ltr,
      );
    }
    unawaited(_recover(value));
  }

  Future<void> _confirmResetLocal() async {
    final l10n = L10n.of(context)!;
    final authCubit = context.read<AuthCubit>();
    final seedWarning = await authCubit.hasSeedOnlyLocalAccounts();
    if (!mounted) return;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.authRecoveryResetLocalTitle,
      content: seedWarning
          ? '${l10n.authRecoveryResetLocalBody}\n\n'
                '${l10n.authRecoveryResetSeedWarning}'
          : l10n.authRecoveryResetLocalBody,
      confirmLabel: l10n.authRecoveryResetLocalTitle,
      cancelLabel: l10n.buttonCancel,
    );
    if ((confirmed ?? false) && mounted) {
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
      appBar: TenturaTopBar.of(
        context,
        centerTitle: true,
        leading: const AutoLeadingButton(),
        title: Text(l10n.authRecoveryHubTitle),
        progress: BlocSelector<AuthCubit, AuthState, bool>(
          selector: (state) => state.isLoading,
          builder: TenturaTopBar.loadingBar,
          bloc: authCubit,
        ),
      ),
      body: SafeArea(
        child: TenturaContentColumn(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tt.screenHPadding),
            child: BlocSelector<AuthCubit, AuthState, bool>(
              bloc: authCubit,
              selector: (state) => state.isLoading,
              builder: (context, isLoading) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.authSessionProblemBanner,
                      style: theme.textTheme.bodyMedium,
                    ),
                    SizedBox(height: tt.sectionGap),
                    FilledButton(
                      onPressed: isLoading ? null : authCubit.signInAgain,
                      child: Text(l10n.authRecoverySignInAgain),
                    ),
                    SizedBox(height: tt.rowGap),
                    OutlinedButton(
                      onPressed: isLoading
                          ? null
                          : () => unawaited(_confirmResetLocal()),
                      child: Text(l10n.authRecoveryResetLocalTitle),
                    ),
                    SizedBox(height: tt.sectionGap * 2),
                    Text(
                      l10n.recoverFromSeedHint,
                      style: theme.textTheme.bodyMedium,
                    ),
                    SizedBox(height: tt.sectionGap),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final viewportH = MediaQuery.sizeOf(context).height;
                        final qrHeight = (viewportH * 0.28).clamp(180.0, 320.0);
                        return SizedBox(
                          height: qrHeight,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(tt.cardRadius),
                            child: Semantics(
                              key: _scanLiveRegionKey,
                              label: l10n.recoverFromSeedHint,
                              liveRegion: true,
                              child: MobileScanner(onDetect: _handleBarcode),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: tt.sectionGap),
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
                    SizedBox(height: tt.rowGap),
                    Text(
                      l10n.recoverFromSeedPrivacyNote,
                      style: theme.textTheme.bodySmall,
                    ),
                    SizedBox(height: tt.sectionGap),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
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
                          onPressed: isLoading
                              ? null
                              : () => _recover(_seedController.text),
                          child: Text(l10n.recoverFromSeedAction),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
