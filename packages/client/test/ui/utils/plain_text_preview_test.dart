import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/util/plain_text_preview.dart';

void main() {
  group('stripAngleBracketRegionsForPlainPreview', () {
    test('removes pseudo-markup tags while keeping surrounding words', () {
      expect(
        stripAngleBracketRegionsForPlainPreview(
          r'before <b>bold</b> after',
        ),
        'before bold after',
      );
    });

    test('removes script-like angle regions (inner text stays plain)', () {
      expect(
        stripAngleBracketRegionsForPlainPreview(
          r'x <script>alert(1)</script> y',
        ),
        'x alert(1) y',
      );
    });

    test('preserves standalone < and > (comparisons, arrows)', () {
      expect(stripAngleBracketRegionsForPlainPreview('a < b'), 'a < b');
      expect(stripAngleBracketRegionsForPlainPreview('->'), '->');
      expect(stripAngleBracketRegionsForPlainPreview('≤ 3'), '≤ 3');
    });

    test('preserves unicode and ordinary text', () {
      expect(
        stripAngleBracketRegionsForPlainPreview('مرحبا plain 测试'),
        'مرحبا plain 测试',
      );
    });

    test('does not treat multiline angle junk as one tag', () {
      expect(
        stripAngleBracketRegionsForPlainPreview('a <b\nc> d'),
        'a <b c> d',
      );
    });
  });
}
