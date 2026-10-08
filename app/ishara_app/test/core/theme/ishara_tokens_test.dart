// Every colour token must equal the prototype CSS variable it comes from.
// Reads design/prototype.html directly, so a design change makes this fail.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:path/path.dart' as p;

Map<String, String> _vars(String block) => {
  for (final m in RegExp(r'--([\w-]+):\s*([^;]+);').allMatches(block))
    m.group(1)!: m.group(2)!.trim(),
};

Color _css(String v) {
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(v);
  if (hex != null) return Color(int.parse('FF${hex.group(1)}', radix: 16));
  final rgba = RegExp(r'^rgba\((\d+),(\d+),(\d+),([\d.]+)\)$').firstMatch(v);
  if (rgba != null) {
    final a = (double.parse(rgba.group(4)!) * 255).round();
    return Color.fromARGB(
      a,
      int.parse(rgba.group(1)!),
      int.parse(rgba.group(2)!),
      int.parse(rgba.group(3)!),
    );
  }
  if (v == '#fff') return const Color(0xFFFFFFFF);
  throw FormatException('unsupported CSS colour', v);
}

Map<String, Color> _tokens(IsharaColors c) => {
  'bg': c.bg,
  'bg2': c.bg2,
  'ink': c.ink,
  'sub': c.sub,
  'muted': c.muted,
  'teal': c.teal,
  'teal-soft': c.tealSoft,
  'violet': c.violet,
  'violet-soft': c.violetSoft,
  'amber': c.amber,
  'amber-soft': c.amberSoft,
  'danger': c.danger,
  'ok': c.ok,
  'ok-soft': c.okSoft,
  'glass': c.glass,
  'glass2': c.glass2,
  'line': c.line,
  'stage-a': c.stageA,
  'stage-b': c.stageB,
  'stage-c': c.stageC,
  'panel': c.panel,
  'panel-soft': c.panelSoft,
  'bar': c.bar,
  'bar2': c.bar2,
  'bar2s': c.bar2s,
  'knob': c.knob,
  'input': c.input,
  'hover': c.hover,
  'shadow': c.shadow,
  'track': c.track,
  'ring': c.ring,
};

void main() {
  final html = File(
    p.join(Directory.current.path, '..', '..', 'design', 'prototype.html'),
  ).readAsStringSync();
  final css = html.substring(0, html.indexOf('</style>'));
  final dark = _vars(css.substring(css.indexOf(':root{'), css.indexOf('}')));
  final lightStart = css.indexOf(
    '.stage[data-theme=light],.desk[data-theme=light]{',
  );
  final light = {
    ...dark,
    ..._vars(css.substring(lightStart, css.indexOf('}', lightStart))),
  };

  for (final (name, vars, colors) in [
    ('dark', dark, IsharaColors.dark),
    ('light', light, IsharaColors.light),
  ]) {
    test('$name tokens equal the prototype CSS', () {
      for (final e in _tokens(colors).entries) {
        expect(e.value, _css(vars[e.key]!), reason: '--${e.key} ($name)');
      }
    });
  }

  test('high contrast = .stage.hc (muted -> sub, line -> ring, 2 px)', () {
    for (final c in [IsharaColors.dark, IsharaColors.light]) {
      final hc = c.highContrast();
      expect(hc.muted, c.sub);
      expect(hc.line, c.ring);
      expect(hc.borderWidth, 2);
      expect(hc.ink, c.ink);
      expect(c.borderWidth, 1);
    }
    expect(css, contains('.stage.hc{--muted:var(--sub);--line:var(--ring);}'));
  });

  test('copyWith overrides any token and keeps the rest', () {
    const c = IsharaColors.dark;
    final x = c.copyWith(teal: const Color(0xFF000001), borderWidth: 3);
    expect(x.teal, const Color(0xFF000001));
    expect(x.borderWidth, 3);
    expect(_tokens(x)..remove('teal'), _tokens(c)..remove('teal'));
    expect(c.copyWith().primaryGradient, c.primaryGradient);
  });

  test('lerp snaps at the midpoint (no colour animation)', () {
    const a = IsharaColors.dark;
    const b = IsharaColors.light;
    expect(a.lerp(b, .4), same(a));
    expect(a.lerp(b, .6), same(b));
    expect(a.lerp(null, .9), same(a));
  });

  test('gradients follow the theme', () {
    expect(IsharaColors.dark.primary.colors, IsharaColors.dark.primaryGradient);
    expect(
      IsharaColors.light.violetButton.colors.first,
      const Color(0xFF3446C9),
    );
    expect(IsharaColors.brandGradient.stops, [0, .55, 1]);
  });
}
