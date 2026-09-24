import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/open_url.dart';
import '../theme/app_colors.dart';

/// The premium CUnnect wordmark used on every page
/// (Poppins 800, red "CU" with glow + white "nnect").
class CunnectWordmark extends StatelessWidget {
  final double fontSize;
  final double letterSpacing;

  const CunnectWordmark({super.key, this.fontSize = 30, this.letterSpacing = -3});

  @override
  Widget build(BuildContext context) {
    // ⭐ new image logo — the text overlap glitch is gone for good
    return Image.asset('assets/logo.png',
        height: fontSize * 1.15, fit: BoxFit.contain);
  }
}

/// Simple brand text — ⭐ now matches the old app wordmark (with glow),
/// so the logo looks identical across the whole app.
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
    // ⭐ Scaffold already places the appBar below the status bar —
    // adding a SafeArea inside clipped the content (mobile glitch).
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
        return const Color(0x80F10B1D);
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
        return const Color(0x1AF10B1D);
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
/// ⭐ v79: the SUCCESS flash message is GREEN again (the owner's own
/// look) — only the error one is red.
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
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
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
      side: BorderSide(
          color: error ? const Color(0x94F10B1D) : const Color(0x8C3DB260)),
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
/// Loads from backend media URLs; a subtle placeholder on failure.
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

// ---------------------------------------------------------------------
// ⭐ Standard VEG / NON-VEG mark — white square + green/red border +
// filled circle. Keep `size` EQUAL to the dish-name fontSize so the
// mark reads like the next word of the name.
// ---------------------------------------------------------------------
class VegMark extends StatelessWidget {
  final bool isVeg;
  final double size;

  const VegMark({super.key, required this.isVeg, required this.size});

  @override
  Widget build(BuildContext context) {
    // ⭐ v84: VEG is GREEN, NON-VEG is RED (it was red for both).
    final color =
        isVeg ? const Color(0xFF0F8A3C) : const Color(0xFFD32F2F);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: color, width: size * 0.11),
      ),
      alignment: Alignment.center,
      child: Container(
        width: size * 0.46,
        height: size * 0.46,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Dish name + inline VegMark — the mark is exactly font-sized and sits
/// right after the name like the "next word".
class DishNameWithMark extends StatelessWidget {
  final String name;
  final bool isVeg;
  final TextStyle style;
  final int maxLines;

  const DishNameWithMark({
    super.key,
    required this.name,
    required this.isVeg,
    required this.style,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final markSize = style.fontSize ?? 13;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: name, style: style),
        const WidgetSpan(child: SizedBox(width: 6)),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: VegMark(isVeg: isVeg, size: markSize),
        ),
      ]),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// ⭐ v60: concise bullet-point payment instructions — shown below the QR
/// and UPI ID in EVERY payment section (food checkout, printout, hostel).
class PaymentSteps extends StatelessWidget {
  final String actionLabel; // e.g. 'Place Order' / 'Send Print Request'

  const PaymentSteps({super.key, this.actionLabel = 'Place Order'});

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Scan the QR / copy UPI ID and make the payment',
      'Copy and paste the transaction ID from your UPI app',
      'Tap $actionLabel',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Text('•',
                      style: TextStyle(
                          color: Color(0xFFFFABB2),
                          fontSize: 11,
                          height: 1.45,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(s,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10.5,
                          height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }

}

/// ⭐ v72: plain text in which every web link is painted in CUnnect RED
/// and opens straight away when tapped (share any link on the feed).
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final int maxLines;

  const LinkText(
    this.text, {
    super.key,
    this.style = const TextStyle(color: Color(0xFFBBBBBB), fontSize: 12),
    this.linkColor = const Color(0xFFF10B1D),
    this.maxLines = 200,
  });

  static final RegExp _link =
      RegExp(r'((?:https?://|www\.)[^\s<>\[\]{}]+)', caseSensitive: false);

  /// Trailing punctuation belongs to the sentence, not to the link.
  static String _trim(String url) {
    var u = url;
    while (u.isNotEmpty && '.,;:!?)]}'.contains(u[u.length - 1])) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _taps = [];

  List<InlineSpan> _spans(BuildContext context) {
    final text = widget.text;
    final base = widget.style;
    final color = widget.linkColor;
    final out = <InlineSpan>[];
    var cursor = 0;
    for (final m in LinkText._link.allMatches(text)) {
      if (m.start > cursor) {
        out.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      final raw = m.group(0)!;
      final url = LinkText._trim(raw);
      if (url.isEmpty) continue;
      final tap = TapGestureRecognizer()
        ..onTap = () async {
          final target = url.startsWith('www.') ? 'https://$url' : url;
          final err = await openExternalUrl(target);
          if (err != null && context.mounted) {
            showCunnectToast(context, err, error: true);
          }
        };
      _taps.add(tap);
      out.add(TextSpan(
        text: url,
        style: base.copyWith(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
            fontWeight: FontWeight.w700),
        recognizer: tap,
      ));
      if (raw.length > url.length) {
        out.add(TextSpan(text: raw.substring(url.length)));
      }
      cursor = m.end;
    }
    if (cursor < text.length) out.add(TextSpan(text: text.substring(cursor)));
    if (out.isEmpty) out.add(TextSpan(text: text));
    return out;
  }

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.maxLines;
    return Text.rich(
      TextSpan(style: widget.style, children: _spans(context)),
      maxLines: max,
      overflow: max > 100 ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }
}
