import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/platform/web_safe_text_field_enabled.dart';
import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/exception/now_line_changed_exception.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/code_unit_length_formatter.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

/// Sets the beacon room [current line] via [BeaconThreadsCase.updateRoomNowLine].
///
/// [baseRevision] is the `currentLineRevision` of [initialText]. When someone
/// changed the line meanwhile, the sheet stays open with the person's text,
/// shows the newer line and calls [onStale] with it (so the screen behind
/// shows it too); saving again re-applies the person's text on top (#517).
Future<void> showBeaconCurrentLineSheet(
  BuildContext context, {
  required String beaconId,
  required String initialText,
  required int baseRevision,
  void Function(BeaconRoomState saved)? onSaved,
  void Function(NowLineChangedException newer)? onStale,
}) async {
  final l10n = L10n.of(context)!;
  final threadsCase = GetIt.I<BeaconThreadsCase>();
  final saved = await showTenturaAdaptiveSheet<BeaconRoomState>(
    context: context,
    useRootNavigator: true,
    enableDrag: false,
    builder: (ctx) => _BeaconCurrentLineSheetBody(
      l10n: l10n,
      beaconId: beaconId,
      initialText: initialText,
      baseRevision: baseRevision,
      threadsCase: threadsCase,
      onStale: onStale,
    ),
  );
  if (saved != null && context.mounted) {
    onSaved?.call(saved);
  }
}

class _BeaconCurrentLineSheetBody extends StatefulWidget {
  const _BeaconCurrentLineSheetBody({
    required this.l10n,
    required this.beaconId,
    required this.initialText,
    required this.baseRevision,
    required this.threadsCase,
    this.onStale,
  });

  final L10n l10n;
  final String beaconId;
  final String initialText;
  final int baseRevision;
  final BeaconThreadsCase threadsCase;
  final void Function(NowLineChangedException newer)? onStale;

  @override
  State<_BeaconCurrentLineSheetBody> createState() =>
      _BeaconCurrentLineSheetBodyState();
}

class _BeaconCurrentLineSheetBodyState
    extends State<_BeaconCurrentLineSheetBody> {
  late final TextEditingController _controller;

  /// The field is disabled while saving, which takes focus away; a failed
  /// save gives it back so a keyboard user can keep typing (#693).
  final _focusNode = FocusNode();

  var _submitting = false;

  /// The revision this save is based on: the one the editor opened with,
  /// or, after a conflict, that of the other person's line, which is now
  /// shown (so the next Save replaces it on purpose).
  late int _baseRevision;

  /// Set when someone else changed the line while this editor was open.
  String? _conflict;

  /// Set when a save failed for another reason (network, server).
  String? _saveError;

  /// Whether a newer line was seen while this editor was open; then "Keep
  /// theirs" closes without saving.
  var _sawNewer = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _baseRevision = widget.baseRevision;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty && !_submitting;

  bool get _isDirty => _controller.text.trim() != widget.initialText.trim();

  /// Called after a failed save: the field can take focus again only once it
  /// is rebuilt enabled, so the request waits for that frame (#693).
  void _refocusField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _save() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _saveError = null;
    });
    try {
      final line = _controller.text.trim();
      final saved = await widget.threadsCase.updateRoomNowLine(
        beaconId: widget.beaconId,
        currentLine: line,
        baseRevision: _baseRevision,
      );
      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } on NowLineChangedException catch (e) {
      // Shown inside the sheet (a snackbar would sit under it): the other
      // person's line, and that the next Save replaces it (B085). Their text
      // stays in the field.
      _baseRevision = e.currentRevision;
      widget.onStale?.call(e);
      if (mounted) {
        setState(() {
          _submitting = false;
          _sawNewer = true;
          _conflict = e.toL10n(L10n.of(context)?.localeName);
        });
        _refocusField();
      }
    } on Object catch (e, st) {
      // Shown inside the sheet: a snackbar would sit under it, unseen (#603).
      // The text stays in the field for another try.
      reportUserFacingError(e, stackTrace: st);
      if (mounted) {
        final locale = L10n.of(context)?.localeName;
        setState(() {
          _submitting = false;
          _saveError = switch (e) {
            final Localizable l => l.toL10n(locale),
            _ => e.toString(),
          };
        });
        _refocusField();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final tt = context.tt;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return TenturaSheetDismissGuard(
      isDirty: _isDirty,
      useRootNavigator: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          top: tt.sectionGap,
          bottom: bottom + tt.sectionGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.beaconHudEditCurrentLineTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                // Same discard check as the scrim (#444).
                IconButton(
                  tooltip: l10n.buttonClose,
                  onPressed: () => unawaited(
                    TenturaSheetDismissGuard.requestClose(
                      context,
                      isDirty: _isDirty,
                      useRootNavigator: true,
                    ),
                  ),
                  icon: Icon(Icons.close, size: tt.iconSize),
                ),
              ],
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: l10n.beaconRoomStripCurrentLineLabel,
                helperText: l10n.beaconCurrentLineEditHelper,
                helperMaxLines: 3,
                errorText: _conflict ?? _saveError,
                errorMaxLines: 4,
              ),
              // The conflict note is about the text they saw; once they edit,
              // it no longer applies (B085 review).
              onChanged: (_) => setState(() {
                _conflict = null;
                _saveError = null;
              }),
              maxLength: kBeaconRoomCurrentLineMaxLength,
              // Code units, as the server counts the line (#343): maxLength
              // alone counts characters, so an emoji fit here and failed there.
              inputFormatters: const [
                CodeUnitLengthLimitingTextInputFormatter(
                  kBeaconRoomCurrentLineMaxLength,
                ),
              ],
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => Text(
                    '${_controller.text.length}/$maxLength',
                    style: TenturaText.withTabular(
                      TenturaText.bodySmall(context.tt.textMuted),
                    ),
                  ),
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              enabled: webSafeTextFieldEnabled(
                targetEnabled: !_submitting,
                hasFocus: _focusNode.hasFocus,
              ),
              autofocus: true,
            ),
            SizedBox(height: tt.sectionGap),
            if (_sawNewer) ...[
              // The newer line is already shown behind the sheet; closing
              // keeps it (#517).
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(l10n.beaconCurrentLineKeepTheirs),
              ),
              SizedBox(height: tt.rowGap),
            ],
            FilledButton(
              onPressed: !_canSubmit ? null : _save,
              child: _submitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(MaterialLocalizations.of(context).saveButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
