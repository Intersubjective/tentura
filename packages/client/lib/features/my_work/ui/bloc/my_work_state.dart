import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'my_work_state.freezed.dart';

enum MyWorkFilter { all, authored, committed }

enum MyWorkSection { drafts, active, review, closed }

@freezed
abstract class MyWorkState extends StateBase with _$MyWorkState {
  const factory MyWorkState({
    @Default('') String context,
    @Default([]) List<Beacon> authoredDrafts,
    @Default([]) List<Beacon> authoredActive,
    @Default([]) List<Beacon> authoredReview,
    @Default([]) List<Beacon> authoredClosed,
    @Default([]) List<Beacon> committedDrafts,
    @Default([]) List<Beacon> committedActive,
    @Default([]) List<Beacon> committedReview,
    @Default([]) List<Beacon> committedClosed,
    /// Closed-tab counts before full closed rows are loaded (from `MyWorkInit` id lists).
    @Default([]) List<String> authoredClosedIdHints,
    @Default([]) List<String> committedClosedIdHints,
    @Default(false) bool closedDataFetched,
    @Default(false) bool closedFetchInProgress,
    @Default(MyWorkSection.active) MyWorkSection section,
    @Default(MyWorkFilter.all) MyWorkFilter filter,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _MyWorkState;

  const MyWorkState._();

  List<Beacon> _authoredList(MyWorkSection s) => switch (s) {
        MyWorkSection.drafts => authoredDrafts,
        MyWorkSection.active => authoredActive,
        MyWorkSection.review => authoredReview,
        MyWorkSection.closed => authoredClosed,
      };

  List<Beacon> _committedList(MyWorkSection s) => switch (s) {
        MyWorkSection.drafts => committedDrafts,
        MyWorkSection.active => committedActive,
        MyWorkSection.review => committedReview,
        MyWorkSection.closed => committedClosed,
      };

  /// Beacons for [s] with explicit [f] (dedupes committed vs authored for All).
  List<Beacon> visibleBeaconsForSectionAndFilter(MyWorkSection s, MyWorkFilter f) {
    final authored = _authoredList(s);
    final committed = _committedList(s);
    return switch (f) {
      MyWorkFilter.all => [
        ...authored,
        ...committed.where((c) => !authored.any((a) => a.id == c.id)),
      ],
      MyWorkFilter.authored => authored,
      MyWorkFilter.committed => committed,
    };
  }

  /// Beacons visible for [section] with the current [filter] (dedupes committed vs authored for All).
  List<Beacon> visibleBeaconsForSection(MyWorkSection section) =>
      visibleBeaconsForSectionAndFilter(section, filter);

  /// Main list: on Drafts tab, always merged All (filter chips hidden); elsewhere respects [filter].
  List<Beacon> get visibleBeacons => section == MyWorkSection.drafts
      ? visibleBeaconsForSectionAndFilter(
          MyWorkSection.drafts,
          MyWorkFilter.all,
        )
      : visibleBeaconsForSectionAndFilter(section, filter);

  int _closedCountFromHints() => switch (filter) {
        MyWorkFilter.authored => authoredClosedIdHints.length,
        MyWorkFilter.committed => committedClosedIdHints.length,
        MyWorkFilter.all =>
          authoredClosedIdHints.length +
              committedClosedIdHints
                  .where((id) => !authoredClosedIdHints.contains(id))
                  .length,
      };

  /// Count for a section chip; matches list semantics except closed before lazy fetch uses id hints.
  int countForSection(MyWorkSection s) {
    if (s == MyWorkSection.closed && !closedDataFetched) {
      return _closedCountFromHints();
    }
    final f = s == MyWorkSection.drafts && section == MyWorkSection.drafts
        ? MyWorkFilter.all
        : filter;
    return visibleBeaconsForSectionAndFilter(s, f).length;
  }

  /// [BeaconTile.isMine]: correct for merged Drafts and for All on other tabs.
  bool tileIsMine(Beacon beacon) {
    if (section == MyWorkSection.drafts) {
      return authoredDrafts.any((a) => a.id == beacon.id);
    }
    return switch (filter) {
      MyWorkFilter.committed => false,
      MyWorkFilter.authored => true,
      MyWorkFilter.all =>
        _authoredList(section).any((a) => a.id == beacon.id),
    };
  }
}
