import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/app_update_service.dart';

void main() {
  group('AppUpdateService download URL validation', () {
    test('accepts HTTPS GitHub and GitHub asset hosts', () {
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('https://github.com/a/b/releases/download/v1/app.apk')), isTrue);
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('https://objects.githubusercontent.com/a.apk')), isTrue);
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('https://release-assets.githubusercontent.com/a.apk')), isTrue);
    });

    test('rejects HTTP, lookalike and unrelated hosts', () {
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('http://github.com/a.apk')), isFalse);
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('https://evilgithubusercontent.com/a.apk')), isFalse);
      expect(AppUpdateService.isTrustedDownloadUri(Uri.parse('https://example.com/a.apk')), isFalse);
    });
  });
}
