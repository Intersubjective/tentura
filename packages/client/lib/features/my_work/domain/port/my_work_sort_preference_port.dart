import '../entity/my_work_sort.dart';

/// The My Work sort order saved on this device (implemented in the data
/// layer), so a reload comes back to the order the user last chose (#431).
abstract class MyWorkSortPreferencePort {
  /// The saved order, or null when nothing (usable) is saved on this device.
  Future<MyWorkSort?> getSort();

  Future<void> setSort(MyWorkSort sort);
}
