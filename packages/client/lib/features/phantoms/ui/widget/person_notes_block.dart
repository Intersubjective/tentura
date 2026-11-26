import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/person_note.dart';
import '../../domain/port/person_note_repository_port.dart';
import '../bloc/person_notes_cubit.dart';

class PersonNotesBlock extends StatelessWidget {
  const PersonNotesBlock({required this.subject, super.key});

  final PersonNoteSubject subject;

  @override
  Widget build(BuildContext context) {
    final repository = GetIt.I.maybeGet<PersonNoteRepositoryPort>();
    if (repository == null) return const SizedBox.shrink();

    return BlocProvider(
      key: ValueKey((subject.runtimeType, subject.id)),
      create: (_) {
        final cubit = PersonNotesCubit(repository, subject);
        unawaited(cubit.load());
        return cubit;
      },
      child: const _NoteSections(),
    );
  }
}

class _NoteSections extends StatelessWidget {
  const _NoteSections();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<PersonNotesCubit>();
    final state = context.watch<PersonNotesCubit>().state;
    final sections = state.sections;
    return Padding(
      padding: EdgeInsets.only(top: tt.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sections == null && state.busy)
            const Center(child: TenturaCircularProgress()),
          if (sections != null)
            for (final section in sections)
              _NoteEditor(
                key: ValueKey(section.mergedFrom?.subject.id),
                section: section,
                busy: state.busy,
              ),
          if (state.failed) ...[
            TenturaStatusText(l10n.errorGenericAction),
            if (sections == null)
              TenturaTextAction(
                label: l10n.personNoteRetry,
                onPressed: () => unawaited(cubit.load()),
              ),
          ],
        ],
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.section,
    required this.busy,
    super.key,
  });

  final PersonNoteSection section;
  final bool busy;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _controller = TextEditingController(text: widget.section.body);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final draft = _controller.text;
    // TextField counts graphemes. The server's limit counts code points.
    final tooLong = draft.runes.length > kPersonNoteMaxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.section.mergedFrom case (:final name, subject: _)) ...[
          Text('— «$name»', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: tt.tightGap),
        ],
        TextField(
          controller: _controller,
          readOnly: widget.busy,
          minLines: 2,
          maxLines: 4,
          maxLength: kPersonNoteMaxLength,
          decoration: InputDecoration(
            labelText: l10n.personNoteLabel,
            hintText: l10n.personNoteAddHint,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: tooLong ? l10n.personNoteTooLong : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TenturaTextAction(
            label: l10n.buttonSave,
            onPressed: widget.busy || tooLong || draft == widget.section.body
                ? null
                : () => unawaited(
                    context.read<PersonNotesCubit>().save(
                      widget.section,
                      draft,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
