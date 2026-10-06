const _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ó': 'o',
  'ö': 'o',
  'ú': 'u',
  'ü': 'u',
  '♀': 'f',
  '♂': 'm',
};

/// Lowercase, fold accents/gender symbols, and drop everything but a-z0-9
/// (so all punctuation AND spaces disappear: "Mr. Mime" -> "mrmime").
String normalise(String input) {
  final out = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    for (final c in (_fold[ch] ?? ch).codeUnits) {
      if ((c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39)) {
        out.writeCharCode(c);
      }
    }
  }
  return out.toString();
}

final _wordBreak = RegExp(r'[\s\-().:]+');

/// Normalised words of a display name, split on spaces/hyphens/brackets/dots.
List<String> splitWords(String name) => [
  for (final w in name.split(_wordBreak))
    if (normalise(w).isNotEmpty) normalise(w),
];
