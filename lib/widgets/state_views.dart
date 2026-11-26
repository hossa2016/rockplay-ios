import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Mensaje de estado (vacío / error / intro) con icono, título y acción.
/// Es el único estilo de estado de la app. [compact] = versión en línea
/// para filas horizontales y secciones dentro de una página.
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;
  final bool compact;

  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.actionLabel,
    this.onAction,
    this.isError = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isError ? AppColors.amber : AppColors.redText;
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.surfaceHigh),
              child: Icon(icon, size: 22, color: tint),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: AppType.bodySm,
                          fontWeight: FontWeight.w700)),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(message,
                        style: TextStyle(
                            fontSize: AppType.label,
                            height: 1.3,
                            color: AppColors.textDim)),
                  ],
                  // La acción va debajo: al lado apretaba el texto en
                  // columnas de una palabra con letra grande.
                  if (actionLabel != null && onAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft),
                          onPressed: onAction,
                          child: Text(actionLabel!)),
                    ),
                ],
              ),
            ),
          ]),
        ),
      );
    }
    final content = Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.xxxl, vertical: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHigh,
                border: Border.all(color: AppColors.outline),
              ),
              child: Icon(icon, size: 38, color: tint),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textDim,
                  height: 1.4,
                  fontSize: AppType.bodySm,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
    );
    // Dentro de otra lista (alto infinito) va tal cual; si no, centrado.
    return LayoutBuilder(
      builder: (context, box) => box.hasBoundedHeight
          ? Center(child: SingleChildScrollView(child: content))
          : content,
    );
  }
}

/// Aparece con fundido y ligero desplazamiento. [order] escalona la entrada.
/// Respeta «reducir animaciones» del sistema.
class FadeIn extends StatelessWidget {
  final Widget child;
  final int order;

  const FadeIn({super.key, required this.child, this.order = 0});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final o = order > 8 ? 8 : (order < 0 ? 0 : order);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + o * 45),
      curve: Curves.easeOutCubic,
      builder: (context, v, ch) {
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: ch),
        );
      },
      child: child,
    );
  }
}

/// Brillo que recorre los esqueletos. Quieto si se piden menos animaciones.
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [
              AppColors.surfaceHigh,
              Color(0xFF30303B),
              AppColors.surfaceHigh,
            ],
            stops: const [0.35, 0.5, 0.65],
            transform: _Slide(_c.value * 2 - 1),
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

Widget _box(double w, double h, double r) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(r),
      ),
    );

/// Lista de esqueletos pulsantes mientras carga. [shrinkWrap] para usarla
/// dentro de otra lista.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool shrinkWrap;
  const SkeletonList({super.key, this.count = 7, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.builder(
        shrinkWrap: shrinkWrap,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.sm),
        itemCount: count,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              _box(56, 56, AppRadius.sm),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(double.infinity, 14, 6),
                    const SizedBox(height: AppSpace.sm),
                    _box(120, 12, 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esqueletos para carruseles horizontales (portadas o círculos).
class SkeletonRow extends StatelessWidget {
  final double itemWidth;
  final double coverHeight;
  final bool circle;
  final int count;
  const SkeletonRow({
    super.key,
    this.itemWidth = 140,
    this.coverHeight = 140,
    this.circle = false,
    this.count = 4,
  });

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
        itemBuilder: (_, __) => SizedBox(
          width: itemWidth,
          child: Column(
            crossAxisAlignment: circle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _box(circle ? coverHeight : itemWidth, coverHeight,
                  circle ? coverHeight / 2 : AppRadius.md),
              const SizedBox(height: AppSpace.sm),
              _box(itemWidth * 0.8, 12, 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide extends GradientTransform {
  final double p;
  const _Slide(this.p);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * p, 0, 0);
}
