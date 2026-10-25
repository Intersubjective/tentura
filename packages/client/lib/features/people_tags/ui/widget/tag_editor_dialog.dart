import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/people_tags_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Saves the edited tag; may throw [PeopleTagsException], which the editor
/// shows under the name field and stays open.
typedef TagEditorSave =
    Future<PersonTag> Function(String name, String? glyph, int color);

/// Name, glyph (a letter or an emoji from the platform keyboard) and one of
/// the eight colours of a new tag, or of the [initial] tag being edited. Pops
/// with the saved tag, null on cancel.
Future<PersonTag?> showTagEditorDialog(
  BuildContext context, {
  required TagEditorSave onSave,
  PersonTag? initial,
}) => showDialog<PersonTag>(
  context: context,
  builder: (_) => _TagEditorDialog(onSave: onSave, initial: initial),
);

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({required this.onSave, this.initial});

  final TagEditorSave onSave;
  final PersonTag? initial;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _glyph = TextEditingController(text: widget.initial?.glyph);

  late int _color = widget.initial?.color ?? 0;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _glyph.dispose();
    super.dispose();
  }

  bool get _canSave => !_busy && _name.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final glyph = _glyph.text.trim();
    try {
      final tag = await widget.onSave(
        _name.text.trim(),
        glyph.isEmpty ? null : glyph,
        _color,
      );
      if (mounted) Navigator.of(context).pop(tag);
    } on PeopleTagsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toL10n(L10n.of(context)!.localeName);
      });
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar(
        context,
        isError: true,
        text: e.toString(),
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l10n.peopleTagsEditorTitle
            : l10n.peopleTagsEditTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('tag-editor-name'),
              controller: _name,
              autofocus: true,
              maxLength: 32,
              buildCounter: tenturaCounterNearLimit,
              textInputAction: TextInputAction.done,
              style: tenturaFormFieldTextStyle(context),
              decoration: tenturaFormFieldDecoration(
                context,
                labelText: l10n.peopleTagsEditorName,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) {
                if (_canSave) unawaited(_save());
              },
            ),
            SizedBox(height: tt.rowGap),
            TextField(
              key: const ValueKey('tag-editor-glyph'),
              controller: _glyph,
              maxLength: 2,
              buildCounter: tenturaCounterNearLimit,
              style: tenturaFormFieldTextStyle(context),
              decoration: tenturaFormFieldDecoration(
                context,
                labelText: l10n.peopleTagsEditorGlyph,
              ),
            ),
            SizedBox(height: tt.rowGap),
            Wrap(
              children: [
                for (var i = 0; i < TenturaTagColors.swatchCount; i++)
                  _ColorSwatchButton(
                    colorIndex: i,
                    name: _colorName(l10n, i),
                    selected: i == _color,
                    onTap: () => setState(() => _color = i),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('tag-editor-save'),
          onPressed: _canSave ? _save : null,
          child: Text(l10n.peopleTagsEditorSave),
        ),
      ],
    );
  }
}

String _colorName(L10n l10n, int index) => switch (index) {
  0 => l10n.peopleTagsColorRed,
  1 => l10n.peopleTagsColorOrange,
  2 => l10n.peopleTagsColorAmber,
  3 => l10n.peopleTagsColorGreen,
  4 => l10n.peopleTagsColorTeal,
  5 => l10n.peopleTagsColorBlue,
  6 => l10n.peopleTagsColorViolet,
  _ => l10n.peopleTagsColorPink,
};

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.colorIndex,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final int colorIndex;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: tt.buttonHeight / 2,
        child: SizedBox.square(
          dimension: tt.buttonHeight,
          child: Center(
            child: TagGlyph(
              glyph: selected ? '✓' : '',
              colorIndex: colorIndex,
              size: tt.avatarSizeSmall,
            ),
          ),
        ),
      ),
    );
  }
}
