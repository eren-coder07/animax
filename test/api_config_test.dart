import 'package:animax/core/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default backend is the current Aniwaves host', () {
    expect(ApiConfig().baseUrl, kDefaultApiBase);
    expect(kDefaultApiBase, 'https://aniwaves.tv');
  });

  test('saved configs on the retired aniwaves.ru host migrate to the default',
      () {
    expect(
        ApiConfig.fromJson(<String, dynamic>{'baseUrl': 'https://aniwaves.ru'})
            .baseUrl,
        kDefaultApiBase);
    expect(
        ApiConfig.fromJson(<String, dynamic>{'baseUrl': 'https://www.aniwaves.ru/'})
            .baseUrl,
        kDefaultApiBase);
    expect(ApiConfig.fromJson(<String, dynamic>{}).baseUrl, kDefaultApiBase);
  });

  test('custom saved hosts are kept', () {
    expect(
        ApiConfig.fromJson(<String, dynamic>{'baseUrl': 'https://example.org'})
            .baseUrl,
        'https://example.org');
  });
}
