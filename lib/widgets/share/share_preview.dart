import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../services/platform/share_intent_service.dart';
import '../../services/sftp/upload_plan.dart';
import '../../theme/theme.dart';
import '../../utils/file_icon.dart';
import '../../utils/format_size.dart';
import '../ui/section_header.dart';

/// What was shared, above the list it is being sent to. Captioned like the
/// list's own sections, so the screen reads as one sentence: "Upload 2 files
/// to" - then the machines. Files show as small tiles with the same type
/// icons the file browser uses, running on to the screen's edge rather than
/// stopping short at the margin, to say there is more to scroll to.
class SharePreview extends StatelessWidget {
  const SharePreview({super.key, required this.content});

  final SharedContent content;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final files = content.files;
    final caption = files.length == 1
        ? t.share.uploadTo
        : t.share.uploadManyTo(count: files.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: SectionHeader(caption),
        ),
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _FileTile(files[i]),
          ),
        ),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile(this.file);

  final LocalUpload file;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildFileIcon(
            file.name,
            size: 28,
            fallbackColor: colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.itemTitle.copyWith(fontSize: 14),
                ),
                FutureBuilder<int?>(
                  future: file.length(),
                  builder: (context, size) => Text(
                    size.data == null ? '' : formatFileSize(size.data),
                    style: colors.uiSmall.copyWith(color: colors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
