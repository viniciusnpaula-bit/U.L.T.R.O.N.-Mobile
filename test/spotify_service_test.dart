import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/spotify_service.dart';

void main() {
  late _MemorySecureStorage storage;
  late DateTime currentNow;

  setUp(() {
    storage = _MemorySecureStorage();
    currentNow = DateTime(2026, 11, 22, 21, 0);
  });

  test(
      'builds OAuth 2.0 PKCE authorization URI and exchanges callback code for tokens',
      () async {
    String? postedBody;
    final spotify = SpotifyService(
      storage: storage,
      now: () => currentNow,
      httpHandler: (method, uri, {headers = const {}, body}) async {
        expect(method, 'POST');
        expect(uri.toString(), 'https://accounts.spotify.com/api/token');
        postedBody = body;
        return SpotifyHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'access_token': 'acc_pkce_123',
            'refresh_token': 'ref_pkce_456',
            'expires_in': 3600,
          }),
        );
      },
    );

    final authUri = await spotify.buildAuthorizationUri(
      clientIdOverride: 'client_abc_123',
      codeVerifierOverride:
          'verifier_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN',
      stateOverride: 'state_xyz',
    );
    expect(authUri.host, 'accounts.spotify.com');
    expect(authUri.queryParameters['client_id'], 'client_abc_123');
    expect(authUri.queryParameters['redirect_uri'],
        'ultron://spotify-callback');
    expect(authUri.queryParameters['code_challenge_method'], 'S256');
    expect(authUri.queryParameters['code_challenge'], isNotEmpty);

    final ok = await spotify.handleAuthorizationCallbackUri(
      'ultron://spotify-callback?code=auth_code_999&state=state_xyz',
    );
    expect(ok, isTrue);
    expect(postedBody, contains('grant_type=authorization_code'));
    expect(postedBody, contains('code=auth_code_999'));
    expect(postedBody, contains('code_verifier=verifier_'));
    expect(await spotify.loadAccessToken(), 'acc_pkce_123');
    expect(await spotify.loadRefreshToken(), 'ref_pkce_456');
    expect(await spotify.isConnected(), isTrue);
  });

  test('automatically refreshes expired access_token or 401 response via PKCE',
      () async {
    await storage.write(
        key: SpotifyService.clientIdStorageKey, value: 'client_id_test');
    await storage.write(
        key: SpotifyService.accessTokenStorageKey, value: 'expired_token');
    await storage.write(
        key: SpotifyService.refreshTokenStorageKey, value: 'valid_refresh_tok');
    // Expired 10 minutes ago
    await storage.write(
      key: SpotifyService.expiresAtStorageKey,
      value: currentNow
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch
          .toString(),
    );

    var refreshCalls = 0;
    String? usedBearer;

    final spotify = SpotifyService(
      storage: storage,
      now: () => currentNow,
      httpHandler: (method, uri, {headers = const {}, body}) async {
        if (uri.host == 'accounts.spotify.com' && uri.path == '/api/token') {
          refreshCalls++;
          expect(body, contains('grant_type=refresh_token'));
          expect(body, contains('refresh_token=valid_refresh_tok'));
          return SpotifyHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'access_token': 'fresh_token_789',
              'expires_in': 3600,
            }),
          );
        }
        usedBearer = headers['Authorization'];
        return SpotifyHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'is_playing': true,
            'progress_ms': 65000,
            'device': {
              'name': 'Galaxy A34 5G',
              'type': 'Smartphone',
              'volume_percent': 80,
            },
            'item': {
              'id': 'trk_1',
              'uri': 'spotify:track:trk_1',
              'name': 'Veridis Quo',
              'duration_ms': 345000,
              'artists': [
                {'name': 'Daft Punk'},
              ],
              'album': {'name': 'Discovery'},
            },
          }),
        );
      },
    );

    final state = await spotify.getPlaybackState();
    expect(refreshCalls, 1);
    expect(usedBearer, 'Bearer fresh_token_789');
    expect(state.isPlaying, isTrue);
    expect(state.track?.name, 'Veridis Quo');
    expect(state.track?.artist, 'Daft Punk');
    expect(state.deviceName, 'Galaxy A34 5G');
    expect(state.progressLabel, '01:05 / 05:45');
  });

  test(
      'parses tracks, playlists, plays track by search, and adds current track to playlist',
      () async {
    await storage.write(
        key: SpotifyService.clientIdStorageKey, value: 'client_id_test');
    await storage.write(
        key: SpotifyService.accessTokenStorageKey, value: 'active_token');
    await storage.write(
      key: SpotifyService.expiresAtStorageKey,
      value: currentNow
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch
          .toString(),
    );

    final requests = <String>[];
    final spotify = SpotifyService(
      storage: storage,
      now: () => currentNow,
      httpHandler: (method, uri, {headers = const {}, body}) async {
        requests.add('$method ${uri.path}');
        if (uri.path == '/v1/search') {
          return SpotifyHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'tracks': {
                'items': [
                  {
                    'id': 'starboy_1',
                    'uri': 'spotify:track:starboy_1',
                    'name': 'Starboy',
                    'duration_ms': 230000,
                    'artists': [
                      {'name': 'The Weeknd'},
                      {'name': 'Daft Punk'},
                    ],
                    'album': {'name': 'Starboy'},
                  },
                ],
              },
            }),
          );
        }
        if (uri.path == '/v1/me/player/play') {
          expect(body, contains('spotify:track:starboy_1'));
          return const SpotifyHttpResponse(statusCode: 204, body: '');
        }
        if (uri.path == '/v1/me/playlists') {
          return SpotifyHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'items': [
                {
                  'id': 'pl_treino',
                  'uri': 'spotify:playlist:pl_treino',
                  'name': 'Treino Tático',
                  'tracks': {'total': 42},
                  'owner': {'display_name': 'Operador'},
                },
              ],
            }),
          );
        }
        if (uri.path == '/v1/me/player') {
          return SpotifyHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'is_playing': true,
              'progress_ms': 12000,
              'item': {
                'id': 'starboy_1',
                'uri': 'spotify:track:starboy_1',
                'name': 'Starboy',
                'duration_ms': 230000,
                'artists': [
                  {'name': 'The Weeknd'},
                ],
              },
            }),
          );
        }
        if (uri.path == '/v1/playlists/pl_treino/tracks') {
          expect(body, contains('spotify:track:starboy_1'));
          return const SpotifyHttpResponse(
            statusCode: 201,
            body: '{"snapshot_id":"snap_1"}',
          );
        }
        return const SpotifyHttpResponse(statusCode: 404, body: '');
      },
    );

    // 1. Search tracks
    final tracks = await spotify.searchTracks('Starboy');
    expect(tracks.length, 1);
    expect(tracks.single.artist, 'The Weeknd, Daft Punk');

    // 2. Play by search query
    final playMsg = await spotify.play('Starboy');
    expect(playMsg, contains('Tocando no Spotify: Starboy'));

    // 3. List playlists
    final playlists = await spotify.listUserPlaylists();
    expect(playlists.length, 1);
    expect(playlists.single.name, 'Treino Tático');
    expect(playlists.single.tracksTotal, 42);

    // 4. Add currently playing track (empty trackUriOrQuery) to playlist by name
    final addMsg = await spotify.addTrackToPlaylist(
      playlistIdOrName: 'Treino Tático',
    );
    expect(addMsg, contains('Adicionado "Starboy'));
    expect(addMsg, contains('Treino Tático'));
  });

  test(
      'degrades gracefully with clear instructions when Spotify OAuth is not configured',
      () async {
    final unconfiguredSpotify = SpotifyService(storage: storage);
    expect(await unconfiguredSpotify.isConnected(), isFalse);

    final service = DeviceControlService(
      storage: storage,
      spotifyProvider: () => unconfiguredSpotify,
    );

    final natRes =
        await service.tryExecuteNaturalCommand('tocar Daft Punk no spotify');
    expect(natRes?.handled, isTrue);
    expect(natRes?.message, contains('Spotify Web API não conectado'));
    expect(natRes?.message, contains('ultron://spotify-callback'));

    final aiRes = await service.executeAiActions(
      '[ACTION:SPOTIFY_STATE] [ACTION:SPOTIFY_PLAYLISTS]',
    );
    expect(aiRes.executedLogs.length, 2);
    expect(
        aiRes.executedLogs.first, contains('Spotify Web API não conectado'));
  });
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}
