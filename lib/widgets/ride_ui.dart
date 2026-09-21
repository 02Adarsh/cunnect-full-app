import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// ⭐ v74: the Ride design kit.
///
/// One place for the glass cards, gradients, buttons and tiles that make
/// the Ride section feel like a finished product instead of a form.
/// Everything stays on the CUnnect dark theme — black base, red accent,
/// soft borders and gentle motion.
class RideColors {
  RideColors._();

  static const Color bg = Color(0xFF070707);
  static const Color card = Color(0xFF131313);
  static const Color cardHi = Color(0xFF1A1A1A);
  static const Color line = Color(0xFF262626);
  static const Color lineSoft = Color(0xFF1D1D1D);
  static const Color mint = Color(0xFF98E6B0);
  static const Color amber = Color(0xFFFFC978);
  static const Color sky = Color(0xFF8EC5FF);
  static const Color violet = Color(0xFFC4A6FF);
  static Color get red => AppColors.red;
  static Color get muted => AppColors.muted;
}

/// Vehicle accent colours — every vehicle gets its own identity.
Color rideVehicleTint(String key) => switch (key) {
      'mini' => RideColors.mint,
      'sedan' => RideColors.sky,
      'xl' => RideColors.violet,
      _ => AppColors.red,
    };

/// A frosted dark card — the base building block of the new Ride UI.
class RideGlass extends StatelessWidget {
  const RideGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.border,
    this.color = RideColors.card,
    this.gradient,
    this.blur = 0,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final BoxBorder? border;
  final Color color;
  final Gradient? gradient;
  final double blur;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: RideColors.line),
      ),
      child: child,
    );
    if (blur > 0) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }
    if (onTap != null) {
      body = GestureDetector(onTap: onTap, child: body);
    }
    if (margin != null) {
      body = Padding(padding: margin!, child: body);
    }
    return body;
  }
}

/// Small monospace section label — matches the rest of CUnnect.
class RideLabel extends StatelessWidget {
  const RideLabel(this.text, {super.key, this.color, this.size = 10.5});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w700,
          color: color ?? const Color(0xFF7A7A7A),
        ),
      );
}

/// The main action button (filled red) or a softer outlined one.
class RideButton extends StatelessWidget {
  const RideButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = true,
    this.color,
    this.busy = false,
    this.height = 52,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;
  final Color? color;
  final bool busy;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.red;
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: filled ? Colors.white : c),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 9),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6),
                ),
              ),
            ],
          );
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: filled
          ? ElevatedButton(
              onPressed: busy ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: c,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c),
                foregroundColor: c,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: child,
            ),
    );
  }
}

/// Round icon button used on the map and in headers.
class RideRoundButton extends StatelessWidget {
  const RideRoundButton({
    super.key,
    required this.icon,
    this.onTap,
    this.color,
    this.size = 42,
    this.busy = false,
    this.label,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final bool busy;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.red;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xE6141414),
          shape: BoxShape.circle,
          border: Border.all(color: c.withOpacity(.55)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(.45),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: c))
            : Icon(icon, color: label == null ? c : Colors.white, size: size * .45),
      ),
    );
  }
}

/// A tidy list row with an icon in a tinted square — used everywhere.
class RideTile extends StatelessWidget {
  const RideTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tint;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = tint ?? (danger ? AppColors.red : Colors.white);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.withOpacity(.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withOpacity(.22)),
                ),
                child: Icon(icon, size: 18, color: c),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: danger ? AppColors.red : Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    if (subtitle != null && '$subtitle'.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('$subtitle',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFF8A8A8A), fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill (time, distance, vehicle, badge).
class RideChip extends StatelessWidget {
  const RideChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.solid = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF9E9E9E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: solid ? c : c.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(solid ? 0 : .30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: solid ? Colors.black : c),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: solid ? Colors.black : c,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Number + caption, used for the stats strips.
class RideStat extends StatelessWidget {
  const RideStat({
    super.key,
    required this.value,
    required this.label,
    this.color,
  });

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color ?? Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            RideLabel(label, size: 9),
          ],
        ),
      );
}

/// The little grab handle that sits on top of every sliding sheet.
class RideGrab extends StatelessWidget {
  const RideGrab({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

/// Standard sliding-sheet shell (rounded top, dark, safe area aware).
class RideSheetShell extends StatelessWidget {
  const RideSheetShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 18),
    this.maxHeight = 0.92,
    this.minHeight = 0.35,
    this.initial = 0.62,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxHeight;
  final double minHeight;
  final double initial;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: initial,
        minChildSize: minHeight,
        maxChildSize: maxHeight,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF101010),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black54, blurRadius: 26, offset: Offset(0, -6)),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: controller,
              padding: padding,
              children: [
                Center(child: RideGrab()),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      );
}

/// Empty-state block (no rides yet, no history…).
class RideEmpty extends StatelessWidget {
  const RideEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF131313),
                shape: BoxShape.circle,
                border: Border.all(color: RideColors.line),
              ),
              child: Icon(icon, size: 30, color: const Color(0xFF4A4A4A)),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text('$subtitle',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF8A8A8A), fontSize: 12.5, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      );
}

/// Dots + connector used to draw a pickup → drop timeline.
class RideTimeline extends StatelessWidget {
  const RideTimeline({super.key, this.color = RideColors.mint});

  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(5)),
          ),
          ...List.generate(
              3,
              (_) => Container(
                  width: 2,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: const Color(0xFF333333))),
          const Icon(Icons.location_on_rounded, size: 15, color: AppColors.red),
        ],
      );
}
