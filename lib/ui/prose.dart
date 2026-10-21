import 'package:flutter/material.dart';

import '../trace.dart';

/// PokéAPI-style prose: paragraphs split by blank lines, where a paragraph whose
/// second line is a Markdown rule ("--- | ---:") is a table (rows "a | b", built
/// by the pipeline's `clean_paragraphs`), and `code` spans are formulas.
class ProseText extends StatelessWidget {
  const ProseText(this.text, {super.key});
  final String text;

  static final _rule = RegExp(r'^:?-+:?(\s*\|\s*:?-+:?)+$');

  /// The table's rows, or null when [para] is prose.
  static List<List<String>>? tableOf(String para) {
    final lines = para.split('\n');
    if (lines.length < 3 || !_rule.hasMatch(lines[1].trim())) return null;
    final rows = [
      for (final l in lines) [for (final c in l.split('|')) c.trim()],
    ];
    assert(
      rows.every((r) => r.length == rows.first.length),
      'ragged table: $para',
    );
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final paras = text.split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in paras.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          if (tableOf(p) case final rows?)
            _table(context, rows, i)
          else
            Text.rich(_spans(p), key: Key('prose-para-$i')),
        ],
      ],
    );
  }

  Widget _table(BuildContext context, List<List<String>> rows, int i) {
    trace('prose.table', {'rows': rows.length - 2, 'cols': rows.first.length});
    final theme = Theme.of(context);
    // The rule's "----:" means right-aligned, like Markdown.
    final right = [for (final c in rows[1]) c.endsWith(':')];
    final line = BorderSide(color: theme.dividerColor);
    Widget cell(String s, int col, {bool header = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        s,
        textAlign: right[col] ? TextAlign.right : TextAlign.left,
        style: header ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Table(
        key: Key('prose-table-$i'),
        defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        border: TableBorder(horizontalInside: line, top: line, bottom: line),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            children: [
              for (final (c, s) in rows.first.indexed) cell(s, c, header: true),
            ],
          ),
          for (final r in rows.skip(2))
            TableRow(children: [for (final (c, s) in r.indexed) cell(s, c)]),
        ],
      ),
    );
  }

  /// `code` spans in a monospace font, without the backticks.
  TextSpan _spans(String p) {
    final parts = p.split('`');
    if (parts.length.isEven) {
      trace('prose.code.unbalanced', {'length': p.length});
      return TextSpan(text: p); // leave it as written
    }
    return TextSpan(
      children: [
        for (final (i, s) in parts.indexed)
          TextSpan(
            text: s,
            style: i.isOdd ? const TextStyle(fontFamily: 'monospace') : null,
          ),
      ],
    );
  }
}
