import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/app_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import 'cart_screen.dart';
import 'my_orders_screen.dart';
import 'notifications_screen.dart';

class FoodHomeScreen extends StatefulWidget {
  const FoodHomeScreen({super.key});

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {

  final _searchController = TextEditingController();
  final _pageController = PageController();
  Timer? _liveTimer;
  int _currentSlide = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Same 3-second live polling as the Django page
    // (delivery OTP + notifications + menu availability).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = context.read<AppStore>();
      store.loadFoodHome();
      store.refreshCustomerOrders();
      store.loadNotifications();
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {});
      final st = context.read<AppStore>();
      st.refreshOrderStatuses();
      st.refreshFoodItems();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final slides = store.heroSlides;
    final items = store.searchFood(_query);
    final unread = store.unreadCountFor(AppStore.customerUserId);
    final activeDelivery = store.activeDeliveryOrder;


    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context, store, unread),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 130),
                    children: [
                      if (slides.isNotEmpty) _buildHero(slides),
                      if (activeDelivery != null) _buildOtpCard(activeDelivery),
                      if (slides.length > 1) _buildDots(slides.length),
                      if (store.offers.isNotEmpty) _buildOffers(store),
                      _buildSearch(),
                      _buildFoodList(store, items),
                    ],
                  ),
                ),
              ],
            ),
            if (store.cartCount > 0) _buildCartBar(store),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------ header
  Widget _buildHeader(BuildContext context, AppStore store, int unread) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.black,
        border: Border(bottom: BorderSide(color: Color(0xFF191919))),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const SizedBox(width: 7),
            _HeaderIconButton(
              child: const Text('‹',
                  style: TextStyle(
                      color: Color(0xFFD9D9D9),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: .75)),
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 6),
            _HeaderLink(
              icon: const Icon(Icons.receipt_long_outlined,
                  size: 15, color: AppColors.red),
              label: 'Orders',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyOrdersScreen(mode: 'food'))),
            ),
            Expanded(
              child: Center(
                child: CunnectWordmark(
                    fontSize: MediaQuery.of(context).size.width < 380 ? 20 : 26),
              ),
            ),
            _HeaderIconButton(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_outlined,
                      size: 18, color: Color(0xFFE8B84B)),
                  if (unread > 0)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(99)),
                        alignment: Alignment.center,
                        child: Text('${unread > 99 ? '99+' : unread}',
                            style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),
            const SizedBox(width: 10),
            _HeaderLink(
              icon: const Icon(Icons.shopping_cart_outlined,
                  size: 15, color: Colors.white),
              label: 'Cart',
              badge: store.cartCount > 0 ? '${store.cartCount}' : null,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CartScreen())),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------ hero slider
  Widget _buildHero(List<HeroSlide> slides) {
    return Container(
      height: 165,
      margin: const EdgeInsets.fromLTRB(8, 13, 8, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: PageView.builder(
        controller: _pageController,
        itemCount: slides.length,
        onPageChanged: (index) => setState(() => _currentSlide = index),
        itemBuilder: (context, index) {
          final slide = slides[index];
          return Stack(
            fit: StackFit.expand,
            children: [
              CunnectImage(slide.image, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0x2E000000), Color(0x05000000)]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDots(int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (index) {
          final active = index == _currentSlide;
          return GestureDetector(
            onTap: () {
              setState(() => _currentSlide = index);
              _pageController.animateToPage(index,
                  duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 15 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? AppColors.red : const Color(0xFF494949),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOtpCard(Order order) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x8CF10B1D)),
        gradient: const LinearGradient(
          begin: Alignment(-0.87, -0.5),
          end: Alignment(0.87, 0.5),
          colors: [Color(0x2EF10B1D), Color(0xE61C1C1C)],
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery partner is on the way',
                    style: TextStyle(
                        color: Color(0xFFFFABB2), fontSize: 10.5, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text('Share this OTP only after receiving your order.',
                    style: TextStyle(color: Color(0xFFDEDEDE), fontSize: 11, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(order.deliveryOtp,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 5)),
        ],
      ),
    );
  }

  // ------------------------------------------------ offers
  Widget _buildOffers(AppStore store) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Offers for you', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Swipe to explore',
                    style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: store.offers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final offer = store.offers[index];
                return _OfferCard(
                  offer: offer,
                  onApply: () async {
                    final result = await store.applyCoupon(offer.couponCode);
                    if (!context.mounted) return;
                    if (result.showPopup) {
                      _showCouponPopup(context, result.message);
                    } else {
                      showCunnectToast(context, result.message, error: !result.success);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCouponPopup(BuildContext context, String message) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Coupon applied',
      barrierColor: Colors.black.withOpacity(.72),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondary) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340,
              padding: const EdgeInsets.fromLTRB(23, 48, 23, 21),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xB3F10B1D)),
                gradient: const LinearGradient(
                    begin: Alignment(-0.7, -0.7),
                    end: Alignment(0.7, 0.7),
                    colors: [Color(0xFF242424), Color(0xFF111111)]),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(.7), blurRadius: 48, offset: const Offset(0, 18)),
                  BoxShadow(color: const Color(0x2EF10B1D), blurRadius: 30),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -74,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.785398,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.red,
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(color: const Color(0xFFF3F3F3), width: 4),
                            boxShadow: [BoxShadow(color: const Color(0x8CF10B1D), blurRadius: 15)],
                          ),
                          child: Center(
                            child: Transform.rotate(
                              angle: -0.785398,
                              child: const Text('%',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('COUPON APPLIED',
                          style: TextStyle(
                              color: Color(0xFFA9A9A9),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .9)),
                      const SizedBox(height: 9),
                      const Text('Discount unlocked!',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 11),
                      Text(message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFC4C4C4), fontSize: 13, height: 1.45)),
                      const SizedBox(height: 19),
                      SizedBox(
                        width: double.infinity,
                        height: 47,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                          child: const Text('YAY!'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------ search + list
  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF303030)),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 11),
              child: Icon(Icons.search, size: 17, color: AppColors.red),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(fontSize: 12, color: Color(0xFFF4F4F4)),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: 'Search food items...',
                  hintStyle: TextStyle(color: Color(0xFF777777), fontSize: 12),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.close, size: 14, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodList(AppStore store, List<FoodItem> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 50, horizontal: 16),
        child: Text('No food items are available right now.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 13, 14, 12),
      child: Column(
        children: [
          for (final item in items) _FoodItemRow(item: item, store: store),
        ],
      ),
    );
  }

  // ------------------------------------------------ cart bar
  Widget _buildCartBar(AppStore store) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: Color(0xFF181818),
          border: Border(top: BorderSide(color: Color(0xFF333333))),
          boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 25, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 25),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(99)),
                child: Text('${store.cartCount}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 9),
              Text('₹${store.cartTotal.round()}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const CartScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                child: const Text('View Cart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
class _HeaderIconButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: 34, height: 34, child: Center(child: child)),
    );
  }
}

class _HeaderLink extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  const _HeaderLink({required this.icon, required this.label, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 10, fontWeight: FontWeight.w800)),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 15),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(99)),
                child: Text(badge!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final FoodOffer offer;
  final VoidCallback onApply;

  const _OfferCard({required this.offer, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 255,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF343434)),
        gradient: const LinearGradient(
          begin: Alignment(-0.78, -0.63),
          end: Alignment(0.78, 0.63),
          colors: [Color(0xFF251014), Color(0xFF171717)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(offer.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SizedBox(
              width: 160,
              child: Text(offer.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFD0D0D0), fontSize: 10, height: 1.3)),
            ),
          ),
          Row(
            children: [
              if (offer.couponCode != null) DashedCouponCode(code: offer.couponCode!),
              const Spacer(),
              Material(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  onTap: onApply,
                  borderRadius: BorderRadius.circular(7),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Text('Apply Offer',
                        style: TextStyle(
                            color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FoodItemRow extends StatelessWidget {
  final FoodItem item;
  final AppStore store;

  const _FoodItemRow({required this.item, required this.store});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      margin: const EdgeInsets.only(bottom: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showDetails(context),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: CunnectImage(item.image, width: 66, height: 66, fit: BoxFit.cover),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DishNameWithMark(
                      name: item.name,
                      isVeg: item.isVeg,
                      style: const TextStyle(
                          color: Color(0xFFF4F4F4), fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('₹${item.price.round()}',
                      style: const TextStyle(color: AppColors.red, fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (item.vendorLogo.isNotEmpty) ...[
                      ClipOval(
                          child: CunnectImage(item.vendorLogo,
                              width: 14, height: 14)),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(item.vendorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 10)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.mutedAlt, fontSize: 11.5, height: 1.32)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (item.isAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _AddButton(onTap: () => store.addToCart(item.id)),
            )
          else
            Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF4A4A4A)),
              ),
              child: const Text('Unavailable',
                  style: TextStyle(color: Color(0xFFA5A5A5), fontSize: 9.5, fontWeight: FontWeight.w800)),
            ),
        ],
        ),
      ),
    );
  }

  /// ⭐ dish pe tap -> poori description bottom sheet me
  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3A),
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CunnectImage(item.image,
                          width: 84, height: 84, fit: BoxFit.cover)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DishNameWithMark(
                            name: item.name,
                            isVeg: item.isVeg,
                            maxLines: 2,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF4F4F4))),
                        const SizedBox(height: 4),
                        Text('\u20B9${item.price.round()}',
                            style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                  item.description.isEmpty
                      ? 'No description available.'
                      : item.description,
                  style: const TextStyle(
                      color: Color(0xFFB5B5B5), fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: item.isAvailable
                      ? () {
                          store.addToCart(item.id);
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF2A2A2A),
                    disabledForegroundColor: const Color(0xFF8A8A8A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(item.isAvailable
                      ? 'ADD TO CART \u2022 \u20B9${item.price.round()}'
                      : 'UNAVAILABLE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
        width: 66,
        height: 66,
        color: const Color(0xFF202020),
        alignment: Alignment.center,
        child: const Text('🍽️', style: TextStyle(fontSize: 24)),
      );
}

class _AddButton extends StatefulWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.25), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 1), weight: 55),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: InkWell(
        onTap: () {
          widget.onTap();
          _controller.forward(from: 0);
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.red),
          ),
          alignment: Alignment.center,
          child: const Text('+',
              style: TextStyle(color: Color(0xFFF4F4F4), fontSize: 20, fontWeight: FontWeight.w300, height: 1)),
        ),
      ),
    );
  }
}
