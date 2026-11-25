import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/phantoms/domain/exception.dart';
import 'package:tentura/features/phantoms/domain/port/phantom_repository_port.dart';
import 'package:tentura/features/phantoms/ui/widget/phantom_context_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/util/ui_utils.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';

import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';

const _destination = AttentionFeedDestinationId.fieldPersonLinks;

class ConstellationLinkNotices extends StatefulWidget {
  const ConstellationLinkNotices({
    required this.cubit,
    required this.field,
    required this.maxHeight,
    super.key,
  });

  final ConstellationCubit cubit;
  final ConstellationField field;
  final double maxHeight;

  @override
  State<ConstellationLinkNotices> createState() =>
      _ConstellationLinkNoticesState();
}

class _ConstellationLinkNoticesState extends State<ConstellationLinkNotices> {
  AttentionCase? _attention;
  StreamSubscription<AttentionFeedSession>? _subscription;
  List<AttentionReceipt> _receipts = const [];
  final _shownMerges = <String>{};
  final _dismissedHints = <ConstellationLinkHint>{};
  bool _mergeScheduled = false;
  bool _showingMerge = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!GetIt.I.isRegistered<AttentionCase>()) return;
    final attention = GetIt.I<AttentionCase>()..attachFeedSession(_destination);
    _attention = attention;
    _subscription = attention.watchFeedSession(_destination).listen((session) {
      setState(() {
        _receipts = [
          for (final receipt
              in session.pages[AttentionView.all]?.items ??
                  const <AttentionReceipt>[])
            if (receipt.personLinkNotice != null) receipt,
        ];
      });
      _scheduleMerge();
    });
    unawaited(attention.refresh(destinationId: _destination));
  }

  @override
  void didUpdateWidget(ConstellationLinkNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    _dismissedHints.removeWhere(
      (hint) => !widget.field.linkHints.contains(hint),
    );
    _scheduleMerge();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _attention?.detachFeedSession(_destination);
    super.dispose();
  }

  void _scheduleMerge() {
    if (_mergeScheduled || _showingMerge) return;
    _mergeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mergeScheduled = false;
      if (mounted) _showMerge();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showMerge() {
    final l10n = L10n.of(context);
    if (l10n == null) return;
    final names = {
      for (final person in widget.field.phantoms) person.id: person.displayName,
    };
    // Present oldest first. The shared snackbar replaces the current bar.
    for (final receipt in _receipts.reversed) {
      final notice = receipt.personLinkNotice;
      final source = receipt.sourceEventKey;
      if (notice == null ||
          notice.kind != PersonLinkNoticeKind.merged ||
          receipt.isSeen ||
          source == null ||
          _shownMerges.contains(source)) {
        continue;
      }
      final name = notice.displayName ?? names[notice.phantomId];
      if (name == null) continue;
      final cubit = widget.cubit;
      final bar = showUndoSnackBar(
        context,
        text: l10n.personLinkMerged(name),
        onUndo: () {
          if (mounted) {
            unawaited(
              unlinkConstellationPerson(context, cubit, notice.phantomId),
            );
          }
        },
      );
      if (bar == null) return;
      _shownMerges.add(source);
      _showingMerge = true;
      unawaited(_markSeen(receipt.id));
      unawaited(
        bar.closed.then((_) {
          _showingMerge = false;
          if (!mounted) return;
          _scheduleMerge();
        }),
      );
      return;
    }
  }

  Future<void> _markSeen(String id) async {
    try {
      await _attention?.markSeen([id]);
    } on Exception {
      // AttentionCase reports and rolls back a failed acknowledgement.
    }
  }

  Future<void> _act(
    Future<void> Function(PhantomRepositoryPort) action, {
    String? name,
  }) async {
    if (_busy) return;
    final cubit = widget.cubit;
    setState(() => _busy = true);
    try {
      await action(GetIt.I<PhantomRepositoryPort>());
      await cubit.refreshAfterPhantomWrite();
    } on Exception catch (error, stackTrace) {
      if (mounted) _showLinkError(context, error, stackTrace, name: name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    if (l10n == null) return const SizedBox.shrink();
    final field = widget.field;
    if (_receipts.isEmpty && field.linkHints.isEmpty) {
      return const SizedBox.shrink();
    }
    final cubit = widget.cubit;
    final privateNames = {
      for (final person in field.phantoms) person.id: person.displayName,
    };
    final people = constellationLinkCandidates(cubit);
    final accountNames = {for (final person in people) person.id: person.name};
    final joined = <String>{};
    final cards = [
      for (final receipt in _receipts)
        if (receipt.personLinkNotice case (
          kind: PersonLinkNoticeKind.joined,
          :final phantomId,
          displayName: _,
        ))
          if (privateNames[phantomId] case final String name
              when joined.add(phantomId))
            _LinkCard(
              text: l10n.personLinkJoined(name),
              actions: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _act((repository) async {
                            final picked = await pickPersonToLink(
                              context,
                              people,
                            );
                            if (!context.mounted || picked == null) return;
                            await repository.link(
                              phantomId: phantomId,
                              userId: picked,
                            );
                          }, name: name),
                        ),
                  child: Text(l10n.personLinkChoose),
                ),
              ],
            ),
      for (final hint in field.linkHints)
        if (!_dismissedHints.contains(hint))
          if (privateNames[hint.phantomId] case final String privateName)
            if (accountNames[hint.userId] case final String accountName)
              _LinkCard(
                text: l10n.personLinkHint(privateName, accountName),
                actions: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _act(
                              (repository) => repository.link(
                                phantomId: hint.phantomId,
                                userId: hint.userId,
                              ),
                              name: privateName,
                            ),
                          ),
                    child: Text(l10n.personLinkConfirm),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(
                            _act((repository) async {
                              await repository.hintDismiss(
                                phantomId: hint.phantomId,
                                userId: hint.userId,
                              );
                              if (mounted) {
                                setState(() => _dismissedHints.add(hint));
                              }
                            }, name: privateName),
                          ),
                    child: Text(l10n.personLinkDismiss),
                  ),
                ],
              ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cards,
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: context.tt.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          Wrap(spacing: context.tt.tightGap, children: actions),
        ],
      ),
    ),
  );
}

List<({String id, String name})> constellationLinkCandidates(
  ConstellationCubit cubit,
) => [
  for (final person in cubit.fieldPeople)
    if (!person.isViewer &&
        cubit.fieldPersonById(person.id)?.pinState != 'tombstone')
      (id: person.id, name: person.name),
];

Future<void> unlinkConstellationPerson(
  BuildContext context,
  ConstellationCubit cubit,
  String phantomId,
) async {
  try {
    await GetIt.I<PhantomRepositoryPort>().unmerge(phantomId: phantomId);
    await cubit.refreshAfterPhantomWrite();
  } on Exception catch (error, stackTrace) {
    if (context.mounted) _showLinkError(context, error, stackTrace);
  }
}

void _showLinkError(
  BuildContext context,
  Exception error,
  StackTrace stackTrace, {
  String? name,
}) {
  final l10n = L10n.of(context);
  if (l10n == null) return;
  final joining = error is PhantomJoiningException && name != null;
  showSnackBar(
    context,
    text: joining ? l10n.personPanelJoining(name) : l10n.errorGenericAction,
    isError: !joining,
    isFloating: joining,
    error: joining ? null : error,
    stackTrace: stackTrace,
  );
}
