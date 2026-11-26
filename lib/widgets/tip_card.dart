import 'package:flutter/material.dart';

import '../services/help_settings.dart';
import '../theme/app_theme.dart';

/// Consejo corto que aparece una sola vez en una pantalla.
class TipCard extends StatefulWidget {
  final String id;
  final String text;
  const TipCard({super.key, required this.id, required this.text});

  @override
  State<TipCard> createState() => _TipCardState();
}

class _TipCardState extends State<TipCard> {
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    HelpSettings.tipSeen(widget.id).then((v) {
      if (mounted) setState(() => _seen = v);
    });
  }

  Future<void> _close() async {
    setState(() => _seen = true);
    await HelpSettings.markTip(widget.id, true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: HelpSettings.showTips,
      builder: (context, on, _) {
        if (!on || _seen) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 2, 8),
            decoration: BoxDecoration(
              color: AppColors.amberTint,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border:
                  Border.all(color: AppColors.amberLine),
            ),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.text,
                    style: const TextStyle(fontSize: AppType.bodySm, height: 1.35)),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Entendido',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _close,
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
