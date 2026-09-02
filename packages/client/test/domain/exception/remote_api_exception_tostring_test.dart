import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/exception/generic_exception.dart';

void main() {
  test('RemoteApiException.toString exposes message for Sentry', () {
    const error = RemoteApiException('field "beacon" not found');
    expect(error.toString(), 'field "beacon" not found');
  });
}
