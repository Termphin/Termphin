import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../models/ssh_key.dart';
import '../../theme/theme.dart';
import '../ui/clipboard_and_links.dart';

/// A freshly made key is no use until the server knows it, so every place
/// that makes one says where the public half goes and hands it over.
Future<void> showPublicKeyDialog(BuildContext context, SshKey key) {
  final t = Translations.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t.keys.keyCreatedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.keys.keyCreatedInstructions,
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ctx.colors.backgroundPrimary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: ctx.colors.surfaceBorder),
            ),
            child: SelectableText(
              key.publicKeyOpenSSH,
              style: ctx.colors.monoSmall,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => copyToClipboard(ctx, key.publicKeyOpenSSH),
          child: Text(t.common.copy),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t.common.done),
        ),
      ],
    ),
  );
}
