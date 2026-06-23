import 'package:test/test.dart';

import 'package:tentura_server/consts/user_handle_consts.dart';

void main() {
  group('isValidUserHandleFormat', () {
    test('accepts valid lowercase handles', () {
      expect(isValidUserHandleFormat('abc'), isTrue);
      expect(isValidUserHandleFormat('alice_smith'), isTrue);
      expect(isValidUserHandleFormat('a' * kUserHandleMaxLength), isTrue);
    });

    test('rejects too short handles', () {
      expect(isValidUserHandleFormat('ab'), isFalse);
      expect(isValidUserHandleFormat(''), isFalse);
    });

    test('rejects invalid characters and uppercase', () {
      expect(isValidUserHandleFormat('Alice'), isFalse);
      expect(isValidUserHandleFormat('user-name'), isFalse);
      expect(isValidUserHandleFormat('user name'), isFalse);
    });

    test('rejects handles longer than max length', () {
      expect(isValidUserHandleFormat('a' * (kUserHandleMaxLength + 1)), isFalse);
    });
  });
}
