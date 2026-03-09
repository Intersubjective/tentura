import 'package:test/test.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';

void main() {
  group('JwtEntity.validate', () {
    // A valid subject ID must be kIdLength characters long, start with 'U',
    // and the rest must be hexadecimal characters.
    // We construct a valid ID based on kIdLength for robust testing.
    final validHexPart = 'a' * (kIdLength - 1);
    final validSub = 'U$validHexPart';

    test('should not throw when sub is valid', () {
      // Arrange
      final jwt = JwtEntity(sub: validSub);

      // Act & Assert
      expect(jwt.validate, returnsNormally);
    });

    test('should throw IdWrongException for incorrect length (too short)', () {
      // Arrange
      const jwt = JwtEntity(sub: 'U12345');

      // Act & Assert
      expect(
        jwt.validate,
        throwsA(isA<IdWrongException>()),
      );
    });

    test('should throw IdWrongException for incorrect length (too long)', () {
      // Arrange
      final jwt = JwtEntity(sub: 'U${'a' * kIdLength}');

      // Act & Assert
      expect(
        jwt.validate,
        throwsA(isA<IdWrongException>()),
      );
    });

    test('should throw IdWrongException for missing "U" prefix', () {
      // Arrange
      final jwt = JwtEntity(sub: 'X$validHexPart');
      // Act & Assert
      expect(jwt.validate, throwsA(isA<IdWrongException>()));
    });

    test('should throw IdWrongException for non-hex characters', () {
      // Arrange
      // Replace the last character with a non-hex 'g'.
      final invalidHexPart = '${'a' * (kIdLength - 2)}g';
      final jwt = JwtEntity(sub: 'U$invalidHexPart');
      // Act & Assert
      expect(jwt.validate, throwsA(isA<IdWrongException>()));
    });
  });
}
