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

  group('AppUpdateService version comparison', () {
    test('only offers a higher version', () {
      expect(AppUpdateService.isNewer('0.2.1', '0.2.0'), isTrue);
      expect(AppUpdateService.isNewer('0.3.0', '0.2.9'), isTrue);
      expect(AppUpdateService.isNewer('1.0.0', '0.99.99'), isTrue);
    });

    test('does not offer the installed or an older version', () {
      expect(AppUpdateService.isNewer('0.2.0', '0.2.0'), isFalse);
      expect(AppUpdateService.isNewer('0.1.9', '0.2.0'), isFalse);
    });

    test('ignores the v prefix and the build number suffix', () {
      expect(AppUpdateService.isNewer('v0.2.1', '0.2.0'), isTrue);
      expect(AppUpdateService.isNewer('0.2.0+7', '0.2.0'), isFalse);
      expect(AppUpdateService.isNewer('0.2.1+3', '0.2.0+9'), isTrue);
    });
  });
}
