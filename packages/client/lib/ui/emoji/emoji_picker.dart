import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'package:tentura/ui/emoji/emoji_catalog.dart';
import 'package:tentura/ui/emoji/emoji_recents.dart';

const double _kCellExtent = 44;
const double _kSectionHeaderHeight = 32;
const double _kPopoverWidth = 352;
const double _kPopoverHeight = 420;

/// Composer emoji button. Opens the picker as a bottom sheet on compact
/// windows (stays open for several picks, like phone messengers) and as a
/// popover above the button elsewhere (closes after a pick, like Slack).
class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({
    required this.onPick,
    this.onClosed,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<String> onPick;

  /// Called after the picker closes, e.g. to return focus to the composer.
  final VoidCallback? onClosed;

  final bool enabled;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final _popover = OverlayPortalController();
  final _link = LayerLink();
  final _tapGroup = Object();

  void _pick(String emoji) {
    EmojiRecents.add(emoji);
    widget.onPick(emoji);
  }

  Future<void> _open() async {
    if (context.windowClass == WindowClass.compact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.5,
            child: EmojiPickerPanel(onPick: _pick),
          ),
        ),
      );
      widget.onClosed?.call();
      return;
    }
    if (_popover.isShowing) {
      _closePopover();
    } else {
      _popover.show();
    }
  }

  void _closePopover() {
    if (!_popover.isShowing) return;
    _popover.hide();
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return OverlayPortal(
      controller: _popover,
      overlayChildBuilder: _buildPopover,
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _tapGroup,
          child: Semantics(
            identifier: TestIds.roomEmojiButton,
            button: true,
            child: IconButton(
              key: TestIds.key(TestIds.roomEmojiButton),
              tooltip: l10n.composerEmojiButtonTooltip,
              onPressed: widget.enabled ? _open : null,
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    final tt = context.tt;
    final viewport = MediaQuery.sizeOf(context);
    final height = math.min(_kPopoverHeight, viewport.height * 0.6);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(0, -tt.tightGap),
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _closePopover(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _closePopover,
            },
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: math.min(_kPopoverWidth, viewport.width),
                height: height,
                child: EmojiPickerPanel(
                  autofocusSearch: true,
                  onPick: (emoji) {
                    _pick(emoji);
                    _closePopover();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Searchable emoji grid with recents and category jump bar.
class EmojiPickerPanel extends StatefulWidget {
  const EmojiPickerPanel({
    required this.onPick,
    this.autofocusSearch = false,
    super.key,
  });

  final ValueChanged<String> onPick;

  final bool autofocusSearch;

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

/// One picker section; `category` is `null` for recently used emoji.
typedef _Section = ({EmojiCategory? category, List<EmojiEntry> entries});

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Section> _sections;
  var _columns = 1;
  var _activeSection = 0;

  @override
  void initState() {
    super.initState();
    final recents = [
      for (final emoji in EmojiRecents.value)
        ?EmojiCatalog.byEmoji(emoji),
    ];
    _sections = [
      if (recents.isNotEmpty) (category: null, entries: recents),
      for (final category in EmojiCategory.values)
        (category: category, entries: EmojiCatalog.byCategory[category]!),
    ];
    _search.addListener(() => setState(() {}));
    _scroll.addListener(_syncActiveSection);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  double _sectionOffset(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      final rows = (_sections[i].entries.length / _columns).ceil();
      offset += _kSectionHeaderHeight + rows * _kCellExtent;
    }
    return offset;
  }

  void _syncActiveSection() {
    if (!_scroll.hasClients) return;
    final position = _scroll.offset + 1;
    var active = 0;
    for (var i = 0; i < _sections.length; i++) {
      if (_sectionOffset(i) <= position) active = i;
    }
    if (active != _activeSection) setState(() => _activeSection = active);
  }

  void _jumpTo(int sectionIndex) {
    if (_search.text.isNotEmpty) _search.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(
        math.min(
          _sectionOffset(sectionIndex),
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final query = _search.text.trim();
    final results = query.isEmpty ? null : EmojiCatalog.search(query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            tt.cardGap,
            tt.cardGap,
            tt.cardGap,
            tt.tightGap,
          ),
          child: Semantics(
            identifier: TestIds.emojiPickerSearch,
            textField: true,
            child: TextField(
              key: TestIds.key(TestIds.emojiPickerSearch),
              controller: _search,
              autofocus: widget.autofocusSearch,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                final first = results?.firstOrNull;
                if (first != null) widget.onPick(first.emoji);
              },
              decoration: InputDecoration(
                hintText: l10n.emojiPickerSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(TenturaRadii.searchBar),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
          child: Row(
            children: [
              for (var i = 0; i < _sections.length; i++)
                _CategoryTab(
                  category: _sections[i].category,
                  selected: results == null && i == _activeSection,
                  onTap: () => _jumpTo(i),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth - 2 * tt.tightGap;
              _columns = math.max(1, (width / _kCellExtent).floor());
              final padding = EdgeInsets.symmetric(horizontal: tt.tightGap);
              if (results != null) {
                if (results.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.emojiPickerNoResults,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return CustomScrollView(
                  key: const ValueKey('emoji-search-results'),
                  slivers: [
                    SliverPadding(
                      padding: padding.copyWith(top: tt.tightGap),
                      sliver: _grid(results),
                    ),
                  ],
                );
              }
              return CustomScrollView(
                controller: _scroll,
                slivers: [
                  for (final section in _sections) ...[
                    SliverPadding(
                      padding: padding,
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          height: _kSectionHeaderHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _categoryLabel(l10n, section.category),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: padding,
                      sliver: _grid(section.entries),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _grid(List<EmojiEntry> entries) => SliverGrid(
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _columns,
      mainAxisExtent: _kCellExtent,
    ),
    delegate: SliverChildBuilderDelegate(
      (context, index) => _EmojiCell(
        entry: entries[index],
        onTap: () => widget.onPick(entries[index].emoji),
      ),
      childCount: entries.length,
    ),
  );
}

String _categoryLabel(L10n l10n, EmojiCategory? category) => switch (category) {
  null => l10n.emojiCategoryRecent,
  EmojiCategory.smileys => l10n.emojiCategorySmileys,
  EmojiCategory.people => l10n.emojiCategoryPeople,
  EmojiCategory.nature => l10n.emojiCategoryNature,
  EmojiCategory.food => l10n.emojiCategoryFood,
  EmojiCategory.travel => l10n.emojiCategoryTravel,
  EmojiCategory.activities => l10n.emojiCategoryActivities,
  EmojiCategory.objects => l10n.emojiCategoryObjects,
  EmojiCategory.symbols => l10n.emojiCategorySymbols,
  EmojiCategory.flags => l10n.emojiCategoryFlags,
};

IconData _categoryIcon(EmojiCategory? category) => switch (category) {
  null => Icons.history_rounded,
  EmojiCategory.smileys => Icons.emoji_emotions_outlined,
  EmojiCategory.people => Icons.emoji_people_outlined,
  EmojiCategory.nature => Icons.emoji_nature_outlined,
  EmojiCategory.food => Icons.emoji_food_beverage_outlined,
  EmojiCategory.travel => Icons.emoji_transportation_outlined,
  EmojiCategory.activities => Icons.emoji_events_outlined,
  EmojiCategory.objects => Icons.emoji_objects_outlined,
  EmojiCategory.symbols => Icons.emoji_symbols_outlined,
  EmojiCategory.flags => Icons.emoji_flags_outlined,
};

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final EmojiCategory? category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: _categoryLabel(L10n.of(context)!, category),
      isSelected: selected,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(
        _categoryIcon(category),
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell({required this.entry, required this.onTap});

  final EmojiEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shortcode = ':${entry.shortcode}:';
    return Tooltip(
      message: shortcode,
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Semantics(
        identifier: TestIds.emojiPickerCell(entry.shortcode),
        button: true,
        label: '${entry.emoji} $shortcode',
        excludeSemantics: true,
        child: InkWell(
          key: TestIds.key(TestIds.emojiPickerCell(entry.shortcode)),
          borderRadius: BorderRadius.circular(context.tt.buttonRadius),
          onTap: onTap,
          child: Center(
            child: Text(
              entry.emoji,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }
}
