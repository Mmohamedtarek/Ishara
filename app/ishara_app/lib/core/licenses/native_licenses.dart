import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One notice on the licences page: the components it covers, an optional
/// lead line, and its text in `assets/licenses/`.
typedef NativeNotice = ({List<String> packages, String lead, String file});

/// Native code in the Android app that pub doesn't know about: Moonshine
/// 0.1.6 and its model, the libraries built into `libmoonshine.so`
/// (Moonshine's `core/third-party`) and ONNX Runtime 1.23.2 (DECISIONS
/// TV-21); EgypTalk-ASR-v2, sherpa-onnx 2.0.3, the libraries built into
/// `libsherpa-onnx-jni.so` and its ONNX Runtime 1.28.2 (TV-24). Licence
/// texts are the upstream ones, at the versions built in. Firebase's
/// Android libraries (step 10b): the open-source ones with their full texts,
/// Google's own by name, version and terms.
const List<NativeNotice> nativeNotices = [
  (
    packages: ['Moonshine Voice', 'Moonshine Small streaming English model'],
    lead: '',
    file: 'moonshine.txt',
  ),
  (
    packages: ['EgypTalk-ASR-v2 Egyptian Arabic model'],
    lead: '',
    file: 'egyptalk_asr_v2.txt',
  ),
  (packages: ['ONNX Runtime'], lead: '', file: 'onnxruntime.txt'),
  (
    packages: ['ONNX Runtime'],
    lead: 'ONNX Runtime 1.23.2 (in Moonshine).',
    file: 'onnxruntime_third_party_notices.txt',
  ),
  (
    packages: ['ONNX Runtime'],
    lead:
        'ONNX Runtime 1.28.2 (built into sherpa-onnx). These notices are '
        'those of the ONNX Runtime 1.28.0 release.',
    file: 'onnxruntime_1_28_third_party_notices.txt',
  ),
  (
    packages: ['Eigen'],
    lead:
        'Eigen, the part built into Moonshine 0.1.6. Source code: '
        'https://gitlab.com/libeigen/eigen and '
        'https://github.com/moonshine-ai/moonshine/tree/v0.1.6/core/third-party/Eigen',
    file: 'eigen.txt',
  ),
  (
    packages: [
      'sherpa-onnx',
      'kaldi-native-fbank',
      'kaldi-decoder',
      'simple-sentencepiece',
    ],
    lead: '',
    file: 'apache_2_0.txt',
  ),
  (
    packages: ['kaldifst', 'kaldi-hmm-gmm', 'kaldi_native_io'],
    lead: '',
    file: 'kaldi_legal_notices.txt',
  ),
  (packages: ['OpenFst'], lead: '', file: 'openfst.txt'),
  (packages: ['hclust-cpp'], lead: '', file: 'hclust_cpp.txt'),
  (packages: ['KISS FFT'], lead: '', file: 'kissfft.txt'),
  (packages: ['JSON for Modern C++'], lead: '', file: 'nlohmann_json.txt'),
  (packages: ['UTF8-CPP'], lead: '', file: 'utfcpp.txt'),
  (packages: ['utf8proc'], lead: '', file: 'utf8proc.txt'),
  // Firebase on Android (step 10b): the Android libraries the Firebase
  // plugins bring, from the release build's dependency list (2026-11-27).
  (
    packages: [
      'Firebase Android SDK',
      'gRPC Java',
      'Guava',
      'Gson',
      'PerfMark',
      'Credential Manager',
      'javax.inject',
      'JSR 305 annotations',
      'Error Prone annotations',
      'Android annotations',
    ],
    lead:
        'Firebase: firebase-firestore 26.6.0, firebase-common 22.2.1, '
        'firebase-components 19.0.0, firebase-annotations 17.0.0, '
        'firebase-appcheck-interop 17.0.0, firebase-database-collection '
        '18.0.1, protolite-well-known-types 18.0.1, firebase-bom 34.19.0. '
        'gRPC Java 1.62.2: grpc-android, grpc-api, grpc-context, grpc-core, '
        'grpc-okhttp, grpc-protobuf-lite, grpc-stub, grpc-util. Guava '
        '32.1.3-android and failureaccess 1.0.1. Gson 2.10.1. PerfMark API '
        '0.26.0. androidx.credentials and credentials-play-services-auth '
        '1.2.0-rc01. javax.inject 1. JSR 305 3.0.2. Error Prone annotations '
        '2.26.0. Android annotations 4.1.1.4.',
    file: 'apache_2_0.txt',
  ),
  (
    packages: ['gRPC Java'],
    lead: 'gRPC Java 1.62.2 NOTICE.',
    file: 'grpc_java_notice.txt',
  ),
  (
    packages: ['PerfMark'],
    lead: 'PerfMark 0.26.0 NOTICE.',
    file: 'perfmark_notice.txt',
  ),
  (
    packages: ['Checker Framework qualifiers'],
    lead: 'checker-qual 3.37.0.',
    file: 'checker_qual.txt',
  ),
  (
    packages: ['Animal Sniffer annotations'],
    lead: 'animal-sniffer-annotations 1.23.',
    file: 'animal_sniffer.txt',
  ),
  (packages: ['RE2/J'], lead: 'RE2/J 1.6.', file: 're2j.txt'),
  (
    packages: [
      'Firebase Authentication',
      'Google Play services',
      'reCAPTCHA',
      'Play Integrity',
    ],
    lead: '',
    file: 'google_sdk_terms.txt',
  ),
];

/// Adds [nativeNotices] to the licences page (About › Licences). Android
/// only: the other platforms don't ship this code.
void registerNativeLicenses({TargetPlatform? platform, AssetBundle? bundle}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) return;
  LicenseRegistry.addLicense(() => nativeLicenses(bundle ?? rootBundle));
}

/// The entries of [nativeNotices], read from [bundle].
Stream<LicenseEntry> nativeLicenses(AssetBundle bundle) async* {
  for (final n in nativeNotices) {
    final text = await bundle.loadString(
      'assets/licenses/${n.file}',
      cache: false,
    );
    yield LicenseEntryWithLineBreaks(
      n.packages,
      n.lead.isEmpty ? text : '${n.lead}\n\n$text',
    );
  }
}
