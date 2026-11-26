import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'dj_screen.dart';
import 'radio_screen.dart';
import 'search_screen.dart';

/// Pide abrir un modo de Buscar desde fuera (0 canciones, 1 mix de artista,
/// 2 radio en vivo).
final ValueNotifier<int> searchHubWantMode = ValueNotifier<int>(-1);

/// Pestaña Buscar: canciones, mix de artista o radio en vivo.
class SearchHub extends StatefulWidget {
  const SearchHub({super.key});

  @override
  State<SearchHub> createState() => _SearchHubState();
}

class _SearchHubState extends State<SearchHub> {
  int _mode = 0;

  @override
  void initState() {
    super.initState();
    searchHubWantMode.addListener(_wantMode);
  }

  void _wantMode() {
    final m = searchHubWantMode.value;
    if (m < 0) return;
    searchHubWantMode.value = -1;
    if (mounted) setState(() => _mode = m);
  }

  @override
  void dispose() {
    searchHubWantMode.removeListener(_wantMode);
    super.dispose();
  }

  Widget _seg(String label, int i) {
    final on = _mode == i;
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        child: GestureDetector(
          onTap: () {
            if (_mode != i) HapticFeedback.selectionClick();
            setState(() => _mode = i);
          },
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.fast),
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.redBtn : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppType.bodySm,
                    // No solo color: el elegido también va en negrita.
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? Colors.white : AppColors.textDim)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.outline),
              ),
              child: Dense(child: Row(children: [
                _seg('Canciones', 0),
                _seg('Mezclar', 1),
                _seg('Radio', 2),
              ])),
            ),
            Expanded(
              child: IndexedStack(
                index: _mode,
                children: const [
                  SearchScreen(),
                  DjScreen(),
                  RadioScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
