import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One notice on the licences page: the components it covers, an optional
/// lead line, and its text in `assets/licenses/`.
typedef NativeNotice = ({List<String> packages, String lead, String file});

/// Native code in the Android app that pub doesn't know about (DECISIONS
/// TV-21): Moonshine 0.1.6 and its model, the libraries built into
/// `libmoonshine.so` (Moonshine's `core/third-party`), and ONNX Runtime
/// 1.23.2 with its own notices. Licence texts are the upstream ones.
const List<NativeNotice> nativeNotices = [
  (
    packages: ['Moonshine Voice', 'Moonshine Small streaming English model'],
    lead: '',
    file: 'moonshine.txt',
  ),
  (packages: ['ONNX Runtime'], lead: '', file: 'onnxruntime.txt'),
  (
    packages: ['ONNX Runtime'],
    lead: '',
    file: 'onnxruntime_third_party_notices.txt',
  ),
  (
    packages: ['Eigen'],
    lead:
        'Eigen, the part built into Moonshine 0.1.6. Source code: '
        'https://gitlab.com/libeigen/eigen and '
        'https://github.com/moonshine-ai/moonshine/tree/v0.1.6/core/third-party/Eigen',
    file: 'eigen.txt',
  ),
  (packages: ['kaldi-native-fbank'], lead: '', file: 'kaldi_native_fbank.txt'),
  (packages: ['KISS FFT'], lead: '', file: 'kissfft.txt'),
  (packages: ['JSON for Modern C++'], lead: '', file: 'nlohmann_json.txt'),
  (packages: ['UTF8-CPP'], lead: '', file: 'utfcpp.txt'),
  (packages: ['utf8proc'], lead: '', file: 'utf8proc.txt'),
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
