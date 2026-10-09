@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_icon_data.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';

import '../support/kit.dart';

const _res = 'android/app/src/main/res';
const _xca = 'ios/Runner/Assets.xcassets';

/// Every app icon and native launch image the platforms show.
List<File> _iconFiles() => [
  for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'])
    File('$_res/mipmap-$d/ic_launcher.png'),
  for (final dir in ['$_xca/AppIcon.appiconset', '$_xca/LaunchImage.imageset'])
    for (final f in Directory(dir).listSync())
      if (f is File && f.path.endsWith('.png')) f,
];

String _hex(Color c) {
  final rgb = (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${rgb.toUpperCase()}';
}

/// PNG colour type (2 = RGB, 6 = RGBA) and size.
(int, int, int) _png(Uint8List b) {
  final d = ByteData.sublistView(b);
  return (d.getUint32(16), d.getUint32(20), b[25]);
}

void main() {
  test("no app icon or launch image is Flutter's template image", () {
    final template = {
      for (final l in readText(
        'test/fixtures/flutter_template_icon_hashes.txt',
      ).split('\n'))
        if (l.trim().isNotEmpty && !l.startsWith('#')) l.trim(),
    };
    expect(template, hasLength(greaterThan(20)));
    final files = _iconFiles();
    expect(files, hasLength(greaterThanOrEqualTo(5 + 15 + 3)));
    for (final f in files) {
      expect(
        template,
        isNot(contains(sha256.convert(f.readAsBytesSync()).toString())),
        reason: "${f.path} is Flutter's template image",
      );
    }
  });

  test('the one vector source is the prototype mark (and the app widget)', () {
    final svg = readText('brand/ishara_mark.svg');
    // gradient = IsharaMark.gradient (135°, stops 0 / .55 / 1)
    const offsets = ['0', '0.55', '1'];
    expect(IsharaMark.gradient.stops, [0, .55, 1]);
    for (final (i, c) in IsharaMark.gradient.colors.indexed) {
      expect(svg, contains('offset="${offsets[i]}" stop-color="${_hex(c)}"'));
    }
    expect(svg, contains('rx="26"'));
    expect(svg, contains('stroke-width="2.4"'));
    // the hand = the prototype's ICONS.logo paths
    final logo = isharaIconSvg['logo']!;
    final paths = RegExp('<path d="([^"]+)"/>')
        .allMatches(logo)
        .map((m) => m[1]);
    expect(paths, hasLength(4));
    for (final d in paths) {
      expect(svg, contains('<path d="$d"/>'));
    }
  });

  test('Android: adaptive icon (with monochrome), legacy icons, launch', () {
    final adaptive = readText('$_res/mipmap-anydpi-v26/ic_launcher.xml');
    for (final layer in ['background', 'foreground', 'monochrome']) {
      expect(adaptive, contains('@drawable/ic_launcher_$layer'));
      expect(
        File('$_res/drawable/ic_launcher_$layer.xml').existsSync(),
        isTrue,
      );
    }
    for (final (d, px) in [
      ('mdpi', 48),
      ('hdpi', 72),
      ('xhdpi', 96),
      ('xxhdpi', 144),
      ('xxxhdpi', 192),
    ]) {
      final (w, h, _) = _png(
        File('$_res/mipmap-$d/ic_launcher.png').readAsBytesSync(),
      );
      expect((w, h), (px, px), reason: d);
    }
    // launch background = prototype --bg, light and dark; no white flash
    expect(
      readText('$_res/values/colors.xml'),
      contains(_hex(IsharaColors.light.bg)),
    );
    expect(
      readText('$_res/values-night/colors.xml'),
      contains(_hex(IsharaColors.dark.bg)),
    );
    for (final night in ['', '-night']) {
      final styles = readText('$_res/values$night/styles.xml');
      expect(styles, contains('@drawable/launch_background'));
      expect(
        styles,
        contains(
          '<item name="android:windowBackground">@color/ishara_bg</item>',
        ),
      );
      final v31 = readText('$_res/values$night-v31/styles.xml');
      expect(v31, contains('windowSplashScreenBackground">@color/ishara_bg'));
      expect(
        v31,
        contains('windowSplashScreenAnimatedIcon">@drawable/splash_icon'),
      );
    }
    for (final f in ['drawable', 'drawable-v21']) {
      final lb = readText('$_res/$f/launch_background.xml');
      expect(lb, contains('@color/ishara_bg'));
      expect(lb, contains('@drawable/launch_mark'));
      expect(lb, isNot(contains('white')));
    }
  });

  test('iOS: every AppIcon size exists, opaque; launch screen = bg + mark', () {
    final contents = jsonDecode(
      readText('$_xca/AppIcon.appiconset/Contents.json'),
    ) as Map<String, dynamic>;
    for (final img
        in (contents['images'] as List).cast<Map<String, dynamic>>()) {
      final f = File('$_xca/AppIcon.appiconset/${img['filename']}');
      final (w, h, type) = _png(f.readAsBytesSync());
      final pts = double.parse((img['size'] as String).split('x').first);
      final scale = int.parse((img['scale'] as String).replaceAll('x', ''));
      expect(
        (w, h),
        ((pts * scale).round(), (pts * scale).round()),
        reason: f.path,
      );
      expect(type, 2, reason: '${f.path}: iOS icons must have no alpha');
    }
    final story = readText('ios/Runner/Base.lproj/LaunchScreen.storyboard');
    expect(
      story,
      contains('<color key="backgroundColor" name="LaunchBackground"/>'),
    );
    expect(story, contains('image="LaunchImage"'));
    final colors = readText('$_xca/LaunchBackground.colorset/Contents.json');
    String comp(Color c) => '"red": "0x${_hex(c).substring(1, 3)}"';
    expect(colors, contains(comp(IsharaColors.light.bg)));
    expect(colors, contains(comp(IsharaColors.dark.bg)));
    expect(colors, contains('"value": "dark"'));
  });
}
