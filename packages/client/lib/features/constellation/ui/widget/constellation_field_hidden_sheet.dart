import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_hidden_item.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field_target_kind.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../bloc/constellation_cubit.dart';

Future<void> showConstellationFieldHiddenSheet(
  BuildContext context, {
  required ConstellationCubit cubit,
}) {
  return showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const ConstellationFieldHiddenSheetBody(),
    ),
  );
}

class ConstellationFieldHiddenSheetBody extends StatefulWidget {
  const ConstellationFieldHiddenSheetBody({super.key});

  @override
  State<ConstellationFieldHiddenSheetBody> createState() =>
      _ConstellationFieldHiddenSheetBodyState();
}

class _ConstellationFieldHiddenSheetBodyState
    extends State<ConstellationFieldHiddenSheetBody> {
  static const _pageSize = 25;

  final _items = <ConstellationFieldHiddenItem>[];
  final _scrollController = ScrollController();
  var _loading = true;
  var _loadingMore = false;
  var _showing = false;
  String? _nextCursor;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || _nextCursor == null) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadInitial() async {
    final hideCase = context.read<ConstellationCubit>().fieldHideCase;
    if (hideCase == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
      _items.clear();
      _nextCursor = null;
    });
    try {
      final batch = await hideCase.fetchHiddenItems();
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(batch);
        _loading = false;
        _nextCursor = batch.length >= _pageSize && batch.isNotEmpty
            ? batch.last.hiddenAt.toUtc().toIso8601String()
            : null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final hideCase = context.read<ConstellationCubit>().fieldHideCase;
    if (cursor == null || hideCase == null || _loadingMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final batch = await hideCase.fetchHiddenItems(cursor: cursor);
      if (!mounted) {
        return;
      }
      setState(() {
        final seen = {
          for (final item in _items) (item.targetKind, item.targetId),
        };
        for (final item in batch) {
          final key = (item.targetKind, item.targetId);
          if (seen.add(key)) {
            _items.add(item);
          }
        }
        _loadingMore = false;
        _nextCursor = batch.length >= _pageSize && batch.isNotEmpty
            ? batch.last.hiddenAt.toUtc().toIso8601String()
            : null;
      });
    } on Object {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _onShow(ConstellationFieldHiddenItem item) async {
    if (_showing) {
      return;
    }
    setState(() => _showing = true);
    final cubit = context.read<ConstellationCubit>();
    final ok = await cubit.showHiddenFieldItem(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _showing = false;
      if (ok) {
        _items.removeWhere(
          (row) =>
              row.targetKind == item.targetKind &&
              row.targetId == item.targetId,
        );
      }
    });
  }

  String _authorLabel(ConstellationCubit cubit, String authorId) {
    final field = cubit.state.field;
    if (field == null) {
      return authorId;
    }
    for (final peer in field.peers) {
      if (peer.id == authorId) {
        return peer.displayName ?? authorId;
      }
    }
    return authorId;
  }

  IconData _kindIcon(ConstellationFieldTargetKind kind) =>
      kind == ConstellationFieldTargetKind.post
      ? Icons.article_outlined
      : Icons.assignment_outlined;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final cubit = context.read<ConstellationCubit>();
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.85;

    Widget body;
    if (_loading) {
      body = const Center(child: TenturaCircularProgress());
    } else if (_loadError != null) {
      body = TenturaEmptyState(
        icon: Icons.error_outline,
        title: l10n.errorGenericAction,
      );
    } else if (_items.isEmpty) {
      body = TenturaEmptyState(
        icon: Icons.visibility_off_outlined,
        title: l10n.constellationHiddenByYouEmpty,
      );
    } else {
      body = ListView.separated(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.tightGap,
          tt.screenHPadding,
          media.padding.bottom + tt.rowGap,
        ),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => SizedBox(height: tt.tightGap),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Center(child: TenturaCircularProgress());
          }
          final item = _items[index];
          final hiddenLabel = l10n.constellationHiddenByYouHiddenOn(
            dateFormatDay(item.hiddenAt, locale: l10n.localeName),
          );
          return Card(
            child: Padding(
              padding: tt.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _kindIcon(item.targetKind),
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item.title,
                          style: TenturaText.bodyMedium(tt.text),
                        ),
                        SizedBox(height: tt.tightGap / 2),
                        Text(
                          _authorLabel(cubit, item.authorId),
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                        SizedBox(height: tt.tightGap / 2),
                        Text(
                          hiddenLabel,
                          style: TenturaText.bodySmall(tt.textFaint),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: tt.tightGap),
                  FilledButton.tonal(
                    key: TestIds.key(TestIds.constellationHiddenByYouShow),
                    onPressed: _showing ? null : () => unawaited(_onShow(item)),
                    child: Text(l10n.constellationHiddenByYouShow),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: Text(
              l10n.constellationHiddenByYouTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(height: tt.tightGap),
          Expanded(child: body),
        ],
      ),
    );
  }
}
