import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/core/security/pin_vault.dart';

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pbkdf2 PBKDF2-HMAC-SHA256', () {
    // Known vectors: PBKDF2-HMAC-SHA256("password", "salt", c, 32).
    const expected1 =
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b';
    const expected2 =
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43';

    test('matches the published test vectors', () {
      final password = utf8.encode('password');
      final salt = utf8.encode('salt');
      expect(hex(pbkdf2(password, salt, 1, 32)), expected1);
      expect(hex(pbkdf2(password, salt, 2, 32)), expected2);
    });

    test('depends on the salt and stays deterministic otherwise', () {
      final password = utf8.encode('1234');
      final a = pbkdf2(password, utf8.encode('salt-a'), 10, 32);
      final b = pbkdf2(password, utf8.encode('salt-b'), 10, 32);
      final again = pbkdf2(password, utf8.encode('salt-a'), 10, 32);
      expect(a, isNot(equals(b)));
      expect(a, equals(again));
      expect(a.length, 32);
    });
  });
}
