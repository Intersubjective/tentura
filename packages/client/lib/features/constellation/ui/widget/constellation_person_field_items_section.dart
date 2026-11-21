import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/util/ui_utils.dart';

import '../../domain/entity/constellation_field_target_kind.dart';
import '../../domain/entity/constellation_person_field_item.dart';
import '../../domain/use_case/constellation_person_field_items_case.dart';
import '../bloc/constellation_cubit.dart';

/// Server-backed Requests and Posts for the Field person panel (#255 l9k5.10).
class ConstellationPersonFieldItemsSection extends StatefulWidget {
  const ConstellationPersonFieldItemsSection({
    required this.personId,
    super.key,
  });

  final String personId;

  @visibleForTesting
  static Key personItemUnreadGlowKey(String beaconId) =>
      Key('constellation.person_items.row.glow.$beaconId');

  @override
  State<ConstellationPersonFieldItemsSection> createState() =>
      _ConstellationPersonFieldItemsSectionState();
}

class _ConstellationPersonFieldItemsSectionState
    extends State<ConstellationPersonFieldItemsSection> {
  static const _debounce = Duration(milliseconds: 300);

  var _bucket = ConstellationPersonFieldBucket.active;
  final _search = TextEditingController();
  Timer? _debounceTimer;
  var _query = '';
  var _loading = false;
  var _loadingMore = false;
  Object? _error;
  var _items = <ConstellationPersonFieldItem>[];
  String? _nextCursor;
  var _counts = const ConstellationPersonFieldCounts(
    active: 0,
    closed: 0,
    hidden: 0,
  );
  var _initialized = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      unawaited(_reload(reset: true));
    }
  }

  @override
  void didUpdateWidget(ConstellationPersonFieldItemsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personId != widget.personId) {
      unawaited(_reload(reset: true));
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      final next = _search.text.trim();
      if (next == _query) {
        return;
      }
      _query = next;
      unawaited(_reload(reset: true));
    });
  }

  ConstellationPersonFieldItemsCase? get _case =>
      context.read<ConstellationCubit>().personFieldItemsCase;

  Future<void> _reload({required bool reset}) async {
    final case_ = _case;
    if (case_ == null || !mounted) {
      return;
    }
    setState(() {
      _loading = reset;
      _loadingMore = !reset;
      _error = null;
      if (reset) {
        _items = [];
        _nextCursor = null;
      }
    });
    try {
      final page = await case_.fetch(
        personId: widget.personId,
        bucket: _bucket,
        query: _query,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _counts = page.counts;
        _nextCursor = page.nextCursor;
        _items = reset ? page.items : [..._items, ...page.items];
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error;
        if (reset) {
          _items = [];
        }
      });
    }
  }

  void _onTabChanged(int index) {
    final bucket = ConstellationPersonFieldBucket.values[index];
    if (bucket == _bucket) {
      return;
    }
    setState(() => _bucket = bucket);
    unawaited(_reload(reset: true));
  }

  Future<void> _openItem(ConstellationPersonFieldItem item) async {
    context.read<ConstellationCubit>()
      ..openedFieldBeacon(item.id)
      ..selectPerson(null)
      ..selectRequest(item.id);
  }

  Future<void> _toggleHidden(ConstellationPersonFieldItem item) async {
    final cubit = context.read<ConstellationCubit>();
    final hiddenTab = _bucket == ConstellationPersonFieldBucket.hidden;
    final ok = hiddenTab
        ? await cubit.showAgainBeaconFromPersonPanel(
            targetKind: item.kind,
            beaconId: item.id,
            title: item.label,
            authorId: item.authorId,
          )
        : await cubit.hideBeaconFromPersonPanel(
            targetKind: item.kind,
            beaconId: item.id,
          );
    if (!mounted || !ok) {
      return;
    }
    await _reload(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final tabIndex = ConstellationPersonFieldBucket.values.indexOf(_bucket);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TenturaUnderlineTabs(
          key: const Key('constellation.person_items.tabs'),
          tabs: [
            l10n.constellationPersonItemsActive,
            l10n.constellationPersonItemsClosed,
            l10n.constellationPersonItemsHidden,
          ],
          selectedIndex: tabIndex,
          onChanged: _onTabChanged,
          badges: [_counts.active, _counts.closed, _counts.hidden],
          countStyle: TenturaTabCountStyle.plainText,
          tabIds: const [
            'constellation.person_items.tab.active',
            'constellation.person_items.tab.closed',
            'constellation.person_items.tab.hidden',
          ],
        ),
        SizedBox(height: tt.rowGap),
        SearchBar(
          key: TestIds.key(TestIds.constellationPersonItemsSearch),
          controller: _search,
          hintText: l10n.constellationPersonItemsSearchHint,
          leading: const Icon(Icons.search),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: l10n.constellationSearchClear,
                onPressed: () {
                  _search.clear();
                  _query = '';
                  unawaited(_reload(reset: true));
                },
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        SizedBox(height: tt.rowGap),
        if (_loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: tt.rowGap),
            child: const Center(child: TenturaCircularProgress()),
          )
        else if (_error != null)
          Text(
            l10n.errorGenericAction,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (_items.isEmpty)
          Text(
            l10n.constellationPersonItemsEmpty,
            key: const Key('constellation.person_items.empty'),
            style: theme.textTheme.bodySmall,
          )
        else
          for (final item in _items)
            Padding(
              padding: EdgeInsets.only(bottom: tt.tightGap),
              child: _PersonFieldItemRow(
                item: item,
                showAgain: _bucket == ConstellationPersonFieldBucket.hidden,
                onOpen: () => unawaited(_openItem(item)),
                onToggleHidden: () => unawaited(_toggleHidden(item)),
              ),
            ),
        if (!_loading && _nextCursor != null) ...[
          SizedBox(height: tt.tightGap),
          OutlinedButton(
            key: TestIds.key(TestIds.constellationPersonItemsLoadMore),
            onPressed: _loadingMore
                ? null
                : () => unawaited(_reload(reset: false)),
            child: _loadingMore
                ? const TenturaCircularProgress()
                : Text(l10n.constellationPersonItemsLoadMore),
          ),
        ],
      ],
    );
  }
}

class _PersonFieldItemRow extends StatelessWidget {
  const _PersonFieldItemRow({
    required this.item,
    required this.showAgain,
    required this.onOpen,
    required this.onToggleHidden,
  });

  final ConstellationPersonFieldItem item;
  final bool showAgain;
  final VoidCallback onOpen;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final isUnread = context.select<ConstellationCubit, bool>(
      (cubit) => cubit.unreadFieldBeaconIds().contains(item.id),
    );
    final icon = item.kind == ConstellationFieldTargetKind.post
        ? Icons.article_outlined
        : Icons.assignment_outlined;

    final surfaceColor = theme.colorScheme.surfaceContainerLow;
    final fillColor = isUnread
        ? Color.alphaBlend(
            tt.attentionHighlight.withValues(alpha: 0.08),
            surfaceColor,
          )
        : surfaceColor;

    return Material(
      key: isUnread
          ? ConstellationPersonFieldItemsSection.personItemUnreadGlowKey(
              item.id,
            )
          : null,
      color: fillColor,
      elevation: isUnread ? 3 : 0,
      shadowColor: isUnread
          ? tt.attentionHighlight.withValues(alpha: 0.45)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: Padding(
          padding: tt.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: tt.iconSize),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.label,
                      key: Key('constellation.person_items.row.${item.id}'),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: tt.tightGap),
                    Text(
                      dateFormatDay(
                        item.lastActivityAt,
                        locale: l10n.localeName,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tt.tightGap),
              TenturaTextAction(
                label: showAgain
                    ? l10n.constellationShowAgain
                    : l10n.constellationHideFromField,
                onPressed: onToggleHidden,
                minInteractive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
