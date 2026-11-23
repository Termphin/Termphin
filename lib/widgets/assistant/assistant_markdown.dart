import 'package:material_ui/material_ui.dart';

import '../../theme/theme.dart';

/// One block of a reply: a paragraph, a heading, a list item or a code
/// block.
sealed class MarkdownBlock {
  const MarkdownBlock();
}

class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.text);

  final String text;
}

class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(this.text);

  final String text;
}

class MarkdownListItem extends MarkdownBlock {
  const MarkdownListItem(this.text, {this.number, this.depth = 0});

  final String text;

  /// The item's number in an ordered list, null for a bullet.
  final int? number;

  /// How far it is indented, in levels.
  final int depth;
}

class MarkdownCode extends MarkdownBlock {
  const MarkdownCode(this.text);

  final String text;
}

/// Splits [text] into blocks: the little markdown a model writes in a chat -
/// paragraphs, `#` headings, `-`, `*` and `1.` lists, and fenced code. A
/// fence still open, as one is while the reply streams in, runs to the end.
List<MarkdownBlock> parseMarkdown(String text) {
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  final lines = text.replaceAll('\r\n', '\n').split('\n');

  void flush() {
    if (paragraph.isNotEmpty) {
      blocks.add(MarkdownParagraph(paragraph.join(' ').trim()));
      paragraph.clear();
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      flush();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      blocks.add(MarkdownCode(code.join('\n')));
      continue;
    }
    if (trimmed.isEmpty) {
      flush();
      continue;
    }
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flush();
      blocks.add(MarkdownHeading(heading.group(1)!));
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      flush();
      blocks.add(MarkdownListItem(bullet.group(1)!, depth: indent ~/ 2));
      continue;
    }
    final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      flush();
      blocks.add(
        MarkdownListItem(
          numbered.group(2)!,
          number: int.parse(numbered.group(1)!),
          depth: indent ~/ 2,
        ),
      );
      continue;
    }
    paragraph.add(trimmed);
  }
  flush();
  return blocks;
}

/// One stretch of a line: plain, bold, italic or code.
typedef MarkdownRun = ({String text, bool bold, bool italic, bool code});

/// Splits a line into runs: `` `code` ``, `**bold**` and `*italic*` or
/// `_italic_`. Markers left open are shown as they are.
List<MarkdownRun> parseInline(String text) {
  final runs = <MarkdownRun>[];
  final pattern = RegExp(
    r'`([^`]+)`|\*\*([^*]+)\*\*|__([^_]+)__|(?<![\w*])\*([^*\s][^*]*?)\*(?!\w)|(?<![\w_])_([^_\s][^_]*?)_(?!\w)',
  );
  var at = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > at) {
      runs.add((
        text: text.substring(at, match.start),
        bold: false,
        italic: false,
        code: false,
      ));
    }
    if (match.group(1) != null) {
      runs.add((text: match.group(1)!, bold: false, italic: false, code: true));
    } else if (match.group(2) != null || match.group(3) != null) {
      runs.add((
        text: (match.group(2) ?? match.group(3))!,
        bold: true,
        italic: false,
        code: false,
      ));
    } else {
      runs.add((
        text: (match.group(4) ?? match.group(5))!,
        bold: false,
        italic: true,
        code: false,
      ));
    }
    at = match.end;
  }
  if (at < text.length) {
    runs.add((
      text: text.substring(at),
      bold: false,
      italic: false,
      code: false,
    ));
  }
  return runs;
}

/// A reply from the assistant, its markdown drawn in the app's own type
/// and colours.
class AssistantMarkdown extends StatelessWidget {
  const AssistantMarkdown(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = TextStyle(
      fontSize: AppTheme.font15,
      height: 1.5,
      color: colors.textPrimary,
    );
    final blocks = parseMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed)
          Padding(
            padding: EdgeInsets.only(
              top: index == 0
                  ? 0
                  : block is MarkdownListItem &&
                        blocks[index - 1] is MarkdownListItem
                  ? AppTheme.space4
                  : AppTheme.space10,
            ),
            child: switch (block) {
              MarkdownParagraph(:final text) => _inline(context, text, base),
              MarkdownHeading(:final text) => _inline(
                context,
                text,
                base.copyWith(fontWeight: FontWeight.w600),
              ),
              MarkdownListItem(:final text, :final number, :final depth) =>
                Padding(
                  padding: EdgeInsets.only(left: depth * AppTheme.space16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: AppTheme.space20,
                        child: Text(
                          number == null ? '•' : '$number.',
                          style: base.copyWith(color: colors.textSecondary),
                        ),
                      ),
                      Expanded(child: _inline(context, text, base)),
                    ],
                  ),
                ),
              MarkdownCode(:final text) => Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space10,
                  vertical: AppTheme.space8,
                ),
                decoration: BoxDecoration(
                  color: colors.isDark
                      ? colors.backgroundPrimary
                      : colors.surfaceOffset,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    text,
                    style: colors.monoStyle.copyWith(
                      fontSize: AppTheme.font12,
                      height: 1.45,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            },
          ),
      ],
    );
  }

  Widget _inline(BuildContext context, String text, TextStyle base) {
    final colors = context.colors;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final run in parseInline(text))
            TextSpan(
              text: run.text,
              style: run.code
                  ? colors.monoStyle.copyWith(
                      fontSize: AppTheme.font14,
                      color: colors.textPrimary,
                      backgroundColor: colors.isDark
                          ? colors.backgroundPrimary
                          : colors.surfaceOffset,
                    )
                  : TextStyle(
                      fontWeight: run.bold ? FontWeight.w600 : null,
                      fontStyle: run.italic ? FontStyle.italic : null,
                    ),
            ),
        ],
      ),
    );
  }
}
