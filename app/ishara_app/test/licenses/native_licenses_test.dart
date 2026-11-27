import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/licenses/native_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(LicenseRegistry.reset);

  test('every notice file is listed, and every listed file exists', () {
    final onDisk = {
      for (final f in Directory('assets/licenses').listSync())
        f.uri.pathSegments.last,
    };
    expect({for (final n in nativeNotices) n.file}, onDisk);
  });

  test('Android: Moonshine, EgypTalk, sherpa-onnx, ONNX Runtime and their '
      'libraries', () async {
    LicenseRegistry.reset();
    registerNativeLicenses(platform: TargetPlatform.android);
    final entries = await LicenseRegistry.licenses.toList();
    final packages = {for (final e in entries) ...e.packages};
    expect(
      packages,
      containsAll([
        'Moonshine Voice',
        'ONNX Runtime',
        'Eigen',
        'kaldi-native-fbank',
        'KISS FFT',
        'JSON for Modern C++',
        'UTF8-CPP',
        'utf8proc',
        'EgypTalk-ASR-v2 Egyptian Arabic model',
        'sherpa-onnx',
        'kaldi-decoder',
        'simple-sentencepiece',
        'kaldifst',
        'kaldi-hmm-gmm',
        'kaldi_native_io',
        'OpenFst',
        'hclust-cpp',
      ]),
    );
    final texts = [
      for (final e in entries) e.paragraphs.map((p) => p.text).join('\n'),
    ];
    expect(texts, everyElement(isNotEmpty));
    expect(
      texts.firstWhere((t) => t.startsWith('Eigen')),
      contains('Mozilla Public License'),
    );
    // CC BY 4.0 (TV-24): credit, licence link, and the change made
    final egyptalk = texts.firstWhere((t) => t.startsWith('EgypTalk-ASR-v2'));
    expect(egyptalk, contains('NAMAA-Space'));
    expect(
      egyptalk,
      contains('https://huggingface.co/NAMAA-Space/EgypTalk-ASR-v2'),
    );
    expect(egyptalk, contains('https://creativecommons.org/licenses/by/4.0/'));
    expect(egyptalk, contains('quantized to int8'));
    expect(egyptalk, contains('NVIDIA'));
  });

  test(
    'other platforms add nothing (they ship no Moonshine or sherpa-onnx)',
    () async {
      LicenseRegistry.reset();
      registerNativeLicenses(platform: TargetPlatform.iOS);
      expect(await LicenseRegistry.licenses.toList(), isEmpty);
    },
  );

  test('the texts are read from the bundle', () async {
    final entries = await nativeLicenses(rootBundle).toList();
    expect(entries, hasLength(nativeNotices.length));
  });
}
