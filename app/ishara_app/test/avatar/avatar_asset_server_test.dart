@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_asset_server.dart';

void main() {
  late AvatarAssetServer server;
  late HttpClient client;
  final reads = <String>[];

  Future<Uint8List> read(String path) async {
    reads.add(path);
    final f = File(path);
    if (!f.existsSync()) throw const FileSystemException('missing');
    return await f.readAsBytes();
  }

  setUp(() async {
    reads.clear();
    server = await AvatarAssetServer.start(read, random: Random(1));
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  String token() => server.pageUri.pathSegments.first;

  Future<HttpClientResponse> get(
    String path, {
    String method = 'GET',
    String? host,
  }) async {
    final req = await client.openUrl(
      method,
      Uri.parse('${server.origin}$path'),
    );
    if (host != null) req.headers.host = host;
    return await req.close();
  }

  test('the page and its files are served with the right types', () async {
    expect(server.pageUri.host, '127.0.0.1');
    expect(token(), hasLength(32));
    expect(server.pageUri.path, '/${token()}/avatar/index.html');
    for (final (path, type) in [
      ('avatar/index.html', 'text/html'),
      ('avatar/engine.js', 'text/javascript'),
      ('avatar/style.css', 'text/css'),
      ('avatar/cast.json', 'application/json'),
      ('avatar/three/build/three.module.js', 'text/javascript'),
      ('avatar/characters/nour.glb', 'model/gltf-binary'),
      ('packs/asl/avatar/library.json', 'application/json'),
    ]) {
      final res = await get('/${token()}/$path');
      expect(res.statusCode, 200, reason: path);
      expect(res.headers.contentType!.mimeType, type, reason: path);
      expect(res.headers.value('x-content-type-options'), 'nosniff');
      expect(res.headers.value('cache-control'), 'no-store');
      final body = await res.fold<int>(0, (n, c) => n + c.length);
      expect(body, File('assets/$path').lengthSync(), reason: path);
    }
    final head = await get('/${token()}/avatar/index.html', method: 'HEAD');
    expect(head.statusCode, 200);
    expect(await head.fold<int>(0, (n, c) => n + c.length), 0);
  });

  test('everything else is 404, without touching the assets', () async {
    final t = token();
    for (final path in [
      '/avatar/index.html', // no token
      '/0000/avatar/index.html', // wrong token
      '/$t/avatar/../packs/asl/signs.json', // traversal (normalized away)
      '/$t/avatar/%2e%2e/pubspec.yaml',
      '/$t/packs/asl/signs.json', // outside the avatar folders
      '/$t/packs/asl/kit/model/labels.txt',
      '/$t/avatar/three/LICENSE', // no served type
      '/$t/avatar/notes.txt',
      '/$t/fonts/Figtree-400.ttf',
      '/$t/',
      '/$t//avatar/index.html',
      // encoded "/" or "\\" inside one segment, dot-files
      '/$t/avatar/x%2F..%2F..%2Fpacks%2Fasl%2Fsigns.json',
      '/$t/avatar/x%5C..%5Cindex.html',
      '/$t/avatar/.hidden.js',
      '/$t/avatar/%2e%2e%2fpubspec.json',
    ]) {
      final res = await get(path);
      expect(res.statusCode, 404, reason: path);
      await res.drain<void>();
    }
    expect(reads, isEmpty);
    final post = await get('/$t/avatar/index.html', method: 'POST');
    expect(post.statusCode, 404);
    await post.drain<void>();
  });

  test('a request for another host is refused (DNS rebinding)', () async {
    final res = await get(
      '/${token()}/avatar/index.html',
      host: 'evil.example',
    );
    expect(res.statusCode, 404);
    await res.drain<void>();
  });

  test('a missing asset is 404', () async {
    final res = await get('/${token()}/avatar/missing.js');
    expect(res.statusCode, 404);
    await res.drain<void>();
    expect(reads, ['assets/avatar/missing.js']);
  });

  test('URLs: page-relative asset paths and the navigation guard', () {
    expect(
      server.pageRelative('assets/packs/asl/avatar/library.json'),
      '../packs/asl/avatar/library.json',
    );
    expect(
      server.pageRelative('assets/avatar/cast.json'),
      '../avatar/cast.json',
    );
    expect(() => server.pageRelative('lib/x'), throwsArgumentError);
    expect(server.owns(server.pageUri.toString()), isTrue);
    expect(server.owns('${server.origin}/other/avatar/index.html'), isFalse);
    expect(server.owns('https://example.com/'), isFalse);
    expect(server.owns('about:blank'), isFalse);
  });

  test('the token is random per start', () async {
    final other = await AvatarAssetServer.start(read);
    addTearDown(other.close);
    expect(other.pageUri.pathSegments.first, isNot(token()));
    expect(other.port, isNot(server.port));
  });
}
