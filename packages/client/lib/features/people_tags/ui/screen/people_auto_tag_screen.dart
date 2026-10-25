import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/people_tags_exception.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../widget/people_tag_person_row.dart';
import '../widget/people_tag_profiles.dart';
import '../widget/person_auto_tag_name.dart';

/// One automatic tag: the people it holds now, and Make it my tag.
@RoutePage()
class PeopleAutoTagScreen extends StatefulWidget {
  const PeopleAutoTagScreen({
    @PathParam('kind') this.kind = 0,
    super.key,
  });

  final int kind;

  @override
  State<PeopleAutoTagScreen> createState() => _PeopleAutoTagScreenState();
}

class _PeopleAutoTagScreenState extends State<PeopleAutoTagScreen> {
  final _peopleTags = GetIt.I<PeopleTagsCase>();
  final _profiles = PeopleTagProfiles();

  List<String> _people = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final ids = await _peopleTags.autoTagMembers(widget.kind);
      await _profiles.ensure(ids);
      if (mounted) setState(() => _people = ids);
    } catch (e, s) {
      _showError(e, s);
    }
  }

  Future<void> _makeMine() async {
    final name = personAutoTagName(L10n.of(context)!, widget.kind);
    setState(() => _busy = true);
    try {
      final tag = await _peopleTags.createTag(
        name: name,
        fromAutoKind: widget.kind,
      );
      if (mounted) await context.router.replace(PeopleTagRoute(tagId: tag.id));
    } on PeopleTagsException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnackBar(
        context,
        isError: true,
        text: e.toL10n(L10n.of(context)!.localeName),
      );
    } catch (e, s) {
      if (mounted) setState(() => _busy = false);
      _showError(e, s);
    }
  }

  void _showError(Object e, StackTrace s) {
    if (!mounted) return;
    showSnackBar(
      context,
      isError: true,
      text: e.toString(),
      error: e,
      stackTrace: s,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final name = personAutoTagName(l10n, widget.kind);
    return Scaffold(
      appBar: TenturaTopBar.of(context, title: Text(name)),
      body: SafeArea(
        child: TenturaContentColumn(
          child: ListView(
            padding: EdgeInsets.all(tt.screenHPadding),
            children: [
              Row(
                children: [
                  Text(
                    '${_people.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : () => unawaited(_makeMine()),
                    child: Text(l10n.peopleTagsMakeMine),
                  ),
                ],
              ),
              SizedBox(height: tt.rowGap),
              for (final id in _people)
                PeopleTagPersonRow(id: id, profile: _profiles.of(id)),
              SizedBox(height: tt.rowGap),
              Text(
                l10n.peopleTagsOnlyYouSee,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
