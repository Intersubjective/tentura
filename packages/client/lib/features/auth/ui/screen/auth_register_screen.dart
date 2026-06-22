import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/env.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/string_input_validator.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../bloc/auth_cubit.dart';

@RoutePage()
class AuthRegisterScreen extends StatefulWidget implements AutoRouteWrapper {
  const AuthRegisterScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  @override
  State<AuthRegisterScreen> createState() => _AuthRegisterScreenState();

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocListener<ScreenCubit, ScreenState>(
        listener: commonScreenBlocListener,
        child: this,
      );
}

class _AuthRegisterScreenState extends State<AuthRegisterScreen>
    with StringInputValidator {
  final _env = GetIt.I<Env>();

  final _authCubit = GetIt.I<AuthCubit>();

  final _codeController = TextEditingController();

  final _titleController = TextEditingController();

  final _handleController = TextEditingController();

  late final _textTheme = Theme.of(context).textTheme;

  late final _l10n = L10n.of(context)!;

  @override
  void initState() {
    super.initState();
    final invitationId = widget.id.trim();
    if (invitationId.isNotEmpty) {
      _codeController.text = invitationId;
    } else {
      unawaited(_getCodeFromClipboard(supressError: true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: Text(_l10n.createNewAccount),
      leading: const AutoLeadingButton(),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: BlocSelector<AuthCubit, AuthState, bool>(
          key: Key('Loader:${_authCubit.hashCode}'),
          selector: (state) => state.isLoading,
          builder: LinearPiActive.builder,
          bloc: _authCubit,
        ),
      ),
    ),
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Invite Code
        if (_env.needInviteCode)
          Padding(
            padding: kPaddingAll,
            child: TextFormField(
                // Do NOT autofocus when the id is pre-filled from a deep link.
              // On iOS, autofocus during cold-start (e.g. QR-code launch) fires
              // while UIKit still rejects firstResponder requests; Flutter marks
              // the field as focused but the keyboard never appears, breaking
              // all subsequent taps on any field for the rest of the session.
              autofocus: widget.id.trim().isEmpty,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              controller: _codeController,
              contextMenuBuilder: (_, state) =>
                  AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: state.contextMenuAnchors,
                    buttonItems: [
                      ContextMenuButtonItem(
                        type: ContextMenuButtonType.paste,
                        onPressed: _getCodeFromClipboard,
                      ),
                    ],
                  ),

              decoration: InputDecoration(
                hintText: _l10n.pleaseEnterCode,
                labelText: _l10n.labelInvitationCode,
                suffix: IconButton(
                  tooltip: _l10n.buttonPaste,
                  constraints: const BoxConstraints(
                    minWidth: kMinInteractiveDimension,
                    minHeight: kMinInteractiveDimension,
                  ),
                  onPressed: _getCodeFromClipboard,
                  icon: const Icon(Icons.paste_rounded),
                ),
              ),
              maxLength: kIdLength,
              keyboardType: TextInputType.text,
              style: _textTheme.headlineLarge,
              inputFormatters: [
                FilteringTextInputFormatter.allow(kInvitationCodeRegExp),
              ],
              validator: (text) => invitationCodeValidator(_l10n, text),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),

        // Username
        Padding(
          padding: kPaddingAll,
          child: TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _titleController,
            decoration: InputDecoration(
              hintText: _l10n.pleaseFillDisplayName,
              labelText: _l10n.labelDisplayName,
            ),
            maxLength: kTitleMaxLength,
            style: _textTheme.headlineLarge,
            validator: (text) => displayNameValidator(_l10n, text),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),

        // Handle (optional)
        Padding(
          padding: kPaddingAll,
          child: TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _handleController,
            decoration: InputDecoration(
              hintText: _l10n.userHandleHint,
              labelText: _l10n.labelUserHandle,
            ),
            maxLength: kUserHandleMaxLength,
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-z0-9_]')),
            ],
            validator: (text) {
              final t = (text ?? '').trim().toLowerCase();
              if (t.isEmpty) return null;
              if (!isValidUserHandleFormat(t)) {
                return _l10n.userHandleInvalidFormat;
              }
              return null;
            },
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),

        // Register
        Padding(
          padding: kPaddingAll,
          child: FilledButton(
            onPressed: () => _authCubit.signUp(
              invitationCode: _codeController.text,
              displayName: _titleController.text,
              handle: _handleController.text.trim().toLowerCase().isEmpty
                  ? null
                  : _handleController.text.trim().toLowerCase(),
            ),
            child: Text(_l10n.buttonCreate),
          ),
        ),
      ],
      ),
    ),
  );

  Future<void> _getCodeFromClipboard({
    bool supressError = false,
  }) async {
    final code = await _authCubit.getInvitationCodeFromClipboard(
      supressError: supressError,
    );
    if (code.isNotEmpty) {
      _codeController.text = code;
    }
  }
}
