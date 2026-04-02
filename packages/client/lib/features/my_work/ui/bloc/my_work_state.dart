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

  /// Beacons visible for [section] with the current [filter] (dedupes committed vs authored for All).
  List<Beacon> visibleBeaconsForSection(MyWorkSection section) {
    final authored = _authoredList(section);
    final committed = _committedList(section);
    return switch (filter) {
      MyWorkFilter.all => [
        ...authored,
        ...committed.where((c) => !authored.any((a) => a.id == c.id)),
      ],
      MyWorkFilter.authored => authored,
      MyWorkFilter.committed => committed,
    };
  }

  List<Beacon> get visibleBeacons => visibleBeaconsForSection(section);

  int _closedCountFromHints() => switch (filter) {
        MyWorkFilter.authored => authoredClosedIdHints.length,
        MyWorkFilter.committed => committedClosedIdHints.length,
        MyWorkFilter.all =>
          authoredClosedIdHints.length +
              committedClosedIdHints
                  .where((id) => !authoredClosedIdHints.contains(id))
                  .length,
      };

  /// Count for a section chip; matches [visibleBeaconsForSection] except closed before lazy fetch uses id hints.
  int countForSection(MyWorkSection s) {
    if (s == MyWorkSection.closed && !closedDataFetched) {
      return _closedCountFromHints();
    }
    return visibleBeaconsForSection(s).length;
  }
}
