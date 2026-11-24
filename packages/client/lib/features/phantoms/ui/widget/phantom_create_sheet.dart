import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/emoji/ui/widget/emoji_picker_button.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/code_unit_length_formatter.dart';
import 'package:tentura/ui/util/share_link.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../domain/port/phantom_repository_port.dart';
import '../../domain/use_case/phantom_creation_case.dart';

Future<void> showPhantomCreateSheet(
  BuildContext context, {
  required ConstellationAnchorPosition position,
}) {
  final create = PhantomCreationCase(
    GetIt.I<PhantomRepositoryPort>(),
    GetIt.I<PeopleTagsCase>(),
  );
  return showTenturaAdaptiveSheet<void>(
    context: context,
    showSnackBars: true,
    builder: (_) => _PhantomCreateSheet(create: create, position: position),
  );
}

enum _CreateAction { save, copy, share }

class _PhantomCreateSheet extends StatefulWidget {
  const _PhantomCreateSheet({required this.create, required this.position});

  final PhantomCreationCase create;
  final ConstellationAnchorPosition position;

  @override
  State<_PhantomCreateSheet> createState() => _PhantomCreateSheetState();
}

class _PhantomCreateSheetState extends State<_PhantomCreateSheet> {
  final _invite = TextEditingController();
  final _tagIds = <String>{};
  late final _tagsLoaded = widget.create.loadTags();
  String _name = '';
  String? _emoji;
  bool _inviteEdited = false;
  bool _busy = false;

  String? get _validName => _name.length >= kTitleMinLength ? _name : null;

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  void _changeName(String name, L10n l10n) {
    setState(() {
      _name = name.trim();
      if (!_inviteEdited) {
        _invite.text = _name.isEmpty ? '' : l10n.personCreateInviteText(_name);
      }
    });
  }

  Future<void> _pickEmoji() async {
    final emoji = await showSingleEmojiPicker(context);
    if (mounted && emoji != null) setState(() => _emoji = emoji);
  }

  Future<void> _submit(BuildContext actionContext, _CreateAction action) async {
    final name = _validName;
    if (_busy || name == null) return;
    final message = _invite.text;
    final l10n = L10n.of(context)!;
    setState(() => _busy = true);
    try {
      final id = await widget.create.save(
        name: name,
        position: widget.position,
        tagIds: Set.of(_tagIds),
        emoji: _emoji,
      );
      if (!actionContext.mounted) return;
      if (action == _CreateAction.save) {
        Navigator.of(actionContext).pop();
        return;
      }
      final link = inviteShareUri(
        await widget.create.ensureInvite(id),
      ).toString();
      if (!actionContext.mounted) return;
      final text = message.isEmpty ? link : '$message\n$link';
      if (action == _CreateAction.copy) {
        await copyShareLink(actionContext, link: link, text: text);
      } else {
        await shareLink(
          actionContext,
          link: link,
          subject: l10n.personCreateCanvasAction,
          text: text,
        );
      }
    } on Exception catch (error, trace) {
      if (actionContext.mounted) {
        showSnackBar(
          actionContext,
          text: widget.create.hasCreatedPerson
              ? l10n.errorGenericAction
              : l10n.personCreateCheckField,
          isError: true,
          error: error,
          stackTrace: trace,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final create = widget.create;
    final canEditPerson = !_busy && !create.hasStarted;
    final canSubmit =
        !_busy &&
        _validName != null &&
        (!create.hasStarted || create.hasCreatedPerson);

    return TenturaSheetDismissGuard(
      isDirty: false,
      canDismiss: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: tt.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.personCreateCanvasAction,
                style: theme.textTheme.titleLarge,
              ),
              SizedBox(height: tt.sectionGap),
              TextField(
                decoration: InputDecoration(labelText: l10n.personCreateName),
                enabled: canEditPerson,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [
                  CodeUnitLengthLimitingTextInputFormatter(kTitleMaxLength),
                ],
                onChanged: (name) => _changeName(name, l10n),
              ),
              SizedBox(height: tt.rowGap),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: canEditPerson ? _pickEmoji : null,
                  icon: switch (_emoji) {
                    final emoji? => Text(emoji),
                    null => const Icon(Icons.emoji_emotions_outlined),
                  },
                  label: Text(l10n.composerEmojiButtonTooltip),
                ),
              ),
              SizedBox(height: tt.rowGap),
              Text(
                l10n.constellationTagsSection,
                style: theme.textTheme.titleSmall,
              ),
              FutureBuilder<void>(
                future: _tagsLoaded,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text(l10n.errorGenericAction);
                  return Wrap(
                    spacing: tt.rowGap,
                    children: [
                      for (final tag in widget.create.tags)
                        FilterChip(
                          label: Text(tag.name),
                          selected: _tagIds.contains(tag.id),
                          onSelected: canEditPerson
                              ? (selected) => setState(() {
                                  if (selected) {
                                    _tagIds.add(tag.id);
                                  } else {
                                    _tagIds.remove(tag.id);
                                  }
                                })
                              : null,
                        ),
                    ],
                  );
                },
              ),
              SizedBox(height: tt.sectionGap),
              TextField(
                controller: _invite,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: l10n.personCreateInviteLabel,
                ),
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => _inviteEdited = true,
              ),
              SizedBox(height: tt.sectionGap),
              OutlinedButton(
                onPressed: canSubmit
                    ? () => _submit(context, _CreateAction.copy)
                    : null,
                child: Text(l10n.personCreateCopyInvite),
              ),
              Builder(
                builder: (buttonContext) => OutlinedButton(
                  onPressed: canSubmit
                      ? () => _submit(buttonContext, _CreateAction.share)
                      : null,
                  child: Text(l10n.personCreateShare),
                ),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => _submit(context, _CreateAction.save)
                    : null,
                child: Text(l10n.personCreateSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
