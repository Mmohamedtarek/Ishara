import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ishara_app/core/logging/log.dart';

/// Reads one bundled asset (`rootBundle.load` in the app).
typedef AssetReader = Future<Uint8List> Function(String assetPath);

/// Serves the avatar page and its files from the app's assets on
/// `http://127.0.0.1:<port>/<token>/…`, so the page's ES modules load (they
/// don't from `file://`). Nothing leaves the phone.
///
/// Locked down: loopback only, a random port and a random 128-bit path
/// token, GET/HEAD only, the `Host` header must be this server, and only
/// files under `avatar/` and `packs/<lang>/avatar/` with known types.
class AvatarAssetServer {
  new _(this._server, this._token, this._read) {
    _sub = _server.listen(_handle);
  }

  static final _log = Log('avatar_server');

  /// Starts on a free loopback port.
  static Future<AvatarAssetServer> start(
    AssetReader read, {
    Random? random,
  }) async {
    final rnd = random ?? Random.secure();
    final token = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    return AvatarAssetServer._(server, token, read);
  }

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'glb': 'model/gltf-binary',
  };

  /// Paths (below the token) that may be served.
  static final _allowed = RegExp(
    r'^(avatar/[A-Za-z0-9_./-]+|packs/[a-z]+/avatar/[A-Za-z0-9_.-]+)$',
  );

  final HttpServer _server;
  final String _token;
  final AssetReader _read;
  late final StreamSubscription<HttpRequest> _sub;

  int get port => _server.port;

  /// The page the WebView opens.
  Uri get pageUri => Uri.parse('$origin/$_token/avatar/index.html');

  String get origin => 'http://127.0.0.1:$port';

  /// Page-relative URL of [assetPath] (`assets/…`), for the `init` command.
  String pageRelative(String assetPath) {
    if (!assetPath.startsWith('assets/')) {
      throw ArgumentError.value(assetPath, 'assetPath', 'not under assets/');
    }
    return '../${assetPath.substring('assets/'.length)}';
  }

  /// Whether [url] is a page of this server (navigation guard).
  bool owns(String url) => url.startsWith('$origin/$_token/');

  Future<void> close() async {
    await _sub.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = _assetPath(req);
      if (path == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final Uint8List bytes;
      try {
        bytes = await _read('assets/$path');
      } on Exception {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      res.headers
        ..contentType = ContentType.parse(_types[path.split('.').last]!)
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Referrer-Policy', 'no-referrer')
        ..contentLength = bytes.length;
      if (req.method == 'GET') res.add(bytes);
    } on Object catch (e) {
      _log.warn('serve_failed', {'message': e.toString()});
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      try {
        await res.close();
      } on Object {
        // The WebView went away mid-response; nothing to do.
      }
    }
  }

  /// The asset path a request may read, or null (→ 404).
  String? _assetPath(HttpRequest req) {
    if (req.method != 'GET' && req.method != 'HEAD') return null;
    if (req.headers.host != '127.0.0.1' || req.headers.port != port) {
      return null;
    }
    final seg = req.uri.pathSegments;
    if (seg.length < 2 || seg.first != _token) return null;
    final rest = seg.skip(1);
    // Decoded segments: an encoded "/" or a leading "." would let a path
    // leave the allowed folders.
    if (rest.any(
      (s) =>
          s.isEmpty || s.startsWith('.') || s.contains('/') || s.contains(r'\'),
    )) {
      return null;
    }
    final path = rest.join('/');
    if (!_allowed.hasMatch(path)) return null;
    final ext = path.contains('.') ? path.split('.').last : '';
    return _types.containsKey(ext) ? path : null;
  }
}
