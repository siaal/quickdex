import 'package:flutter_test/flutter_test.dart';
import 'package:quickdex/search/normalise.dart';

void main() {
  test('punctuation and spaces are removed', () {
    expect(normalise('Mr. Mime'), 'mrmime');
    expect(normalise('mr mime'), 'mrmime');
    expect(normalise('mrmime'), 'mrmime');
    expect(normalise("Farfetch’d"), 'farfetchd');
    expect(normalise("Farfetch'd"), 'farfetchd');
    expect(normalise('Ho-Oh'), 'hooh');
  });

  test('accents and gender symbols fold', () {
    expect(normalise('Flabébé'), 'flabebe');
    expect(normalise('Nidoran♀'), 'nidoranf');
    expect(normalise('Nidoran♂'), 'nidoranm');
  });

  test('splitWords', () {
    expect(splitWords('Mr. Mime'), ['mr', 'mime']);
    expect(splitWords('Raichu (Alolan)'), ['raichu', 'alolan']);
  });
}
