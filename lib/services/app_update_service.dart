import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.downloadUrl, required this.name});
  final String version, downloadUrl, name;
}

class AppUpdateService {
  static const repository = 'viniciusnpaula-bit/U.L.T.R.O.N.-Mobile';
  static const releaseApi = 'https://api.github.com/repos/$repository/releases/latest';

  Future<UpdateInfo?> check() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(releaseApi)).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('GitHub respondeu HTTP ${response.statusCode}.');
      }
      final release = jsonDecode(body) as Map<String, dynamic>;
      if (release['draft'] == true || release['prerelease'] == true) return null;
      final assets = (release['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
      final apk = assets.where((asset) => (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')).firstOrNull;
      if (apk == null || (apk['browser_download_url'] as String? ?? '').isEmpty) return null;
      return UpdateInfo(
        version: (release['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), ''),
        name: (apk['name'] ?? 'ultron-update.apk').toString(),
        downloadUrl: apk['browser_download_url'].toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> downloadAndInstall(UpdateInfo update, void Function(double) onProgress) async {
    final uri = Uri.parse(update.downloadUrl);
    if (uri.scheme != 'https' || uri.host != 'github.com' && !uri.host.endsWith('githubusercontent.com')) {
      throw const FormatException('URL de atualização não confiável.');
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/ultron-update.apk');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Download HTTP ${response.statusCode}.');
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      if (await file.length() < 1024 * 1024) throw const FormatException('APK baixado parece incompleto.');
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) throw Exception(result.message);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
