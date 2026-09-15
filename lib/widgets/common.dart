import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_colors.dart';

/// The premium CUnnect wordmark used on every page
/// (Poppins 800, red "CU" with glow + white "nnect").
class CunnectWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;

  const CunnectWordmark({super.key, this.fontSize = 30, this.letterSpacing = -3});

  @override
  Widget build(BuildContext context) {
    // ⭐ naya image logo — text overlap glitch hamesha ke liye gayab
    return Image.asset('assets/logo.png',
        height: fontSize * 1.15, fit: BoxFit.contain);
  }
}

/// Simple brand text — ⭐ ab purane app wale wordmark (glow wala) jaisa hi,
/// taaki pure app me logo ekdam same dikhe.
class CunnectBrand extends StatelessWidget {
  final double fontSize;
  final String? suffix;

  const CunnectBrand({super.key, this.fontSize = 22, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CunnectWordmark(fontSize: fontSize, letterSpacing: -1.2),
        if (suffix != null)
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Text(
              suffix!,
              style: const TextStyle(
                color: Color(0xFFAAAAAA), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6),
            ),
          ),
      ],
    );
  }
}

/// Standard CUnnect page header with back button and centered logo.
class CunnectHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool useWordmark;

  const CunnectHeader({super.key, this.onBack, this.trailing, this.useWordmark = true});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    // ⭐ Scaffold appBar ko status bar ke neeche khud rakhta hai —
    // andar SafeArea lagane se content clip hota tha (mobile glitch).
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFA050505),
        border: Border(bottom: BorderSide(color: Color(0xFF191919))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Text('‹', style: TextStyle(fontSize: 25, height: 1, color: Colors.white)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 20,
          ),
          Expanded(
              child: Center(
                  child: useWordmark ? const CunnectWordmark() : const CunnectBrand())),
          SizedBox(width: 36, child: trailing),
        ],
      ),
    );
  }
}

/// Dark panel with rounded border — matches `.panel` in vendor pages.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const Panel({super.key, required this.child, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Status chip colors — copied from the my_orders.html / vendor pages.
class StatusChip extends StatelessWidget {
  final OrderStatus status;
  final bool pill;

  const StatusChip({super.key, required this.status, this.pill = false});

  Color get _border {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0x80F10B1D);
      case OrderStatus.accepted:
        return const Color(0x7A4BA3FF);
      case OrderStatus.preparing:
        return const Color(0x80FFAA37);
      case OrderStatus.ready:
        return const Color(0x8038B765);
      case OrderStatus.outForDelivery:
        return const Color(0x7A4BA3FF);
      case OrderStatus.completed:
        return const Color(0x5938B765);
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return const Color(0xFF4B4B4B);
    }
  }

  Color get _background {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0x1AF10B1D);
      case OrderStatus.accepted:
        return const Color(0x1A4BA3FF);
      case OrderStatus.preparing:
        return const Color(0x1AFFAA37);
      case OrderStatus.ready:
      case OrderStatus.completed:
        return const Color(0x1A38B765);
      case OrderStatus.outForDelivery:
        return const Color(0x1A4BA3FF);
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.transparent;
    }
  }

  Color get _text {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFFFF9CA4);
      case OrderStatus.accepted:
        return const Color(0xFF9ECBFF);
      case OrderStatus.preparing:
        return const Color(0xFFFFD394);
      case OrderStatus.ready:
      case OrderStatus.completed:
        return const Color(0xFF9BE7B4);
      case OrderStatus.outForDelivery:
        return const Color(0xFF9ECBFF);
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return const Color(0xFFAAAAAA);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pill ? 6 : 8, vertical: pill ? 3 : 5),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _border),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(color: _text, fontSize: pill ? 9 : 9.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Swiggy-style bottom toast used for coupon / action feedback.
void showCunnectToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    content: Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error ? AppColors.red : const Color(0xFF31A655),
          ),
          alignment: Alignment.center,
          child: Text(error ? '!' : '✓',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
                color: error ? const Color(0xFFFFD0D4) : const Color(0xFFD2F9DA),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35),
          ),
        ),
      ],
    ),
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 96),
    backgroundColor: error ? const Color(0xFF2A1114) : const Color(0xFF112218),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: BorderSide(color: error ? const Color(0x94F10B1D) : const Color(0x8C3DB260)),
    ),
    elevation: 12,
    duration: const Duration(seconds: 3),
  ));
}

/// Input field styled like `.field` / `.input` in the templates.
InputDecoration cunnectInputDecoration({String? placeholder}) {
  return InputDecoration(
    hintText: placeholder,
    hintStyle: const TextStyle(color: AppColors.placeholder, fontSize: 13),
    filled: true,
    fillColor: AppColors.inputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AppColors.red),
    ),
  );
}

/// Dashed coupon code box from the offer cards.
class DashedCouponCode extends StatelessWidget {
  final String code;

  const DashedCouponCode({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white.withOpacity(.5), style: BorderStyle.solid),
      ),
      child: Text(
        code,
        style: const TextStyle(
            color: Color(0xFFFFB1B8), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .4),
      ),
    );
  }
}

/// Network image with the same dark placeholder as the Django templates.
/// Backend media URLs se load hota hai; fail hone par subtle placeholder.
class CunnectImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const CunnectImage(this.url,
      {super.key, this.width, this.height, this.fit = BoxFit.cover, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: const Color(0xFF1B1B1B),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined,
          color: Color(0xFF3A3A3A), size: 22),
    );

    if (url.isEmpty || !url.startsWith('http')) {
      return _wrap(placeholder);
    }

    final image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
    return _wrap(image);
  }

  Widget _wrap(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}


/// ⭐ Classic text wordmark (pre-v20) — login/registration/OTP screens
class CunnectWordmarkClassic extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;

  const CunnectWordmarkClassic(
      {super.key, this.fontSize = 30, this.letterSpacing = -3});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'CU',
          style: TextStyle(
            color: AppColors.redLogo,
            shadows: const [
              Shadow(color: Color(0x99FF1022), blurRadius: 18),
              Shadow(color: Color(0x40FF1022), blurRadius: 42),
            ],
          ),
        ),
        TextSpan(
          text: 'nnect',
          style: TextStyle(
            color: Colors.white,
            shadows: const [Shadow(color: Color(0x29FFFFFF), blurRadius: 10)],
          ),
        ),
      ]),
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: letterSpacing,
        height: 1,
      ),
    );
  }
}
