import 'package:flutter_test/flutter_test.dart';
import 'package:termphin/widgets/assistant/assistant_markdown.dart';

void main() {
  test('blocks', () {
    final blocks = parseMarkdown(
      '## Disk\n\nYou have **12 GB** free on `/`.\nThat is enough.\n\n'
      '- `/var/log` 4 GB\n  - nginx 3 GB\n1. Clean logs\n\n```\ndf -h\n```\nDone.',
    );
    expect(blocks[0], isA<MarkdownHeading>());
    expect(
      (blocks[1] as MarkdownParagraph).text,
      'You have **12 GB** free on `/`. That is enough.',
    );
    expect((blocks[2] as MarkdownListItem).number, isNull);
    expect((blocks[3] as MarkdownListItem).depth, 1);
    expect((blocks[4] as MarkdownListItem).number, 1);
    expect((blocks[5] as MarkdownCode).text, 'df -h');
    expect((blocks[6] as MarkdownParagraph).text, 'Done.');
  });

  test('a code fence still streaming in runs to the end', () {
    final blocks = parseMarkdown('Run:\n```\nsystemctl status');
    expect((blocks.last as MarkdownCode).text, 'systemctl status');
  });

  test('inline runs', () {
    final runs = parseInline(
      'free **12 GB** on `/dev/sda1`, *roughly* snake_case_name',
    );
    expect(runs.where((r) => r.bold).single.text, '12 GB');
    expect(runs.where((r) => r.code).single.text, '/dev/sda1');
    expect(runs.where((r) => r.italic).single.text, 'roughly');
    expect(
      runs.map((r) => r.text).join(),
      'free 12 GB on /dev/sda1, roughly snake_case_name',
    );
  });
}
