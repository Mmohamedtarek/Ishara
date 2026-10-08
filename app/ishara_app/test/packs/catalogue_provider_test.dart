import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the catalogue loads from the app bundle, checked against the model',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final cat = await c.read(signCatalogueProvider.future);
      expect(cat.signs, hasLength(25));
      expect(cat.byLabel('hello')!.wordsIn(SpokenLanguage.ar).word, 'أهلاً');
    },
  );
}
