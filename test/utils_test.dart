import 'package:bodiana/core/constants.dart';
import 'package:bodiana/core/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats rupees in Indian style', () {
    expect(money(150000), contains('1,50,000'));
    expect(money('2500.4'), contains('2,500'));
  });

  test('parses embedded rows safely', () {
    expect(asMap([{'a': 1}])['a'], 1);
    expect(asMap(null), isEmpty);
    expect(asList({'a': 1}).length, 1);
    expect(asStrings(['x', null, 'y']), ['x', 'y']);
  });

  test('public storage URLs map back to paths', () {
    expect(
      publicPathFromUrl('https://x.supabase.co/storage/v1/object/public/public-media/uid/logo/1.jpg'),
      'uid/logo/1.jpg',
    );
    expect(publicPathFromUrl('https://example.com/a.jpg'), isNull);
  });

  test('every category resolves', () {
    for (final c in categories) {
      expect(categoryById(c.id).id, c.id);
    }
    expect(categoryById('unknown').id, 'other');
  });
}
