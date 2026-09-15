import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'fcm.dart';

export 'api_client.dart' show ApiConfig, ApiException;

/// Result of coupon actions so the UI can show the same
/// success popup / error toasts as the Django templates.
class CouponResult {
  final bool success;
  final String message;
  final bool showPopup;

  CouponResult(this.success, this.message, {this.showPopup = false});
}

class LoginResult {
  final bool success;
  final String message;

  LoginResult(this.success, this.message);
}

/// Vendor session info (login response).
class VendorSession {
  int id;
  String businessName;
  String vendorType; // 'food' | 'printout'
  String phone;
  String ownerUsername;
  String email;
  bool isActive;
  bool isApproved;

  VendorSession({
    this.id = 0,
    this.businessName = '',
    this.vendorType = 'food',
    this.phone = '',
    this.ownerUsername = '',
    this.email = '',
    this.isActive = true,
    this.isApproved = true,
  });
}

/// API-backed app state. Har screen sirf is class se baat karti hai —
/// saara data Django backend (backend/myproject) se aata hai.
class AppStore extends ChangeNotifier {
  AppStore({ApiClient? apiClient}) : api = apiClient ?? ApiClient() {
    // ⭐ Saved session restore — refresh/restart pe dobara login nahi.
    ApiConfig.studentToken = LocalStore.get('student_token');
    studentUid = LocalStore.get('student_uid');
    customerName = LocalStore.get('student_name') ?? '';
    studentEmail = LocalStore.get('student_email') ?? '';
    studentPhotoUrl = LocalStore.get('student_photo') ?? '';
    customerPhone = LocalStore.get('student_phone') ?? '';
    customerBranch = LocalStore.get('student_branch') ?? '';
    customerYear = LocalStore.get('student_year') ?? '';
    ApiConfig.vendorToken = LocalStore.get('vendor_token');
    umsUid = LocalStore.get('ums_uid');
    _hydrateMediaCaches();
    ApiConfig.deliveryToken = LocalStore.get('delivery_token');
    // ⭐ Vendor session restore — app reopen pe seedha vendor dashboard
    if (ApiConfig.vendorToken != null &&
        (LocalStore.get('vendor_id') ?? '') != '') {
      vendor = VendorSession(
        id: int.tryParse(LocalStore.get('vendor_id') ?? '') ?? 0,
        businessName: LocalStore.get('vendor_name') ?? '',
        vendorType: LocalStore.get('vendor_type') ?? 'food',
        phone: LocalStore.get('vendor_phone') ?? '',
        ownerUsername: LocalStore.get('vendor_owner') ?? '',
        email: LocalStore.get('vendor_email') ?? '',
      );
    }
  }

  final ApiClient api;

  // Legacy constants — kuch purani screens inhe use karti hain.
  static const int customerUserId = 1;
  static const int vendorUserId = 2;
  static const int deliveryUserId = 3;
  static const String defaultAddress =
      'Chandigarh University, GT Road, Mohali';
  static const String defaultLandmark = 'Main Campus Gate';

  // ------------------------------------------------------------------
  // Session / connection
  // ------------------------------------------------------------------
  bool serverReachable = true;
  String? lastError;

  String? get studentToken => ApiConfig.studentToken;

  bool get studentLoggedIn => ApiConfig.studentToken != null;

  String? studentUid;
  String customerName = '';
  String customerPhone = '';
  String customerBranch = '';
  String customerYear = '';
  String studentEmail = '';
  String studentPhotoUrl = ''; // /media/profile_photos/... (relative)

  void _fail(Object error) {
    lastError = error.toString();
    serverReachable = lastError != null;
  }

  // ------------------------------------------------------------------
  // Student auth + dashboard
  // ------------------------------------------------------------------
  final List<DashboardBanner> _banners = [];
  List<DashboardBanner> get dashboardBanners => _banners;

  // ⭐ ORIGINAL main-auth flow (register + OTP + captcha login + step3)
  Future<Map<String, dynamic>> authLogin1(String uid) async {
    try {
      final r = await api.post('/api/auth/login1/', body: {'uid': uid.trim()});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ⭐ Forgot password: email pe OTP bhejo.
  Future<Map<String, dynamic>> authForgot(String uid) async {
    try {
      final r = await api.post('/api/auth/forgot/', body: {'uid': uid.trim()});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ⭐ OTP + naya password -> reset.
  Future<Map<String, dynamic>> authReset(
      String uid, String otp, String password) async {
    try {
      final r = await api.post('/api/auth/reset-password/',
          body: {'uid': uid.trim(), 'otp': otp.trim(), 'password': password});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> authLogin2(
      String uid, String password, String captcha) async {
    try {
      final r = await api.post('/api/auth/login2/',
          body: {'uid': uid.trim(), 'password': password, 'captcha': captcha});
      final data = api.dataOf(r);
      ApiConfig.studentToken = data['token'] as String?;
      studentUid = (data['uid'] ?? uid.trim()) as String;
      customerName = (data['name'] ?? '') as String;
      _clearUmsMemory(); // naya app user -> purana UMS hatao
      studentEmail = (data['email'] ?? '') as String;
      studentPhotoUrl = (data['photo_url'] ?? '') as String;
      customerPhone = (data['phone'] ?? '') as String;
      customerBranch = (data['branch'] ?? '') as String;
      customerYear = (data['year'] ?? '') as String;
      LocalStore.set('student_token', ApiConfig.studentToken ?? '');
      LocalStore.set('student_uid', studentUid ?? '');
      LocalStore.set('student_name', customerName);
      LocalStore.set('student_email', studentEmail);
      registerFcmToken();
      LocalStore.set('student_photo', studentPhotoUrl);
      LocalStore.set('student_phone', customerPhone);
      serverReachable = true;
      lastError = null;
      notifyListeners();
      unawaitedLoadDashboardBanners();
      return data;
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> authRegister(Map<String, dynamic> body) async {
    try {
      final r = await api.post('/api/auth/register/', body: body);
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> authOtpVerify(
      String userId, String otp) async {
    try {
      final r = await api
          .post('/api/auth/otp-verify/', body: {'user_id': userId, 'otp': otp});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> authResendOtp(String userId) async {
    try {
      final r =
          await api.post('/api/auth/resend-otp/', body: {'user_id': userId});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> authCompleteProfile(
      Map<String, dynamic> body) async {
    try {
      final r = await api.post('/api/auth/complete-profile/',
          body: body, token: ApiConfig.studentToken);
      final d = api.dataOf(r);
      // ⭐ photo/email dashboard tak pahunchao
      if (d['email'] != null) {
        studentEmail = '${d['email']}';
        LocalStore.set('student_email', studentEmail);
      }
      if (d['photo_url'] != null) {
        studentPhotoUrl = '${d['photo_url']}';
        LocalStore.set('student_photo', studentPhotoUrl);
      }
      if (d['phone'] != null) {
        customerPhone = '${d['phone']}';
        LocalStore.set('student_phone', customerPhone);
      }
      if (d['branch'] != null) {
        customerBranch = '${d['branch']}';
        LocalStore.set('student_branch', customerBranch);
      }
      if (d['year'] != null) {
        customerYear = '${d['year']}';
        LocalStore.set('student_year', customerYear);
      }
      notifyListeners();
      return d;
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ⭐ Support Us form — backend student/support/ pe save hota hai.
  Future<Map<String, dynamic>> studentSupport(
      String subject, String message) async {
    try {
      final r = await api.post('/api/student/support/',
          body: {
            'subject': subject,
            'message': message,
            'email': studentEmail,
          },
          token: ApiConfig.studentToken);
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<String?> studentLogin(String uid, String password) async {
    try {
      final response = await api.post('/api/auth/student-login/', body: {
        'uid': uid.trim(),
        'password': password,
      });
      final data = api.dataOf(response);
      ApiConfig.studentToken = data['token'] as String?;
      studentUid = (data['uid'] ?? uid.trim()) as String;
      customerName = (data['name'] ?? '') as String;
      LocalStore.set('student_token', ApiConfig.studentToken ?? '');
      LocalStore.set('student_uid', studentUid ?? '');
      LocalStore.set('student_name', customerName);
      customerPhone = (data['phone'] ?? '') as String;
      customerBranch = (data['branch'] ?? '') as String;
      customerYear = (data['year'] ?? '') as String;
      studentEmail = (data['email'] ?? '') as String;
      studentPhotoUrl = (data['photo_url'] ?? '') as String;
      LocalStore.set('student_email', studentEmail);
      LocalStore.set('student_photo', studentPhotoUrl);
      LocalStore.set('student_phone', customerPhone);
      LocalStore.set('student_branch', customerBranch);
      LocalStore.set('student_year', customerYear);
      serverReachable = true;
      lastError = null;
      notifyListeners();
      // Dashboard banners turant le aao (home hero ke liye).
      unawaitedLoadDashboardBanners();
      return null;
    } catch (error) {
      _fail(error);
      notifyListeners();
      return error.toString();
    }
  }

  Future<void> studentLogout() async {
    ApiConfig.studentToken = null;
    LocalStore.remove('student_token');
    LocalStore.remove('student_uid');
    LocalStore.remove('student_name');
    studentUid = null;
    // ⭐ multi-student: app user badle to purana UMS memory se hatao
    umsUid = null;
    LocalStore.remove('ums_uid');
    _umsDashboard = {};
    umsNeedsCaptcha = false;
    umsCaptchaB64 = null;
    notifyListeners();
  }

  /// ⭐ Cached banners/food-home turant render (network se pehle).
  void _hydrateMediaCaches() {
    try {
      final b = LocalStore.get('cache_banners');
      if (b != null && b.isNotEmpty && _banners.isEmpty) {
        final list = (jsonDecode(b) as List? ?? []);
        _banners.addAll([
          for (final e in list)
            DashboardBanner.fromJson(
                (e as Map).cast<String, dynamic>(), ApiConfig.media),
        ]);
      }
      final f = LocalStore.get('cache_food_home');
      if (f != null && f.isNotEmpty && _foodItems.isEmpty) {
        final data = (jsonDecode(f) as Map).cast<String, dynamic>();
        _foodItems.addAll([
          for (final e in (data['items'] as List? ?? []))
            FoodItem.fromJson(
                (e as Map).cast<String, dynamic>(), ApiConfig.media),
        ]);
        _heroSlides.addAll([
          for (final e in (data['hero_slides'] as List? ?? []))
            HeroSlide.fromJson(
                (e as Map).cast<String, dynamic>(), ApiConfig.media),
        ]);
        _offers.addAll([
          for (final e in (data['offers'] as List? ?? []))
            FoodOffer.fromJson(
                (e as Map).cast<String, dynamic>(), ApiConfig.media),
        ]);
      }
      if (_banners.isNotEmpty || _foodItems.isNotEmpty) {
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> loadDashboardBanners() async {
    try {
      final response = await api.get('/api/student/dashboard/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _banners
        ..clear()
        ..addAll([
          for (final banner in (data['banners'] as List? ?? []))
            DashboardBanner.fromJson(
                banner as Map<String, dynamic>, ApiConfig.media),
        ]);
      LocalStore.set('cache_banners', jsonEncode(data['banners'] ?? []));
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  void unawaitedLoadDashboardBanners() {
    loadDashboardBanners();
  }

  Future<String?> sendSupportRequest(String subject, String message) async {
    try {
      await api.post('/api/student/support/',
          token: ApiConfig.studentToken,
          body: {'subject': subject, 'message': message});
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  // ------------------------------------------------------------------
  // Food home / cart / coupons / orders
  // ------------------------------------------------------------------
  final List<FoodItem> _foodItems = [];
  final List<HeroSlide> _heroSlides = [];
  final List<FoodOffer> _offers = [];
  final List<Coupon> _coupons = [];
  final List<CartItem> _cart = [];
  Coupon? _appliedCoupon;
  final List<Order> _customerOrders = [];
  final List<Order> _recentOrderSuccess = [];
  final List<AppNotification> _notifications = [];
  int _unreadCount = 0;

  List<FoodItem> get foodItems => _foodItems;
  List<HeroSlide> get heroSlides => _heroSlides;
  List<FoodOffer> get offers => _offers;
  List<Coupon> get coupons => _coupons;
  List<Coupon> get availableCoupons => _coupons;
  Coupon? get appliedCoupon => _appliedCoupon;
  List<CartItem> get cart => _cart;
  List<Order> get customerOrders => _customerOrders;
  List<Order> get recentOrderSuccess => _recentOrderSuccess;
  List<AppNotification> get notifications => _notifications;

  /// ⭐ sirf food items refresh — delete/kitchen change turant dikhe
  Future<void> refreshFoodItems() async {
    try {
      final response =
          await api.get('/api/food/home/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _foodItems
        ..clear()
        ..addAll([
          for (final item in (data['items'] as List? ?? []))
            FoodItem.fromJson(item as Map<String, dynamic>, ApiConfig.media),
        ]);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadFoodHome() async {
    try {
      final response =
          await api.get('/api/food/home/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _foodItems
        ..clear()
        ..addAll([
          for (final item in (data['items'] as List? ?? []))
            FoodItem.fromJson(item as Map<String, dynamic>, ApiConfig.media),
        ]);
      _heroSlides
        ..clear()
        ..addAll([
          for (final slide in (data['hero_slides'] as List? ?? []))
            HeroSlide.fromJson(slide as Map<String, dynamic>, ApiConfig.media),
        ]);
      _offers
        ..clear()
        ..addAll([
          for (final offer in (data['offers'] as List? ?? []))
            FoodOffer.fromJson(offer as Map<String, dynamic>, ApiConfig.media),
        ]);
      _coupons
        ..clear()
        ..addAll([
          for (final coupon in (data['coupons'] as List? ?? []))
            Coupon.fromJson(coupon as Map<String, dynamic>),
        ]);
      LocalStore.set('cache_food_home', jsonEncode({
            'items': data['items'] ?? [],
            'hero_slides': data['hero_slides'] ?? [],
            'offers': data['offers'] ?? [],
          }));
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  List<FoodItem> searchFood(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _foodItems;
    return _foodItems
        .where((item) =>
            item.name.toLowerCase().contains(q) ||
            item.description.toLowerCase().contains(q) ||
            item.category.toLowerCase().contains(q))
        .toList();
  }

  void addToCart(int itemId) {
    final item = _foodItems.where((f) => f.id == itemId).firstOrNull;
    if (item == null) return;
    final existing =
        _cart.where((c) => c.foodItem.id == itemId).firstOrNull;
    if (existing != null) {
      existing.quantity += 1;
    } else {
      _cart.add(CartItem(foodItem: item));
    }
    notifyListeners();
  }

  /// 'increase' | 'decrease' | 'remove' — cart.html ke buttons jaise.
  void updateCartItem(int itemId, String action) {
    final existing =
        _cart.where((c) => c.foodItem.id == itemId).firstOrNull;
    if (existing == null) return;
    switch (action) {
      case 'increase':
        existing.quantity += 1;
        break;
      case 'decrease':
        existing.quantity -= 1;
        if (existing.quantity <= 0) _cart.remove(existing);
        break;
      case 'remove':
        _cart.remove(existing);
        break;
    }
    _revalidateCoupon();
    notifyListeners();
  }

  double get cartTotal =>
      _cart.fold<double>(0, (sum, item) => sum + item.lineTotal);

  int get cartCount => _cart.fold<int>(0, (sum, item) => sum + item.quantity);

  double get couponDiscount {
    final coupon = _appliedCoupon;
    if (coupon == null) return 0;
    final total = cartTotal;
    final discount = coupon.discountType == 'percent'
        ? total * coupon.discountValue / 100
        : coupon.discountValue;
    return discount > total ? total : discount;
  }

  double get finalTotal => cartTotal - couponDiscount;

  void _revalidateCoupon() {
    final coupon = _appliedCoupon;
    if (coupon == null) return;
    if (cartTotal < coupon.minimumOrderValue) _appliedCoupon = null;
  }

  Future<CouponResult> applyCoupon(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return CouponResult(false, 'Enter a coupon code.');
    }
    if (_cart.isEmpty) {
      return CouponResult(false, 'Add something to the cart first.');
    }
    try {
      final response = await api.post('/api/food/coupon/validate/',
          token: ApiConfig.studentToken,
          body: {'code': trimmed, 'order_total': cartTotal});
      final data = api.dataOf(response);
      _appliedCoupon = Coupon.fromJson(data);
      notifyListeners();
      final applied = _appliedCoupon;
      if (applied != null &&
          applied.discountType == 'percent' &&
          applied.discountValue >= 10) {
        // Django template: bada discount milne par popup dikhata hai.
        return CouponResult(
            true, 'Coupon applied — ${applied.discountLabel}',
            showPopup: true);
      }
      return CouponResult(
          true, '${applied?.code ?? trimmed} applied successfully');
    } on ApiException catch (error) {
      return CouponResult(false, error.message);
    } catch (error) {
      return CouponResult(false, error.toString());
    }
  }

  void removeCoupon() {
    _appliedCoupon = null;
    notifyListeners();
  }

  /// Order place karo. Error hone par message return hota hai, warna null.
  Future<Map<String, dynamic>> fetchVendorUpiInfo() async {
    try {
      final r = await api.get('/api/vendor/upi/', token: ApiConfig.vendorToken);
      return api.dataOf(r);
    } catch (_) {
      return {};
    }
  }

  Future<String> fetchVendorUpi() async {
    final info = await fetchVendorUpiInfo();
    return (info['upi_id'] ?? '') as String;
  }

  Future<void> apiPostRemoveQr() async {
    await api.post('/api/vendor/upi-qr-upload/',
        token: ApiConfig.vendorToken, body: {'remove': '1'});
  }

  Future<String?> uploadVendorLogo(Uint8List bytes, String fileName) async {
    try {
      await api.postMultipart('/api/vendor/logo-upload/',
          fields: {}, fileBytes: bytes, fileName: fileName,
          fileField: 'file', token: ApiConfig.vendorToken);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// ⭐ Vendor apna QR image upload kare — error null warna message.
  Future<String?> uploadVendorQr(Uint8List bytes, String fileName) async {
    try {
      await api.postMultipart('/api/vendor/upi-qr-upload/',
          fields: {}, fileBytes: bytes, fileName: fileName,
          fileField: 'file', token: ApiConfig.vendorToken);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> saveVendorUpi(String upi) async {
    try {
      await api.post('/api/vendor/upi/',
          token: ApiConfig.vendorToken, body: {'upi_id': upi});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// ⭐ Vendor UPI QR (checkout pe scan-and-pay)
  Future<Map<String, dynamic>?> fetchUpiQr(int vendorId, num amount) async {
    try {
      final r = await api.get(
          '/api/food/upi-qr/?vendor_id=$vendorId&amount=$amount');
      return api.dataOf(r);
    } catch (_) {
      return null;
    }
  }

  Future<String?> placeOrder(
      {required String paymentMethod,
      required String orderNote,
      String customerUpi = '',
      String txnId = ''}) async {
    if (_cart.isEmpty) return 'Your cart is empty.';
    try {
      final response = await api.post('/api/food/orders/',
          token: ApiConfig.studentToken, body: {
        'payment': paymentMethod,
        'note': orderNote,
        'customer_upi': customerUpi,
        'txn_id': txnId,
        'address': defaultAddress,
        'landmark': defaultLandmark,
        'items': [
          for (final item in _cart)
            {'item_id': item.foodItem.id, 'quantity': item.quantity},
        ],
        if (_appliedCoupon != null) 'coupon_code': _appliedCoupon!.code,
      });
      final data = api.dataOf(response);
      _recentOrderSuccess
        ..clear()
        ..addAll([
          for (final order in (data['orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _cart.clear();
      _appliedCoupon = null;
      notifyListeners();
      unawaitedRefreshCustomerOrders();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  void unawaitedRefreshCustomerOrders() {
    refreshCustomerOrders();
  }

  Future<void> refreshCustomerOrders() async {
    try {
      final response = await api.get('/api/food/my-orders/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _customerOrders
        ..clear()
        ..addAll([
          for (final order in (data['orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  /// Food home ka 3-second live poll — sirf status refresh.
  Future<void> refreshOrderStatuses() async {
    try {
      final response = await api.get('/api/food/orders/status/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _customerOrders
        ..clear()
        ..addAll([
          for (final order in (data['orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      serverReachable = true;
      notifyListeners();
    } catch (_) {
      // Silent poll — UI disturb nahi karna.
    }
  }

  // ---------- notifications ----------

  Future<void> loadNotifications() async {
    try {
      final response = await api.get('/api/food/notifications/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _notifications
        ..clear()
        ..addAll([
          for (final notification in (data['notifications'] as List? ?? []))
            AppNotification.fromJson(notification as Map<String, dynamic>),
        ]);
      _unreadCount = (data['unread_count'] ??
              _notifications.where((n) => !n.isRead).length)
          as int;
      notifyListeners();
    } catch (_) {}
  }

  /// ⭐ local (client-side) notification — UMS attendance / vendor new order
  void addLocalNotification(String title, String message) {
    showCunnectPopup(title, message,
        vendor: title.toLowerCase().contains('new order'));
    _notifications.insert(
        0,
        AppNotification(
            id: -DateTime.now().millisecondsSinceEpoch,
            title: title,
            message: message,
            isRead: false,
            createdAt: DateTime.now()));
    notifyListeners();
  }

  List<AppNotification> notificationsFor(int userId) {
    return _notifications;
  }

  int unreadCountFor(int userId) => _unreadCount;

  Future<void> markAllRead(int userId) async {
    try {
      await api.post('/api/food/notifications/read/',
          token: ApiConfig.studentToken, body: {});
      for (final notification in _notifications) {
        // AppNotification immutable fields — list replace karte hain.
      }
      _unreadCount = 0;
      _notifications.clear();
      notifyListeners();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Vendor portal
  // ------------------------------------------------------------------
  VendorSession vendor = VendorSession();
  final List<Order> _vendorIncoming = [];
  final List<Order> _vendorActive = [];
  final List<Order> _vendorHistory = [];
  final List<Order> _vendorOutForDelivery = [];
  final List<FoodItem> _menuItems = [];
  bool _kitchenOpen = true;
  int _todaySales = 0;
  int _menuCount = 0;
  int _availableCount = 0;

  List<Order> get vendorIncomingOrders => _vendorIncoming;
  List<Order> get vendorActiveOrders => _vendorActive;
  List<Order> get vendorOrderHistory => _vendorHistory;
  List<FoodItem> get menuItems => _menuItems;
  bool get kitchenOpen => _kitchenOpen;
  bool vendorAlertsEnabled = false;
  int get todaySales => _todaySales;

  Future<LoginResult> vendorLogin(String phone, String password) async {
    try {
      final response = await api.post('/api/vendor/login/',
          body: {'phone': phone.trim(), 'password': password});
      final data = api.dataOf(response);
      ApiConfig.vendorToken = data['token'] as String?;
      LocalStore.set('vendor_token', ApiConfig.vendorToken ?? '');
      vendor = VendorSession(
        id: (data['vendor_id'] ?? 0) as int,
        businessName: (data['business_name'] ?? '') as String,
        vendorType: (data['vendor_type'] ?? 'food') as String,
        phone: (data['phone'] ?? phone) as String,
        ownerUsername: (data['owner_username'] ?? (data['business_name'] ?? '')) as String,
        email: (data['email'] ?? '') as String,
        isActive: true,
        isApproved: true,
      );
      LocalStore.set('vendor_id', '${vendor.id}');
      LocalStore.set('vendor_name', vendor.businessName);
      LocalStore.set('vendor_type', vendor.vendorType);
      LocalStore.set('vendor_phone', vendor.phone);
      LocalStore.set('vendor_owner', vendor.ownerUsername);
      LocalStore.set('vendor_email', vendor.email);
      serverReachable = true;
      notifyListeners();
      registerFcmToken(null, 'vendor');
      return LoginResult(true, 'Welcome, ${vendor.businessName}');
    } on ApiException catch (error) {
      return LoginResult(false, error.message);
    } catch (error) {
      return LoginResult(false, error.toString());
    }
  }

  Future<void> vendorLogout() async {
    ApiConfig.vendorToken = null;
    LocalStore.remove('vendor_token');
    for (final k in ['vendor_id', 'vendor_name', 'vendor_type',
      'vendor_phone', 'vendor_owner', 'vendor_email']) {
      LocalStore.remove(k);
    }
    vendor = VendorSession();
    notifyListeners();
  }

  /// ⭐ vendor repeat-ring band (manual silence)
  Future<void> vendorSilence(int orderId) async {
    try {
      await api.post('/api/vendor/silence/',
          body: {'id': orderId}, token: ApiConfig.vendorToken);
    } catch (_) {}
  }

  Future<void> refreshVendorDashboard() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response = await api.get('/api/vendor/dashboard/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      final oldIds = <int>{for (final o in _vendorIncoming) o.id};
      _vendorIncoming
        ..clear()
        ..addAll([
          for (final order in (data['incoming_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      if (oldIds.isNotEmpty) {
        for (final o in _vendorIncoming) {
          if (!oldIds.contains(o.id)) {
            addLocalNotification('New order received',
                '${o.orderNumber} \u2022 ${o.customerName}');
          }
        }
      }
      _vendorActive
        ..clear()
        ..addAll([
          for (final order in (data['active_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _vendorHistory
        ..clear()
        ..addAll([
          for (final order in (data['history_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _vendorOutForDelivery
        ..clear()
        ..addAll([
          for (final order in (data['out_for_delivery_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _todaySales = ((data['today_sales'] ?? 0) as num).round();
      _kitchenOpen = (data['kitchen_open'] ?? true) as bool;
      _menuCount = (data['menu_count'] ?? 0) as int;
      _availableCount = (data['available_count'] ?? 0) as int;
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> vendorUpdateOrderStatus(int orderId, String action) async {
    // ⭐ optimistic: UI turant update, server sync background me
    Order? moved;
    final i1 = _vendorIncoming.indexWhere((o) => o.id == orderId);
    if (i1 >= 0) {
      moved = _vendorIncoming.removeAt(i1);
    } else {
      final i2 = _vendorActive.indexWhere((o) => o.id == orderId);
      if (i2 >= 0) moved = _vendorActive[i2];
    }
    if (moved != null) {
      if (action == 'accept') {
        moved.status = OrderStatus.accepted;
        _vendorActive.insert(0, moved);
      } else if (action == 'reject') {
        moved.status = OrderStatus.rejected;
      } else if (action == 'prepare') {
        moved.status = OrderStatus.preparing;
      } else if (action == 'ready') {
        moved.status = OrderStatus.ready;
      }
      notifyListeners();
    }
    try {
      await api.post('/api/vendor/orders/$orderId/$action/',
          token: ApiConfig.vendorToken, body: {});
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
    refreshVendorDashboard();
  }

  /// Vendor khud deliver karta hai: start-delivery se OTP flow shuru.
  Future<String?> startDelivery(int orderId, {String? partnerId}) async {
    try {
      await api.post('/api/vendor/orders/$orderId/start-delivery/',
          token: ApiConfig.vendorToken, body: {});
      refreshVendorDashboard();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<String?> verifyVendorDeliveryOtp(int orderId, String otp) async {
    try {
      await api.post('/api/vendor/orders/$orderId/verify-otp/',
          token: ApiConfig.vendorToken, body: {'otp': otp.trim()});
      refreshVendorDashboard();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> loadVendorMenu() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response =
          await api.get('/api/vendor/menu/', token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _menuItems
        ..clear()
        ..addAll([
          for (final item in (data['items'] as List? ?? []))
            FoodItem.fromJson(item as Map<String, dynamic>, ApiConfig.media),
        ]);
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> toggleItemAvailability(int itemId) async {
    // ⭐ optimistic: toggle turant UI me, server sync background me
    final idx = _menuItems.indexWhere((f) => f.id == itemId);
    if (idx >= 0) {
      _menuItems[idx].isAvailable = !_menuItems[idx].isAvailable;
      notifyListeners();
    }
    try {
      await api.post('/api/vendor/menu/$itemId/toggle/',
          token: ApiConfig.vendorToken, body: {});
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
    loadVendorMenu();
  }

  /// ⭐ menu item permanent delete
  Future<void> deleteMenuItem(int itemId) async {
    try {
      await api.post('/api/vendor/menu/$itemId/delete/',
          token: ApiConfig.vendorToken, body: {});
      await loadVendorMenu();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> saveFoodItem({
    int? id,
    required String name,
    required double price,
    required String description,
    required String category,
    required bool isAvailable,
    int stock = 0,
  }) async {
    try {
      final path = id == null ? '/api/vendor/menu/add/' : '/api/vendor/menu/$id/edit/';
      final r = await api.post(path, token: ApiConfig.vendorToken, body: {
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        'is_available': isAvailable,
        'stock': stock,
      });
      await loadVendorMenu();
      final item = (api.dataOf(r)['item'] as Map?)?.cast<String, dynamic>();
      return {'id': item?['id']};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  Future<String?> uploadMenuItemPhoto(int id, Uint8List bytes, String fileName) async {
    try {
      await api.postMultipart('/api/vendor/menu/$id/photo/',
          fields: {}, fileBytes: bytes, fileName: fileName,
          fileField: 'file', token: ApiConfig.vendorToken);
      await loadVendorMenu();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> setKitchenOpen(bool open) async {
    try {
      await api.post('/api/vendor/kitchen/${open ? 'on' : 'off'}/',
          token: ApiConfig.vendorToken, body: {});
      _kitchenOpen = open;
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<String?> saveVendorProfile({
    required String businessName,
    required String phone,
  }) async {
    // Backend par vendor profile update endpoint nahi hai; local update.
    vendor.businessName = businessName;
    notifyListeners();
    return null;
  }

  // ---------- vendor earnings ----------
  final List<Order> _completedOrders = [];
  final List<MapEntry<String, double>> _weeklyEarnings = [];
  double _weekTotal = 0;

  List<MapEntry<String, double>> get weeklyEarnings => _weeklyEarnings;
  double get weekTotal => _weekTotal;

  Future<void> loadVendorEarnings() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response = await api.get('/api/vendor/earnings/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _completedOrders
        ..clear()
        ..addAll([
          for (final order in (data['completed_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _weeklyEarnings
        ..clear()
        ..addAll([
          for (final entry in (data['weekly'] as List? ?? []))
            MapEntry((entry['label'] ?? '') as String,
                ((entry['total'] ?? 0) as num).toDouble()),
        ]);
      _weekTotal = ((data['week_total'] ?? 0) as num).toDouble();
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  List<Order> _ordersForYear(int? year) => year == null
      ? _completedOrders
      : _completedOrders.where((o) => o.createdAt.year == year).toList();

  /// 12 months ki sales — earnings chart ke bars.
  List<MapEntry<String, double>> monthlySales(int year) {
    const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    return [
      for (var m = 1; m <= 12; m++)
        MapEntry(labels[m - 1], monthlyTotal(year, m)),
    ];
  }

  double monthlyTotal(int year, int month) => _completedOrders
      .where((o) => o.createdAt.year == year && o.createdAt.month == month)
      .fold<double>(0, (sum, o) => sum + o.total);

  List<int> get availableYears {
    final years = <int>{};
    for (final order in _completedOrders) {
      years.add(order.createdAt.year);
    }
    years.add(DateTime.now().year);
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  double yearlyTotal(int year) => _completedOrders
      .where((o) => o.createdAt.year == year)
      .fold<double>(0, (sum, o) => sum + o.total);

  double get todayEarnings {
    final now = DateTime.now();
    return _completedOrders
        .where((o) =>
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .fold<double>(0, (sum, o) => sum + o.total);
  }

  List<Order> recentEarnings(int year, {int limit = 5}) =>
      _ordersForYear(year).take(limit).toList();

  int completedOrderCount([int? year]) => _ordersForYear(year).length;

  double averageOrderValue([int? year]) {
    final orders = _ordersForYear(year);
    if (orders.isEmpty) return 0;
    return orders.fold<double>(0, (s, o) => s + o.total) / orders.length;
  }

  // ------------------------------------------------------------------
  // Delivery portal
  // ------------------------------------------------------------------
  final List<Order> _readyOrders = [];
  final List<Order> _deliveryActive = [];
  final List<Order> _deliveryHistory = [];
  bool _deliveryAlertsEnabled = false;
  String? _activeDeliveryPartnerId;

  bool get deliveryAlertsEnabled => _deliveryAlertsEnabled;
  String? get activeDeliveryPartnerId => _activeDeliveryPartnerId;

  /// Delivery partner session mein ye lists delivery dashboard se aati hain;
  /// vendor session mein vendor apne orders ka delivery panel dekhata hai.
  List<Order> get readyOrders {
    if (ApiConfig.deliveryToken != null) return _readyOrders;
    return _vendorActive.where((o) => o.status == OrderStatus.ready).toList();
  }

  List<Order> get outForDeliveryOrders {
    if (ApiConfig.deliveryToken != null) return _deliveryActive;
    return _vendorOutForDelivery;
  }

  List<Order> get deliveredOrders {
    if (ApiConfig.deliveryToken != null) return _deliveryHistory;
    return _vendorHistory
        .where((o) => o.status == OrderStatus.completed)
        .toList();
  }

  Order? get activeDeliveryOrder =>
      _deliveryActive.isNotEmpty ? _deliveryActive.first : null;

  void enableDeliveryAlerts() {
    _deliveryAlertsEnabled = !_deliveryAlertsEnabled;
    notifyListeners();
  }

  Future<LoginResult> deliveryLogin(String phone, String password) async {
    try {
      final response = await api.post('/api/delivery/login/',
          body: {'phone': phone.trim(), 'password': password});
      final data = api.dataOf(response);
      ApiConfig.deliveryToken = data['token'] as String?;
      LocalStore.set('delivery_token', ApiConfig.deliveryToken ?? '');
      _activeDeliveryPartnerId = (data['partner_id'] ?? '').toString();
      serverReachable = true;
      notifyListeners();
      return LoginResult(true, 'Welcome aboard');
    } on ApiException catch (error) {
      return LoginResult(false, error.message);
    } catch (error) {
      return LoginResult(false, error.toString());
    }
  }

  Future<void> deliveryLogout() async {
    ApiConfig.deliveryToken = null;
    LocalStore.remove('delivery_token');
    notifyListeners();
  }

  Future<void> refreshDeliveryDashboard() async {
    if (ApiConfig.deliveryToken == null) return;
    try {
      final response = await api.get('/api/delivery/dashboard/',
          token: ApiConfig.deliveryToken);
      final data = api.dataOf(response);
      _readyOrders
        ..clear()
        ..addAll([
          for (final order in (data['ready_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _deliveryActive
        ..clear()
        ..addAll([
          for (final order in (data['active_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      _deliveryHistory
        ..clear()
        ..addAll([
          for (final order in (data['history_orders'] as List? ?? []))
            Order.fromJson(order as Map<String, dynamic>),
        ]);
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<String?> claimDeliveryOrder(int orderId) async {
    try {
      await api.post('/api/delivery/claim/$orderId/',
          token: ApiConfig.deliveryToken, body: {});
      await refreshDeliveryDashboard();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<String?> verifyDeliveryOtp(int orderId, String otp) async {
    try {
      await api.post('/api/delivery/verify-otp/$orderId/',
          token: ApiConfig.deliveryToken, body: {'otp': otp.trim()});
      await refreshDeliveryDashboard();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  // ------------------------------------------------------------------
  // Printout
  // ------------------------------------------------------------------
  final List<PrintVendor> _printVendors = [];
  final List<PrintOrder> _printOrders = [];
  final List<PrintOrder> _printVendorOrders = [];

  List<PrintVendor> get printVendors => _printVendors;
  List<PrintOrder> get printOrders => _printOrders;
  List<PrintOrder> get printVendorOrders => _printVendorOrders;

  Future<void> loadPrintVendors() async {
    try {
      final response =
          await api.get('/api/print/vendors/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _printVendors
        ..clear()
        ..addAll([
          for (final vendor in (data['vendors'] as List? ?? []))
            PrintVendor.fromJson(vendor as Map<String, dynamic>),
        ]);
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<String?> placePrintOrder({
    required int vendorId,
    required Uint8List fileBytes,
    required String fileName,
    required int copies,
    required String printSide,
    required String bwPageRanges,
    required String colorPageRanges,
    required String notes,
  }) async {
    try {
      final response = await api.postMultipart('/api/print/orders/',
          token: ApiConfig.studentToken,
          fields: {
            'vendor_id': vendorId.toString(),
            'copies': copies.toString(),
            'print_side': printSide,
            'bw_page_ranges': bwPageRanges,
            'color_page_ranges': colorPageRanges,
            'notes': notes,
          },
          fileBytes: fileBytes,
          fileName: fileName,
          fileField: 'document');
      api.dataOf(response);
      await loadMyPrintOrders();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  /// ⭐ PDF ke pages server-side count (dropdowns bharne ke liye).
  Future<Map<String, dynamic>> printPageCount(
      Uint8List bytes, String fileName) async {
    try {
      final response = await api.postMultipart('/api/print/pages/',
          token: ApiConfig.studentToken,
          fields: const {},
          fileBytes: bytes,
          fileName: fileName,
          fileField: 'document');
      return api.dataOf(response);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> loadMyPrintOrders() async {
    try {
      final response = await api.get('/api/print/my-orders/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _printOrders
        ..clear()
        ..addAll([
          for (final order in (data['orders'] as List? ?? []))
            PrintOrder.fromJson(order as Map<String, dynamic>, ApiConfig.media),
        ]);
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> loadPrintVendorDashboard() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response = await api.get('/api/print/vendor/dashboard/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _printVendorOrders
        ..clear()
        ..addAll([
          for (final order in (data['orders'] as List? ?? []))
            PrintOrder.fromJson(order as Map<String, dynamic>, ApiConfig.media),
        ]);
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> updatePrintOrderStatus(int orderId, String action) async {
    try {
      await api.post('/api/print/orders/$orderId/$action/',
          token: ApiConfig.vendorToken, body: {});
      await loadPrintVendorDashboard();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  /// Vendor dashboard ke status action buttons — Django template jaise.
  List<(String, String)> printNextActions(PrintOrder order) {
    switch (order.status) {
      case PrintOrderStatus.pending:
        return [('Accept', 'accept'), ('Reject', 'reject')];
      case PrintOrderStatus.accepted:
        return [('Start Printing', 'printing')];
      case PrintOrderStatus.printing:
        return [('Mark Ready', 'ready')];
      case PrintOrderStatus.ready:
        return [('Complete', 'complete')];
      case PrintOrderStatus.completed:
      case PrintOrderStatus.rejected:
        return [];
    }
  }

  Future<String?> updatePrintPrices(
      {required double bwPrice, required double colorPrice}) async {
    try {
      await api.post('/api/print/vendor/prices/',
          token: ApiConfig.vendorToken,
          body: {'bw_price_per_page': bwPrice, 'color_price_per_page': colorPrice});
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  // ------------------------------------------------------------------
  // Store
  // ------------------------------------------------------------------
  final List<Map<String, dynamic>> _storeCategories = [];
  List<Map<String, dynamic>> get storeCategories => _storeCategories;

  Future<void> loadStoreHome() async {
    try {
      final response =
          await api.get('/api/store/home/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _storeCategories
        ..clear()
        ..addAll([
          for (final category in (data['categories'] as List? ?? []))
            category as Map<String, dynamic>,
        ]);
      // Print vendors bhi store home par dikhte hain.
      _printVendors
        ..clear()
        ..addAll([
          for (final vendor in (data['print_vendors'] as List? ?? []))
            PrintVendor.fromJson(vendor as Map<String, dynamic>),
        ]);
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------
  // ⭐ Hostel Essentials 8-in-1 pack (₹1799)
  // ------------------------------------------------------------------
  Map<String, dynamic> _hostelInfo = {};
  Map<String, dynamic> get hostelInfo => _hostelInfo;

  Future<Map<String, dynamic>> loadHostelInfo() async {
    try {
      final response =
          await api.get('/api/store/hostel/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _hostelInfo = data;
      notifyListeners();
      return data;
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> placeHostelOrder(
      Map<String, dynamic> body) async {
    try {
      final response = await api.post('/api/store/hostel/order/',
          body: body, token: ApiConfig.studentToken);
      return api.dataOf(response);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  List<Map<String, dynamic>> _myHostelOrders = [];
  List<Map<String, dynamic>> get myHostelOrders => _myHostelOrders;

  Future<void> loadMyHostelOrders() async {
    if (ApiConfig.studentToken == null) return;
    try {
      final response = await api.get('/api/store/hostel/my-orders/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _myHostelOrders = [
        for (final o in (data['orders'] as List? ?? []))
          (o as Map<String, dynamic>)
      ];
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _vendorHostelOrders = [];
  List<Map<String, dynamic>> get vendorHostelOrders => _vendorHostelOrders;

  Future<void> loadVendorHostelOrders() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response = await api.get('/api/vendor/hostel-orders/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _vendorHostelOrders = [
        for (final o in (data['orders'] as List? ?? []))
          (o as Map<String, dynamic>)
      ];
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> vendorHostelStatus(
      int id, String status) async {
    try {
      final response = await api.post('/api/vendor/hostel-order-status/',
          body: {'id': id, 'status': status},
          token: ApiConfig.vendorToken);
      return api.dataOf(response);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ------------------------------------------------------------------
  // Chat (network app)
  // ------------------------------------------------------------------
  final List<ChatRoom> _chatRooms = [];
  List<ChatRoom> get chatRooms => _chatRooms;

  ChatRoom? roomById(int id) =>
      _chatRooms.where((room) => room.id == id).firstOrNull;

  ChatRoom? roomByName(String name) =>
      _chatRooms.where((room) => room.name == name).firstOrNull;

  Future<void> loadChatRooms() async {
    try {
      final response =
          await api.get('/api/chat/rooms/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      final fresh = <ChatRoom>[
        for (final room in (data['rooms'] as List? ?? []))
          ChatRoom.fromJson(room as Map<String, dynamic>),
      ];
      // Purane rooms ke loaded messages preserve karo.
      for (final room in fresh) {
        final existing = roomByName(room.name);
        if (existing != null && existing.loaded) {
          room.messages.addAll(existing.messages);
          room.loaded = true;
          room.activePoll = existing.activePoll;
        }
      }
      _chatRooms
        ..clear()
        ..addAll(fresh);
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<String?> createChatRoom(String name, String privacy) async {
    try {
      await api.post('/api/chat/rooms/create/',
          token: ApiConfig.studentToken,
          body: {'name': name.trim(), 'privacy': privacy});
      await loadChatRooms();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> loadRoom(String roomName) async {
    try {
      final response = await api.get('/api/chat/rooms/$roomName/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      final room = roomByName(roomName);
      if (room == null) return;
      room.messages
        ..clear()
        ..addAll([
          for (final message in (data['messages'] as List? ?? []))
            ChatMessage.fromJson(message as Map<String, dynamic>, ApiConfig.media),
        ]);
      room.activePoll = data['poll'] == null
          ? null
          : ChatPoll.fromJson(data['poll'] as Map<String, dynamic>);
      room.loaded = true;
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<String?> joinRoom(String roomName) async {
    try {
      await api.post('/api/chat/rooms/$roomName/join/',
          token: ApiConfig.studentToken, body: {});
      await loadChatRooms();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<String?> sendChatMessage(String roomName, String text,
      {Uint8List? fileBytes, String? fileName, String? fileField}) async {
    try {
      if (fileBytes != null) {
        await api.postMultipart('/api/chat/rooms/$roomName/messages/',
            token: ApiConfig.studentToken,
            fields: {'content': text},
            fileBytes: fileBytes,
            fileName: fileName,
            fileField: fileField ?? 'image');
      } else {
        await api.post('/api/chat/rooms/$roomName/messages/',
            token: ApiConfig.studentToken, body: {'content': text});
      }
      await loadRoom(roomName);
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<String?> sendChatPoll(
      String roomName, String question, List<String> options) async {
    try {
      await api.post('/api/chat/rooms/$roomName/polls/',
          token: ApiConfig.studentToken,
          body: {'question': question, 'options': options});
      await loadRoom(roomName);
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> votePoll(int pollId, int optionId) async {
    try {
      await api.post('/api/chat/polls/$pollId/vote/',
          token: ApiConfig.studentToken, body: {'option_id': optionId});
      // Poll refresh ke liye room dobara load karo (caller room name jaanta hai).
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> toggleChatLike(int messageId, String roomName) async {
    try {
      await api.post('/api/chat/messages/$messageId/like/',
          token: ApiConfig.studentToken, body: {});
      await loadRoom(roomName);
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> togglePinMessage(int messageId, String roomName) async {
    try {
      await api.post('/api/chat/messages/$messageId/pin/',
          token: ApiConfig.studentToken, body: {});
      await loadRoom(roomName);
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  ChatMessage? pinnedMessageOf(ChatRoom room) {
    for (final message in room.messages) {
      if (message.pinned) return message;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // UMS (scraper_app / collegia)
  // ------------------------------------------------------------------
  String? umsUid;
  Map<String, dynamic> _umsDashboard = {};
  Map<String, dynamic> get umsDashboard => _umsDashboard;

  // ⭐ Portal (bahar ke network pe) captcha verify maang raha hai
  bool umsNeedsCaptcha = false;
  String? umsCaptchaB64;
  DateTime? _umsCaptchaCoolUntil;

  /// Dismiss ke baad 10 min tak dialog dobara nahi khulega.
  bool get umsCaptchaReady =>
      DateTime.now().isAfter(_umsCaptchaCoolUntil ?? DateTime(0));

  void markUmsCaptchaDismissed() {
    _umsCaptchaCoolUntil =
        DateTime.now().add(const Duration(minutes: 10));
    notifyListeners();
  }

  void _clearUmsMemory() {
    umsUid = null;
    LocalStore.remove('ums_uid');
    _umsDashboard = {};
    umsNeedsCaptcha = false;
    umsCaptchaB64 = null;
  }

  String get umsUserName =>
      (_umsDashboard['student_name'] ?? umsUid ?? '') as String;

  double? get umsOverallAttendance {
    final value = _umsDashboard['overall_attendance'];
    if (value is num) return value.toDouble();
    return null;
  }

  /// Stage 1: uid bhejo — captcha + password form wapas aata hai.
  Future<Map<String, dynamic>> umsStage1(String uid) async {
    try {
      final response = await api.post('/api/ums/stage1/',
          body: {'uid': uid.trim()}, token: ApiConfig.studentToken);
      return api.dataOf(response);
    } on ApiException catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  /// Stage 2: uid + password + captcha bhejo — login complete.
  Future<Map<String, dynamic>> umsStage2(
      String uid, String password, String captcha) async {
    try {
      final response = await api.post('/api/ums/stage2/',
          body: {'uid': uid.trim(), 'password': password, 'captcha': captcha},
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      umsUid = (data['uid'] ?? uid.trim()) as String;
      if ((umsUid ?? '').isNotEmpty) LocalStore.set('ums_uid', umsUid!);
      notifyListeners();
      return data;
    } on ApiException catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  Future<Map<String, dynamic>> umsDemoLogin() async {
    try {
      final response = await api.post('/api/ums/demo/', body: {});
      final data = api.dataOf(response);
      umsUid = (data['uid'] ?? 'demo') as String;
      if ((umsUid ?? '').isNotEmpty) LocalStore.set('ums_uid', umsUid!);
      notifyListeners();
      return data;
    } on ApiException catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  /// Test/debug hook — screen rendering verify karne ke liye.
  void debugSetUmsDashboard(Map<String, dynamic> data) {
    _umsDashboard = data;
    notifyListeners();
  }

  /// ⭐ App khulte hi UMS silent scrape — captcha sirf tab jab portal
  /// session poori tarah expire ho (warna cookies se auto-scrape).
  void umsAutoScrape() {
    if ((umsUid ?? '').isEmpty) return;
    loadUmsDashboard();
  }

  /// ⭐ No re-login: backend pe saved UMS account ho to session khud
  /// restore - app seedha dashboard kholta hai, login screen nahi.
  Future<bool> umsAutoRestore() async {
    if ((umsUid ?? '').isNotEmpty) return true;
    try {
      final response = await api.get('/api/ums/saved-uids/',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      final uids =
          (data['uids'] as List? ?? []).map((e) => '$e').toList();
      if (uids.isEmpty) return false;
      umsUid = uids.first;
      LocalStore.set('ums_uid', umsUid!);
      notifyListeners();
      await loadUmsDashboard();
      return _umsDashboard.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadUmsDashboard({bool live = false}) async {
    // ⭐ cached dashboard turant dikhao (UMS portal slow hai)
    if (_umsDashboard.isEmpty) {
      try {
        final c = LocalStore.get('cache_ums_dash');
        if (c != null && c.isNotEmpty) {
          _umsDashboard =
              Map<String, dynamic>.from(jsonDecode(c) as Map);
          notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final response = await api.get(
          '/api/ums/dashboard/?uid=${umsUid ?? ''}&refresh=1&live=${live ? 1 : 0}',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      // ⭐ ANY-NETWORK: portal captcha maang raha hai -> dialog ke liye flag
      if (data['needs_captcha'] == true) {
        _umsDashboard = {};
        umsNeedsCaptcha = true;
        umsCaptchaB64 = (data['captcha_b64'] ?? '').toString();
        notifyListeners();
        return;
      }
      umsNeedsCaptcha = false;
      umsCaptchaB64 = null;
      // Purana/different session ka data kabhi mat dikhao:
      // agar dashboard ka uid current login se match nahi karta -> khali.
      final dataUid = (data['uid'] ?? '').toString();
      final want = (umsUid ?? '').toString();
      if (want.isNotEmpty && dataUid.isNotEmpty && dataUid != want) {
        _umsDashboard = {};
      } else {
        _umsDashboard = data;
        try {
          LocalStore.set('cache_ums_dash', jsonEncode(data));
        } catch (_) {}
      }
      notifyListeners();
    } catch (error) {
      _umsDashboard = {};
      _fail(error);
      notifyListeners();
    }
  }

  /// Fresh captcha image (dialog ke refresh button ke liye).
  Future<Map<String, dynamic>> umsFetchCaptcha() async {
    try {
      final response = await api.get('/api/ums/captcha/?uid=${umsUid ?? ''}',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      umsCaptchaB64 = (data['captcha_b64'] ?? '').toString();
      notifyListeners();
      return data;
    } on ApiException catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  /// ⭐ Student captcha dalta hai -> backend portal login + live scrape.
  Future<Map<String, dynamic>> umsVerifyCaptcha(String code) async {
    try {
      final response = await api.post('/api/ums/verify-captcha/',
          body: {'uid': umsUid ?? '', 'code': code},
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      umsNeedsCaptcha = false;
      umsCaptchaB64 = null;
      _umsDashboard = data;
      notifyListeners();
      return data;
    } on ApiException catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': error.toString()};
    }
  }

  /// Uploaded ID card ka version stamp (null = uploaded nahi).
  int? umsIdCardV;

  /// ⭐ Results dropdown: semester tap -> wahi semester ka data.
  Future<bool> umsSwitchSemester(String sessionId) async {
    try {
      final response = await api.get(
          '/api/ums/semester/?uid=${umsUid ?? ''}&session_id=$sessionId',
          token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      if (data.isNotEmpty) {
        _umsDashboard = {..._umsDashboard, ...data};
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ⭐ Realtime sync poll (original dashboard_data mirror).
  Future<Map<String, dynamic>?> umsPing() async {
    try {
      final raw = await api.getRaw('/api/ums/ping/?uid=${umsUid ?? ''}',
          token: ApiConfig.studentToken);
      if (raw['ok'] == true) return raw;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// ⭐ Ping ke attendance numbers dashboard me in-place merge karo.
  void applyUmsSync(Map<String, dynamic> ping) {
    final att = ping['attendance'];
    if (att is! Map) return;
    final next = Map<String, dynamic>.from(_umsDashboard);
    if (att['global'] != null) next['overall_attendance'] = att['global'];
    if (att['attended'] != null) next['total_attended'] = att['attended'];
    if (att['held'] != null) next['total_held'] = att['held'];
    final fresh = att['records'] is List ? att['records'] as List : const [];
    final existing = _umsDashboard['attendance'] is List
        ? List<dynamic>.from(_umsDashboard['attendance'] as List)
        : <dynamic>[];
    for (var i = 0; i < fresh.length && i < existing.length; i++) {
      final r = fresh[i];
      if (r is Map && existing[i] is Map) {
        existing[i] = {
          ...Map<String, dynamic>.from(existing[i] as Map),
          for (final e in r.entries) e.key.toString(): e.value,
        };
      }
    }
    if (existing.isNotEmpty) next['attendance'] = existing;
    _umsDashboard = next;
    notifyListeners();
  }

  /// ⭐ ID card upload (dataURL) — original id_card upload mirror.
  Future<bool> umsIdCardUpload(String dataUrl) async {
    try {
      final raw = await api.postRaw(
          '/api/ums/id-card/?uid=${umsUid ?? ''}',
          body: {'image': dataUrl});
      if (raw['ok'] == true) {
        umsIdCardV = raw['v'] is int ? raw['v'] as int : 1;
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> umsIdCardRemove() async {
    try {
      final raw = await api
          .postRaw('/api/ums/id-card/remove/?uid=${umsUid ?? ''}');
      if (raw['ok'] == true) {
        umsIdCardV = null;
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> umsLogout() async {
    try {
      await api.post('/api/ums/logout/', body: {});
    } catch (_) {}
    umsUid = null;
    umsIdCardV = null;
    _umsDashboard = {};
    notifyListeners();
  }
}
