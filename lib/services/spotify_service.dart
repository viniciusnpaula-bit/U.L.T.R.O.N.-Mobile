import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SpotifyTrackItem {
  const SpotifyTrackItem({
    required this.id,
    required this.uri,
    required this.name,
    required this.artist,
    this.album = '',
    this.durationMs = 0,
  });

  factory SpotifyTrackItem.fromJson(Map<String, dynamic> map) {
    final artists = map['artists'];
    var artistNames = '';
    if (artists is List) {
      artistNames = artists
          .whereType<Map>()
          .map((a) => '${a['name'] ?? ''}'.trim())
          .where((n) => n.isNotEmpty)
          .join(', ');
    }
    final albumObj = map['album'];
    final albumName =
        albumObj is Map ? '${albumObj['name'] ?? ''}'.trim() : '';
    final id = '${map['id'] ?? ''}'.trim();
    final rawUri = '${map['uri'] ?? ''}'.trim();
    return SpotifyTrackItem(
      id: id,
      uri: rawUri.isNotEmpty ? rawUri : (id.isEmpty ? '' : 'spotify:track:$id'),
      name: '${map['name'] ?? 'Faixa'}'.trim(),
      artist: artistNames.isEmpty ? 'Artista' : artistNames,
      album: albumName,
      durationMs: (map['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String uri;
  final String name;
  final String artist;
  final String album;
  final int durationMs;

  String get durationLabel {
    if (durationMs <= 0) return '';
    final totalSecs = durationMs ~/ 1000;
    final m = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final s = (totalSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String formatLine() {
    final dur = durationLabel.isEmpty ? '' : ' [$durationLabel]';
    final alb = album.isEmpty ? '' : ' • $album';
    return '• $name — $artist$alb$dur ($uri)';
  }
}

class SpotifyPlaybackState {
  const SpotifyPlaybackState({
    required this.isPlaying,
    this.track,
    this.progressMs = 0,
    this.deviceName = '',
    this.deviceType = '',
    this.volumePercent,
  });

  factory SpotifyPlaybackState.fromJson(Map<String, dynamic> map) {
    final item = map['item'];
    final device = map['device'];
    return SpotifyPlaybackState(
      isPlaying: map['is_playing'] == true,
      track: item is Map<String, dynamic>
          ? SpotifyTrackItem.fromJson(item)
          : null,
      progressMs: (map['progress_ms'] as num?)?.toInt() ?? 0,
      deviceName: device is Map ? '${device['name'] ?? ''}'.trim() : '',
      deviceType: device is Map ? '${device['type'] ?? ''}'.trim() : '',
      volumePercent:
          device is Map ? (device['volume_percent'] as num?)?.toInt() : null,
    );
  }

  final bool isPlaying;
  final SpotifyTrackItem? track;
  final int progressMs;
  final String deviceName;
  final String deviceType;
  final int? volumePercent;

  static String _formatMs(int ms) {
    final secs = (ms.clamp(0, 36000000)) ~/ 1000;
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get progressLabel {
    final total = track?.durationMs ?? 0;
    if (total <= 0) return _formatMs(progressMs);
    return '${_formatMs(progressMs)} / ${_formatMs(total)}';
  }

  String formatSummary() {
    if (track == null) {
      return '🎵 Spotify: Nenhuma faixa ativa no momento.';
    }
    final stateIcon = isPlaying ? '▶️ Tocando' : '⏸️ Pausado';
    final dev = deviceName.isEmpty
        ? 'Dispositivo padrão'
        : '$deviceName${deviceType.isEmpty ? '' : ' ($deviceType)'}';
    final vol = volumePercent != null ? ' • Vol $volumePercent%' : '';
    return '🎵 SPOTIFY ($stateIcon):\n'
        '• Faixa: ${track!.name} — ${track!.artist}\n'
        '• Progresso: $progressLabel\n'
        '• Dispositivo: $dev$vol\n'
        '• URI: ${track!.uri}';
  }

  String get speakText {
    if (track == null) return 'Nenhuma música tocando no Spotify agora.';
    final verb = isPlaying ? 'Tocando' : 'Pausado em';
    final dev = deviceName.isEmpty ? '' : ' no dispositivo $deviceName';
    return '$verb ${track!.name}, de ${track!.artist}$dev.';
  }
}

class SpotifyPlaylistItem {
  const SpotifyPlaylistItem({
    required this.id,
    required this.uri,
    required this.name,
    this.tracksTotal = 0,
    this.ownerName = '',
  });

  factory SpotifyPlaylistItem.fromJson(Map<String, dynamic> map) {
    final tracks = map['tracks'];
    final total = tracks is Map ? (tracks['total'] as num?)?.toInt() ?? 0 : 0;
    final owner = map['owner'];
    final ownerLabel =
        owner is Map ? '${owner['display_name'] ?? ''}'.trim() : '';
    final id = '${map['id'] ?? ''}'.trim();
    final rawUri = '${map['uri'] ?? ''}'.trim();
    return SpotifyPlaylistItem(
      id: id,
      uri:
          rawUri.isNotEmpty ? rawUri : (id.isEmpty ? '' : 'spotify:playlist:$id'),
      name: '${map['name'] ?? 'Playlist'}'.trim(),
      tracksTotal: total,
      ownerName: ownerLabel,
    );
  }

  final String id;
  final String uri;
  final String name;
  final int tracksTotal;
  final String ownerName;

  String formatLine() =>
      '• $name ($tracksTotal faixas) [ID: $id]';
}

class SpotifyHttpResponse {
  const SpotifyHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef SpotifyHttpHandler = Future<SpotifyHttpResponse> Function(
  String method,
  Uri uri, {
  Map<String, String> headers,
  String? body,
});

/// Integração com a Spotify Web API utilizando OAuth 2.0 com PKCE (sem `client_secret` embutido).
///
/// Armazena de forma criptografada no [FlutterSecureStorage]:
/// - `spotify_client_id`
/// - `access_token`
/// - `refresh_token`
/// - `expires_at_ms`
/// - `pkce_code_verifier` / `pkce_state`
class SpotifyService {
  SpotifyService({
    FlutterSecureStorage? storage,
    SpotifyHttpHandler? httpHandler,
    DateTime Function()? now,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _httpHandler = httpHandler,
        _now = now ?? DateTime.now;

  final FlutterSecureStorage _storage;
  final SpotifyHttpHandler? _httpHandler;
  final DateTime Function() _now;

  static const redirectUri = 'ultron://spotify-callback';
  static const scopes = <String>[
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
    'playlist-read-private',
    'playlist-read-collaborative',
    'playlist-modify-public',
    'playlist-modify-private',
  ];

  // Chaves canônicas no FlutterSecureStorage
  static const clientIdStorageKey = 'spotify_client_id';
  static const accessTokenStorageKey = 'access_token';
  static const refreshTokenStorageKey = 'refresh_token';
  static const expiresAtStorageKey = 'ultron.spotify.expires_at_ms.v1';
  static const codeVerifierStorageKey = 'ultron.spotify.pkce_verifier.v1';
  static const oauthStateStorageKey = 'ultron.spotify.oauth_state.v1';

  Future<String> loadClientId() async =>
      (await _storage.read(key: clientIdStorageKey))?.trim() ?? '';

  Future<void> saveClientId(String clientId) async {
    final clean = clientId.trim();
    if (clean.isEmpty) {
      await _storage.delete(key: clientIdStorageKey);
    } else {
      await _storage.write(key: clientIdStorageKey, value: clean);
    }
  }

  Future<String> loadAccessToken() async =>
      (await _storage.read(key: accessTokenStorageKey))?.trim() ?? '';

  Future<String> loadRefreshToken() async =>
      (await _storage.read(key: refreshTokenStorageKey))?.trim() ?? '';

  Future<bool> isConnected() async {
    final clientId = await loadClientId();
    final access = await loadAccessToken();
    final refresh = await loadRefreshToken();
    return clientId.isNotEmpty && (access.isNotEmpty || refresh.isNotEmpty);
  }

  /// Mensagem amigável de degradação graciosa quando o Spotify não está configurado.
  String buildNotConfiguredMessage({bool hasDesktopPaired = false}) {
    final desktopHint = hasDesktopPaired
        ? '\n💡 Dica: Seu PC Desktop está pareado! Você também pode controlar a mídia do PC com `/pc midia play_pause` ou `[ACTION:PC_MEDIA:play_pause]`.'
        : '\n💡 Dica: Se estiver pareado com o U.L.T.R.O.N. Desktop via LAN (`/desktop`), você também pode controlar o player do PC.';
    return '🎵 Spotify Web API não conectado.\n'
        'Para ativar:\n'
        '1. Abra **Config IA** (`/settings`) → seção **Spotify Web API (OAuth 2.0 PKCE)**.\n'
        '2. Cole seu **Client ID** do Spotify Developer Dashboard (Redirect URI: `$redirectUri`).\n'
        '3. Toque em **Conectar Spotify**.$desktopHint';
  }

  /// Gera `code_verifier` PKCE criptograficamente seguro (RFC 7636, 64 chars URL-safe).
  static String generateCodeVerifier({Random? random}) {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = random ?? Random.secure();
    return List.generate(
      64,
      (_) => charset[rng.nextInt(charset.length)],
    ).join();
  }

  /// Calcula `code_challenge = BASE64URL-ENCODE(SHA256(ASCII(code_verifier)))` sem `=`.
  static String computeCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(ascii.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Inicia o fluxo OAuth 2.0 PKCE: gera e persiste `code_verifier` e `state`,
  /// retornando a URL de autorização `https://accounts.spotify.com/authorize?...`.
  Future<Uri> buildAuthorizationUri({
    String? clientIdOverride,
    String? codeVerifierOverride,
    String? stateOverride,
  }) async {
    final clientId = (clientIdOverride ?? await loadClientId()).trim();
    if (clientId.isEmpty) {
      throw StateError(
        'Informe o Client ID do Spotify antes de iniciar a conexão OAuth PKCE.',
      );
    }
    if (clientIdOverride != null && clientIdOverride.trim().isNotEmpty) {
      await saveClientId(clientId);
    }

    final verifier = codeVerifierOverride ?? generateCodeVerifier();
    final challenge = computeCodeChallenge(verifier);
    final state = stateOverride ?? generateCodeVerifier().substring(0, 16);

    await _storage.write(key: codeVerifierStorageKey, value: verifier);
    await _storage.write(key: oauthStateStorageKey, value: state);

    return Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
      'scope': scopes.join(' '),
    });
  }

  /// Processa o deep-link `ultron://spotify-callback?code=...&state=...` e troca o
  /// `code` por `access_token` e `refresh_token` usando o `code_verifier` PKCE.
  Future<bool> handleAuthorizationCallbackUri(String rawCallbackUri) async {
    final uri = Uri.tryParse(rawCallbackUri.trim());
    if (uri == null) {
      throw ArgumentError('Callback URI do Spotify inválido.');
    }
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      throw StateError('Autorização Spotify recusada: $error');
    }
    final code = uri.queryParameters['code']?.trim() ?? '';
    if (code.isEmpty) {
      throw ArgumentError('Código OAuth ausente no callback do Spotify.');
    }

    final expectedState =
        (await _storage.read(key: oauthStateStorageKey))?.trim() ?? '';
    final receivedState = uri.queryParameters['state']?.trim() ?? '';
    if (expectedState.isNotEmpty &&
        receivedState.isNotEmpty &&
        expectedState != receivedState) {
      throw StateError('Falha de validação de state OAuth no Spotify.');
    }

    final clientId = await loadClientId();
    final verifier =
        (await _storage.read(key: codeVerifierStorageKey))?.trim() ?? '';
    if (clientId.isEmpty || verifier.isEmpty) {
      throw StateError(
        'Client ID ou code_verifier PKCE ausente para concluir login Spotify.',
      );
    }

    final body = _encodeForm({
      'client_id': clientId,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': verifier,
    });

    final resp = await _request(
      'POST',
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'Falha ao trocar código OAuth PKCE no Spotify (HTTP ${resp.statusCode}).',
      );
    }

    await _saveTokenResponse(resp.body);
    await _storage.delete(key: codeVerifierStorageKey);
    await _storage.delete(key: oauthStateStorageKey);
    return true;
  }

  /// Renova o `access_token` usando o `refresh_token` via PKCE (sem `client_secret`).
  Future<String?> refreshAccessToken() async {
    final clientId = await loadClientId();
    final refresh = await loadRefreshToken();
    if (clientId.isEmpty || refresh.isEmpty) return null;

    final body = _encodeForm({
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    });

    final resp = await _request(
      'POST',
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }

    await _saveTokenResponse(resp.body);
    return loadAccessToken();
  }

  /// Remove tokens OAuth do armazenamento seguro.
  Future<void> disconnect({bool clearClientId = false}) async {
    await _storage.delete(key: accessTokenStorageKey);
    await _storage.delete(key: refreshTokenStorageKey);
    await _storage.delete(key: expiresAtStorageKey);
    await _storage.delete(key: codeVerifierStorageKey);
    await _storage.delete(key: oauthStateStorageKey);
    if (clearClientId) {
      await _storage.delete(key: clientIdStorageKey);
    }
  }

  /// 1. SPOTIFY_SEARCH (`[ACTION:SPOTIFY_SEARCH:query]`): Busca faixas no catálogo do Spotify.
  Future<List<SpotifyTrackItem>> searchTracks(
    String query, {
    int limit = 5,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      throw ArgumentError('Informe o termo para buscar no Spotify.');
    }
    final safeLimit = limit.clamp(1, 20);
    final uri = Uri.https('api.spotify.com', '/v1/search', {
      'q': clean,
      'type': 'track',
      'limit': '$safeLimit',
    });

    final resp = await _authenticatedRequest('GET', uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('Spotify search falhou (HTTP ${resp.statusCode}).');
    }
    return parseSearchTracksJson(resp.body);
  }

  static List<SpotifyTrackItem> parseSearchTracksJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) return const [];
    final tracksObj = decoded['tracks'];
    if (tracksObj is! Map) return const [];
    final items = tracksObj['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SpotifyTrackItem.fromJson)
        .toList();
  }

  /// 2. SPOTIFY_STATE (`[ACTION:SPOTIFY_STATE]`): Retorna faixa atual, artista, progresso e dispositivo ativo.
  Future<SpotifyPlaybackState> getPlaybackState() async {
    final uri = Uri.https('api.spotify.com', '/v1/me/player');
    final resp = await _authenticatedRequest('GET', uri);
    if (resp.statusCode == 204 || resp.body.trim().isEmpty) {
      return const SpotifyPlaybackState(isPlaying: false);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'Spotify player state falhou (HTTP ${resp.statusCode}).',
      );
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      return const SpotifyPlaybackState(isPlaying: false);
    }
    return SpotifyPlaybackState.fromJson(decoded);
  }

  /// 3. SPOTIFY_PLAY (`[ACTION:SPOTIFY_PLAY:uri_ou_busca]`): Inicia reprodução de uma URI
  /// (`spotify:track:...`, `spotify:playlist:...`, `spotify:album:...`) ou busca a primeira faixa correspondente.
  Future<String> play(String uriOrQuery) async {
    final clean = uriOrQuery.trim();
    final playUri = Uri.https('api.spotify.com', '/v1/me/player/play');

    if (clean.isEmpty) {
      // Apenas retoma reprodução atual
      final resp = await _authenticatedRequest('PUT', playUri, body: '{}');
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException(
          'Falha ao retomar reprodução no Spotify (HTTP ${resp.statusCode}).',
        );
      }
      return '▶️ Reprodução do Spotify retomada.';
    }

    String targetUri = clean;
    String displayLabel = clean;
    if (!clean.startsWith('spotify:')) {
      final hits = await searchTracks(clean, limit: 1);
      if (hits.isEmpty) {
        throw StateError('Nenhuma faixa encontrada no Spotify para "$clean".');
      }
      final track = hits.first;
      targetUri = track.uri;
      displayLabel = '${track.name} — ${track.artist}';
    }

    final Map<String, dynamic> payload = targetUri.startsWith('spotify:track:')
        ? {
            'uris': [targetUri],
          }
        : {
            'context_uri': targetUri,
          };

    final resp = await _authenticatedRequest(
      'PUT',
      playUri,
      body: jsonEncode(payload),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'Falha ao tocar "$displayLabel" no Spotify (HTTP ${resp.statusCode}).',
      );
    }
    return '🎵 Tocando no Spotify: $displayLabel';
  }

  /// 4. SPOTIFY_PLAYLISTS (`[ACTION:SPOTIFY_PLAYLISTS]`): Lista as playlists do usuário.
  Future<List<SpotifyPlaylistItem>> listUserPlaylists({int limit = 15}) async {
    final safeLimit = limit.clamp(1, 50);
    final uri = Uri.https('api.spotify.com', '/v1/me/playlists', {
      'limit': '$safeLimit',
    });
    final resp = await _authenticatedRequest('GET', uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'Falha ao listar playlists do Spotify (HTTP ${resp.statusCode}).',
      );
    }
    return parsePlaylistsJson(resp.body);
  }

  static List<SpotifyPlaylistItem> parsePlaylistsJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) return const [];
    final items = decoded['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SpotifyPlaylistItem.fromJson)
        .toList();
  }

  /// 5. SPOTIFY_ADD_PLAYLIST (`[ACTION:SPOTIFY_ADD_PLAYLIST:playlist_id_ou_nome|track_uri]`):
  /// Adiciona uma faixa (ou a faixa tocando no momento, caso [trackUriOrQuery] seja vazio) a uma playlist.
  Future<String> addTrackToPlaylist({
    required String playlistIdOrName,
    String trackUriOrQuery = '',
  }) async {
    final cleanPlaylist = playlistIdOrName.trim();
    if (cleanPlaylist.isEmpty) {
      throw ArgumentError('Informe o nome ou ID da playlist do Spotify.');
    }

    // Resolve playlist por ID ou nome
    String resolvedPlaylistId = cleanPlaylist;
    String resolvedPlaylistName = cleanPlaylist;
    if (cleanPlaylist.startsWith('spotify:playlist:')) {
      resolvedPlaylistId =
          cleanPlaylist.substring('spotify:playlist:'.length).trim();
    } else {
      final playlists = await listUserPlaylists(limit: 30);
      final qLower = cleanPlaylist.toLowerCase();
      for (final pl in playlists) {
        if (pl.id == cleanPlaylist || pl.name.toLowerCase() == qLower) {
          resolvedPlaylistId = pl.id;
          resolvedPlaylistName = pl.name;
          break;
        }
      }
      if (resolvedPlaylistId == cleanPlaylist) {
        for (final pl in playlists) {
          if (pl.name.toLowerCase().contains(qLower)) {
            resolvedPlaylistId = pl.id;
            resolvedPlaylistName = pl.name;
            break;
          }
        }
      }
    }

    // Resolve track URI: usa a faixa tocando atualmente se vazio
    var cleanTrack = trackUriOrQuery.trim();
    var trackLabel = cleanTrack;
    if (cleanTrack.isEmpty) {
      final state = await getPlaybackState();
      if (state.track == null || state.track!.uri.isEmpty) {
        throw StateError(
          'Nenhuma faixa tocando no momento para adicionar à playlist.',
        );
      }
      cleanTrack = state.track!.uri;
      trackLabel = '${state.track!.name} — ${state.track!.artist}';
    } else if (!cleanTrack.startsWith('spotify:track:')) {
      final hits = await searchTracks(cleanTrack, limit: 1);
      if (hits.isEmpty) {
        throw StateError(
          'Nenhuma faixa encontrada no Spotify para "$cleanTrack".',
        );
      }
      cleanTrack = hits.first.uri;
      trackLabel = '${hits.first.name} — ${hits.first.artist}';
    }

    final uri = Uri.https(
      'api.spotify.com',
      '/v1/playlists/$resolvedPlaylistId/tracks',
    );
    final resp = await _authenticatedRequest(
      'POST',
      uri,
      body: jsonEncode({
        'uris': [cleanTrack],
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
        'Falha ao adicionar faixa à playlist (HTTP ${resp.statusCode}).',
      );
    }
    return '➕ Adicionado "$trackLabel" à playlist "$resolvedPlaylistName".';
  }

  Future<SpotifyHttpResponse> _authenticatedRequest(
    String method,
    Uri uri, {
    String? body,
  }) async {
    var token = await _getValidAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError(buildNotConfiguredMessage());
    }

    var resp = await _request(
      method,
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed != null && refreshed.isNotEmpty) {
        token = refreshed;
        resp = await _request(
          method,
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body,
        );
      }
    }
    return resp;
  }

  Future<String?> _getValidAccessToken() async {
    final access = await loadAccessToken();
    final expiresRaw = await _storage.read(key: expiresAtStorageKey);
    final expiresMs = int.tryParse(expiresRaw ?? '');
    final nowMs = _now().millisecondsSinceEpoch;

    if (access.isNotEmpty &&
        (expiresMs == null || nowMs + 30000 < expiresMs)) {
      return access;
    }
    final refreshed = await refreshAccessToken();
    if (refreshed != null && refreshed.isNotEmpty) {
      return refreshed;
    }
    return access.isNotEmpty ? access : null;
  }

  Future<void> _saveTokenResponse(String rawBody) async {
    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Resposta OAuth do Spotify inválida.');
    }
    final access = '${decoded['access_token'] ?? ''}'.trim();
    final refresh = '${decoded['refresh_token'] ?? ''}'.trim();
    final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 3600;

    if (access.isEmpty) {
      throw const FormatException('access_token ausente na resposta do Spotify.');
    }
    await _storage.write(key: accessTokenStorageKey, value: access);
    if (refresh.isNotEmpty) {
      await _storage.write(key: refreshTokenStorageKey, value: refresh);
    }
    final expiresAtMs = _now().millisecondsSinceEpoch + expiresIn * 1000;
    await _storage.write(
      key: expiresAtStorageKey,
      value: expiresAtMs.toString(),
    );
  }

  Future<SpotifyHttpResponse> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (_httpHandler != null) {
      return _httpHandler(method, uri, headers: headers, body: body);
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .openUrl(method.toUpperCase(), uri)
          .timeout(const Duration(seconds: 7));
      req.headers.set('User-Agent', 'ULTRON-Mobile/1.5');
      for (final entry in headers.entries) {
        req.headers.set(entry.key, entry.value);
      }
      if (body != null && body.isNotEmpty) {
        final bytes = utf8.encode(body);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final resp = await req.close().timeout(const Duration(seconds: 7));
      final respBody = await utf8.decoder
          .bind(resp)
          .join()
          .timeout(const Duration(seconds: 6));
      return SpotifyHttpResponse(
        statusCode: resp.statusCode,
        body: respBody,
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _encodeForm(Map<String, String> params) => params.entries
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
}
