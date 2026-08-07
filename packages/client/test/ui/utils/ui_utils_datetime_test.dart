import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('dateFormatYMD/timeFormatHm always render viewer-local time', () {
    final utcInstant = DateTime.utc(2026, 6, 20, 23, 30);
    final local = utcInstant.toLocal();
    expect(dateFormatYMD(utcInstant), DateFormat.yMd().format(local));
    expect(timeFormatHm(utcInstant), DateFormat.Hm().format(local));
  });

  test('null input is empty string', () {
    expect(dateFormatYMD(null), '');
    expect(timeFormatHm(null), '');
  });
}
