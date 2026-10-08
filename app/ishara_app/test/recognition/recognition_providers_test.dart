import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'providers load the kit from the app bundle and start the isolate',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final bundle = await c.read(modelBundleProvider.future);
      expect(bundle.labels.length, 22);
      expect(bundle.models.keys, bundle.config.models);
      final service = await c.read(recognitionServiceProvider.future);
      expect(service.labels.all, bundle.labels.all);
    },
  );

  test('glove failure kinds (error screens switch on these)', () {
    final failures = <GloveFailure, String>{
      const BluetoothUnavailableFailure(BluetoothProblem.off): 'bluetooth_off',
      const BluetoothUnavailableFailure(BluetoothProblem.locationOff):
          'bluetooth_locationOff',
      const GloveNotFoundFailure(): 'glove_not_found',
      const GloveConnectFailure('x'): 'glove_connect',
      const GloveProtocolMismatchFailure(2): 'glove_protocol',
      const GloveCommandTimeoutFailure('PING'): 'glove_timeout',
      GloveCommandRejectedFailure(const ErrorEvent('CAL', 'BUSY')):
          'glove_rejected',
      const GloveDisconnectedFailure(): 'glove_disconnected',
    };
    for (final MapEntry(key: f, value: kind) in failures.entries) {
      expect(f.kind, kind);
    }
    expect(
      GloveCommandRejectedFailure(const ErrorEvent('CAL', 'BUSY')).message,
      'glove refused: CAL BUSY',
    );
  });
}
