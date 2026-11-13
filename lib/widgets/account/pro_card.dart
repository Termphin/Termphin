import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../i18n/strings.g.dart';
import '../../services/pro/pro_service.dart';
import '../../theme/theme.dart';
import '../ui/app_card.dart';
import '../ui/app_notifications.dart';

/// Pro, on the account screen: what it is and the store's prices, or that
/// it is on.
class ProCard extends StatefulWidget {
  const ProCard({super.key});

  @override
  State<ProCard> createState() => _ProCardState();
}

class _ProCardState extends State<ProCard> {
  List<ProOffer> _offers = const [];
  bool _busy = false;

  ProService get _pro => ProService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _pro.refresh();
    List<ProOffer> offers = const [];
    try {
      if (!_pro.active.value) offers = await _pro.offers();
    } catch (_) {}
    if (mounted) setState(() => _offers = offers);
  }

  Future<void> _attempt(Future<void> Function() action) async {
    final t = Translations.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && _pro.active.value) {
        AppNotifications.success(context, t.account.pro.thanks);
      }
    } on ProException catch (error) {
      if (mounted && error.failure != ProFailure.cancelled) {
        AppNotifications.error(context, t.account.pro.failed);
      }
    } catch (_) {
      if (mounted) AppNotifications.error(context, t.account.pro.failed);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  String _label(Translations t, ProOffer offer) => switch (offer.period) {
    'annual' => t.account.pro.annual(price: offer.price),
    'lifetime' => t.account.pro.lifetime(price: offer.price),
    _ => t.account.pro.monthly(price: offer.price),
  };

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: _pro.active,
      builder: (context, active, _) => AppCard(
        padding: const EdgeInsets.all(AppTheme.space14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.account.pro.title, style: text.titleMedium),
            const SizedBox(height: AppTheme.space6),
            Text(
              active
                  ? t.account.pro.active
                  : _pro.available
                  ? t.account.pro.pitch
                  : t.account.pro.unavailable,
              style: text.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            if (!active && _pro.available) ...[
              const SizedBox(height: AppTheme.space12),
              for (final offer in _offers) ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _attempt(() => _pro.buy(offer)),
                  child: Text(_label(t, offer)),
                ),
                const SizedBox(height: AppTheme.space8),
              ],
              TextButton(
                onPressed: _busy ? null : () => _attempt(_pro.restore),
                child: Text(t.account.pro.restore),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
