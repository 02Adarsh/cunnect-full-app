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

/// API-backed app state. Every screen talks only to this class —
/// all data comes from the Django backend (backend/myproject).
class AppStore extends ChangeNotifier {
  AppStore({ApiClient? apiClient}) : api = apiClient ?? ApiClient() {
    // ⭐ Saved session restore — no re-login after refresh/restart.
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
    // ⭐ Admin session restore
    final savedAdmin = LocalStore.get('admin_token');
    ApiConfig.adminToken =
        (savedAdmin == null || savedAdmin.isEmpty) ? null : savedAdmin;
    adminUsername = LocalStore.get('admin_username') ?? '';
    // ⭐ Vendor session restore — straight to the vendor dashboard on reopen
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

  // Legacy constants — a few older screens still use these.
  static const int customerUserId = 1;
  static const int vendorUserId = 2;
  static const int deliveryUserId = 3;
  static const String defaultAddress =
      'Chandigarh University UP, Parsandan, Uttar Pradesh 209859';
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

  /// ⭐ v58: forgot password — email a secure RESET LINK (themed page).
  Future<Map<String, dynamic>> authForgotLink(String identifier) async {
    try {
      final r = await api.post('/api/auth/forgot-link/',
          body: {'identifier': identifier.trim()});
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ⭐ v63: set the new password from the IN-APP deep-linked reset screen.
  /// ⭐ v70: one stable id per app install — used for the
  /// single-device login rule (same phone can always log back in).
  String get deviceId {
    var id = LocalStore.get('device_id');
    if (id == null || id.isEmpty) {
      id = 'DEV-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '-${(1000 + DateTime.now().microsecond % 9000)}';
      LocalStore.set('device_id', id);
    }
    return id;
  }

  Future<Map<String, dynamic>> authResetLinkPassword(
      String uidb64, String token, String password) async {
    try {
      final r = await api.post('/api/auth/reset-link-password/', body: {
        'uidb64': uidb64,
        'token': token,
        'password': password,
      });
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// ⭐ Forgot password: send an OTP to the email.
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

  /// ⭐ OTP + new password -> reset.
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
      final r = await api.post('/api/auth/login2/', body: {
        'uid': uid.trim(),
        'password': password,
        'captcha': captcha,
        'device_id': deviceId,
      });
      final data = api.dataOf(r);
      ApiConfig.studentToken = data['token'] as String?;
      studentUid = (data['uid'] ?? uid.trim()) as String;
      customerName = (data['name'] ?? '') as String;
      _clearUmsMemory(); // new app user -> drop the old UMS
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

  /// ⭐ Support Us form — saved to the backend at student/support/.
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
        'device_id': deviceId,
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
      // Fetch the dashboard banners right away (for the home hero).
      unawaitedLoadDashboardBanners();
      return null;
    } catch (error) {
      _fail(error);
      notifyListeners();
      return error.toString();
    }
  }

  Future<void> studentLogout() async {
    // ⭐ v70: release the single-device lock on the server.
    final token = ApiConfig.studentToken;
    if (token != null && token.isNotEmpty) {
      try {
        await api.post('/api/auth/logout/', token: token, body: {});
      } catch (_) {
        // offline logout is still fine — the session frees itself later.
      }
    }
    ApiConfig.studentToken = null;
    LocalStore.remove('student_token');
    LocalStore.remove('student_uid');
    LocalStore.remove('student_name');
    studentUid = null;
    // ⭐ multi-student: when the app user changes, drop the old UMS from memory
    umsUid = null;
    LocalStore.remove('ums_uid');
    _umsDashboard = {};
    umsNeedsCaptcha = false;
    umsCaptchaB64 = null;
    notifyListeners();
  }

  /// ⭐ Render cached banners/food-home instantly (before the network).
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

  // ---------- ⭐ notices + polls (backend/admin se) ----------
  final List<CampusNotice> _notices = [];
  final List<AppPollModel> _polls = [];
  bool noticesLoading = false;

  List<CampusNotice> get notices => _notices;
  List<AppPollModel> get polls => _polls;

  // ⭐ Custom store sections (created from the admin portal).
  List<Map<String, dynamic>> storeSections = [];

  // ⭐ v60: admin-controlled flags for the BUILT-IN sections
  // (food / printout / hostel) — title, subtitle, is_active, coming_soon.
  Map<String, Map<String, dynamic>> builtinSections = {};

  Future<void> loadStoreSections() async {
    try {
      final r =
          await api.get('/api/store/sections/', token: ApiConfig.studentToken);
      final data = api.dataOf(r);
      storeSections = [
        for (final x in (data['sections'] as List? ?? []))
          Map<String, dynamic>.from(x as Map),
      ];
      builtinSections = {
        for (final e in ((data['builtin'] as Map?) ?? {}).entries)
          '${e.key}': Map<String, dynamic>.from(e.value as Map),
      };
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadNotices() async {
    // ⭐ Instant: hydrate from the on-device cache first so the feed
    // renders with zero delay, then refresh from the network.
    if (_notices.isEmpty && _polls.isEmpty) {
      try {
        final cn = LocalStore.get('cache_feed_notices');
        if (cn != null && cn.isNotEmpty) {
          _notices.addAll([
            for (final n in (jsonDecode(cn) as List? ?? []))
              CampusNotice.fromJson(
                  (n as Map).cast<String, dynamic>(), ApiConfig.media),
          ]);
        }
        final cp = LocalStore.get('cache_feed_polls');
        if (cp != null && cp.isNotEmpty) {
          _polls.addAll([
            for (final p in (jsonDecode(cp) as List? ?? []))
              AppPollModel.fromJson(
                  (p as Map).cast<String, dynamic>(), ApiConfig.media),
          ]);
        }
      } catch (_) {}
    }
    noticesLoading = _notices.isEmpty && _polls.isEmpty;
    notifyListeners();
    // ⭐ Fast: both feed endpoints fetched in parallel.
    final results = await Future.wait([
      api
          .get('/api/notices/', token: ApiConfig.studentToken)
          .then<Map<String, dynamic>?>((r) => api.dataOf(r))
          .catchError((Object e) {
        _checkStudentAuthLost(e);
        return null;
      }),
      api
          .get('/api/polls/', token: ApiConfig.studentToken)
          .then<Map<String, dynamic>?>((r) => api.dataOf(r))
          .catchError((Object e) => null),
    ]);
    final nd = results[0];
    if (nd != null) {
      _notices
        ..clear()
        ..addAll([
          for (final n in (nd['notices'] as List? ?? []))
            CampusNotice.fromJson(n as Map<String, dynamic>, ApiConfig.media),
        ]);
      try {
        LocalStore.set('cache_feed_notices', jsonEncode(nd['notices'] ?? []));
      } catch (_) {}
    }
    final pd = results[1];
    if (pd != null) {
      _polls
        ..clear()
        ..addAll([
          for (final p in (pd['polls'] as List? ?? []))
            AppPollModel.fromJson(p as Map<String, dynamic>, ApiConfig.media),
        ]);
      try {
        LocalStore.set('cache_feed_polls', jsonEncode(pd['polls'] ?? []));
      } catch (_) {}
    }
    noticesLoading = false;
    notifyListeners();
  }

  Future<String?> voteAppPoll(int pollId, int optionId) async {
    // ⭐ Optimistic: the bars move the instant you tap — the server
    // sync happens in the background and corrects the counts if needed.
    final i = _polls.indexWhere((p) => p.id == pollId);
    AppPollModel? backup;
    if (i >= 0) {
      final poll = _polls[i];
      backup = poll;
      final prev = poll.myOptionId;
      if (prev != optionId) {
        _polls[i] = AppPollModel(
          id: poll.id,
          question: poll.question,
          imageUrl: poll.imageUrl,
          videoUrl: poll.videoUrl,
          pinned: poll.pinned,
          totalVotes: poll.totalVotes + (prev == null ? 1 : 0),
          myOptionId: optionId,
          options: [
            for (final o in poll.options)
              AppPollOptionModel(
                id: o.id,
                text: o.text,
                imageUrl: o.imageUrl,
                votes: o.votes +
                    (o.id == optionId ? 1 : 0) -
                    (prev != null && o.id == prev ? 1 : 0),
              ),
          ],
          createdAt: poll.createdAt,
          social: poll.social,
        );
        notifyListeners();
      }
    }
    try {
      final r = await api.post('/api/polls/$pollId/vote/',
          token: ApiConfig.studentToken, body: {'option_id': optionId});
      final d = api.dataOf(r);
      final updated =
          AppPollModel.fromJson(d['poll'] as Map<String, dynamic>, ApiConfig.media);
      final j = _polls.indexWhere((p) => p.id == pollId);
      if (j >= 0) _polls[j] = updated;
      notifyListeners();
      return null;
    } catch (e) {
      // Roll back the optimistic change on failure.
      if (backup != null) {
        final j = _polls.indexWhere((p) => p.id == pollId);
        if (j >= 0) _polls[j] = backup;
        notifyListeners();
      }
      return e.toString();
    }
  }

  /// ⭐ Feed reaction — any emoji (WhatsApp style). Sending the same emoji
  /// again removes the reaction. kind = 'notice' | 'poll'.
  Future<FeedSocial?> reactToFeed(String kind, int objectId, String emoji) async {
    try {
      final r = await api.post('/api/feed/$kind/$objectId/react/',
          token: ApiConfig.studentToken, body: {'emoji': emoji});
      final social = FeedSocial.fromJson(api.dataOf(r));
      _applyFeedSocial(kind, objectId, social);
      return social;
    } catch (_) {
      return null;
    }
  }

  Future<List<FeedCommentModel>> loadFeedComments(String kind, int objectId) async {
    try {
      final r = await api.get('/api/feed/$kind/$objectId/comments/',
          token: ApiConfig.studentToken);
      return [
        for (final c in (api.dataOf(r)['comments'] as List? ?? []))
          FeedCommentModel.fromJson(c as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<FeedCommentModel>?> addFeedComment(
      String kind, int objectId, String text, {int? parentId}) async {
    try {
      final r = await api.post('/api/feed/$kind/$objectId/comments/add/',
          token: ApiConfig.studentToken,
          body: {'text': text, if (parentId != null) 'parent_id': parentId});
      return _applyCommentsResponse(kind, objectId, r);
    } catch (_) {
      return null;
    }
  }

  /// ⭐ Delete your own comment (replies go with it).
  Future<List<FeedCommentModel>?> deleteFeedComment(
      String kind, int objectId, int commentId) async {
    try {
      final r = await api.post(
          '/api/feed/$kind/$objectId/comments/$commentId/delete/',
          token: ApiConfig.studentToken,
          body: {});
      return _applyCommentsResponse(kind, objectId, r);
    } catch (_) {
      return null;
    }
  }

  /// ⭐ Emoji reaction on a comment — same emoji again toggles it off.
  Future<List<FeedCommentModel>?> reactToFeedComment(
      String kind, int objectId, int commentId, String emoji) async {
    try {
      final r = await api.post(
          '/api/feed/$kind/$objectId/comments/$commentId/react/',
          token: ApiConfig.studentToken,
          body: {'emoji': emoji});
      return _applyCommentsResponse(kind, objectId, r);
    } catch (_) {
      return null;
    }
  }

  List<FeedCommentModel> _applyCommentsResponse(
      String kind, int objectId, Map<String, dynamic> r) {
    final data = api.dataOf(r);
    final comments = [
      for (final c in (data['comments'] as List? ?? []))
        FeedCommentModel.fromJson(c as Map<String, dynamic>),
    ];
    _bumpFeedCommentCount(
        kind, objectId, (data['total'] ?? comments.length) as int);
    return comments;
  }

  void _applyFeedSocial(String kind, int objectId, FeedSocial social) {
    if (kind == 'notice') {
      final i = _notices.indexWhere((n) => n.id == objectId);
      if (i >= 0) _notices[i].social = social;
    } else {
      final i = _polls.indexWhere((p) => p.id == objectId);
      if (i >= 0) _polls[i].social = social;
    }
    notifyListeners();
  }

  void _bumpFeedCommentCount(String kind, int objectId, int count) {
    final FeedSocial? old = kind == 'notice'
        ? _notices.where((n) => n.id == objectId).firstOrNull?.social
        : _polls.where((p) => p.id == objectId).firstOrNull?.social;
    if (old == null) return;
    _applyFeedSocial(kind, objectId,
        FeedSocial(reactions: old.reactions, myReaction: old.myReaction, commentCount: count));
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
  // ⭐ vendor notifications go in a separate list — never mixed with student ones
  final List<AppNotification> _vendorNotifications = [];
  int _vendorUnreadCount = 0;

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

  /// ⭐ refresh food items only — deletes/kitchen changes show instantly
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

  /// 'increase' | 'decrease' | 'remove' — like the cart.html buttons.
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
        // Django template: shows a popup when a big discount is applied.
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

  /// Place the order. Returns an error message on failure, else null.
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

  /// ⭐ Vendor uploads their own QR image — null on success, else an error message.
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

  /// ⭐ Vendor UPI QR (scan-and-pay at checkout)
  Future<Map<String, dynamic>?> fetchUpiQr(int vendorId, num? amount) async {
    try {
      final amt = (amount == null || amount <= 0) ? '' : '&amount=$amount';
      final r = await api.get('/api/food/upi-qr/?vendor_id=$vendorId$amt');
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

  bool _customerOrdersHydrated = false;

  Future<void> refreshCustomerOrders() async {
    // ⭐ v62: cache-first — My Orders shows the last list instantly.
    if (!_customerOrdersHydrated) {
      _customerOrdersHydrated = true;
      try {
        final c = LocalStore.get('cache_my_orders');
        if (c != null && c.isNotEmpty && _customerOrders.isEmpty) {
          _customerOrders.addAll([
            for (final order in (jsonDecode(c) as List? ?? []))
              Order.fromJson((order as Map).cast<String, dynamic>()),
          ]);
          notifyListeners();
        }
      } catch (_) {}
    }
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
      try {
        LocalStore.set('cache_my_orders', jsonEncode(data['orders'] ?? []));
      } catch (_) {}
      serverReachable = true;
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  /// The food home 3-second live poll — status refresh only.
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
      // Silent poll — do not disturb the UI.
    }
  }

  // ---------- notifications ----------

  /// ⭐ Set when the backend rejects the student token (account disabled
  /// or logged out remotely). The dashboard watches this and returns to
  /// the login screen automatically.
  bool studentSessionLost = false;

  void _checkStudentAuthLost(Object error) {
    if (error is ApiException &&
        error.statusCode == 401 &&
        ApiConfig.studentToken != null) {
      studentSessionLost = true;
      studentLogout();
    }
  }

  Future<void> loadNotifications() async {
    try {
      final response = await api.get(
          '/api/food/notifications/?audience=student',
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
    } catch (error) {
      // ⭐ Account disabled / token revoked -> automatic logout.
      _checkStudentAuthLost(error);
    }
  }

  /// ⭐ vendor notifications — vendor token + audience=vendor
  Future<void> loadVendorNotifications() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final response = await api.get(
          '/api/food/notifications/?audience=vendor',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _vendorNotifications
        ..clear()
        ..addAll([
          for (final notification in (data['notifications'] as List? ?? []))
            AppNotification.fromJson(notification as Map<String, dynamic>),
        ]);
      _vendorUnreadCount = (data['unread_count'] ??
              _vendorNotifications.where((n) => !n.isRead).length)
          as int;
      notifyListeners();
    } catch (_) {}
  }

  /// ⭐ local (client-side) notification — UMS attendance / vendor new order
  void addLocalNotification(String title, String message) {
    final isVendor = title.toLowerCase().contains('new order');
    // ⭐ NO on-screen popup/toast for the vendor — only the system
    // notification (with sound, shown by the fcm.dart poll) + bell list.
    if (!isVendor) {
      showCunnectPopup(title, message, vendor: false);
    }
    final n = AppNotification(
        id: -DateTime.now().millisecondsSinceEpoch,
        title: title,
        message: message,
        isRead: false,
        createdAt: DateTime.now());
    // vendor local alerts go to the vendor list, the rest to the student list
    (isVendor ? _vendorNotifications : _notifications).insert(0, n);
    notifyListeners();
  }

  List<AppNotification> notificationsFor(int userId) {
    return userId == vendorUserId ? _vendorNotifications : _notifications;
  }

  int unreadCountFor(int userId) =>
      userId == vendorUserId ? _vendorUnreadCount : _unreadCount;

  Future<void> markAllRead(int userId) async {
    final isVendor = userId == vendorUserId;
    try {
      await api.post('/api/food/notifications/read/',
          token: isVendor ? ApiConfig.vendorToken : ApiConfig.studentToken,
          body: {'audience': isVendor ? 'vendor' : 'student'});
      if (isVendor) {
        _vendorUnreadCount = 0;
        _vendorNotifications.clear();
      } else {
        _unreadCount = 0;
        _notifications.clear();
      }
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

  // ⭐ v55: optimistic order-status protection. A dashboard poll that was
  // already in flight when the vendor tapped Accept / Start Preparing /
  // Mark Ready could land AFTER the optimistic update and resurrect the
  // old button — making every action look like it needs two taps.
  // We remember the tapped status per order and never let a refresh
  // move an order BACKWARDS past it.
  final Map<int, OrderStatus> _optimisticStatus = {};

  static int _statusRank(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return 0;
      case OrderStatus.accepted:
        return 1;
      case OrderStatus.preparing:
        return 2;
      case OrderStatus.ready:
        return 3;
      case OrderStatus.outForDelivery:
        return 4;
      case OrderStatus.completed:
        return 5;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return 6;
    }
  }

  void _applyOptimisticStatuses() {
    if (_optimisticStatus.isEmpty) return;
    // Incoming list: an order the vendor already acted on must not
    // reappear as "new" — move it to Active (or drop it if rejected).
    _vendorIncoming.removeWhere((o) {
      final want = _optimisticStatus[o.id];
      if (want == null) return false;
      if (want == OrderStatus.rejected) return true;
      o.status = want;
      _vendorActive.insert(0, o);
      return true;
    });
    // Active list: never step BACKWARDS behind what the vendor tapped.
    final confirmed = <int>[];
    for (final o in _vendorActive) {
      final want = _optimisticStatus[o.id];
      if (want == null) continue;
      if (_statusRank(o.status) >= _statusRank(want)) {
        confirmed.add(o.id); // server caught up — protection over
      } else {
        o.status = want;
      }
    }
    for (final o in _vendorOutForDelivery) {
      if (_optimisticStatus.containsKey(o.id)) confirmed.add(o.id);
    }
    for (final id in confirmed) {
      _optimisticStatus.remove(id);
    }
  }

  bool _vendorDashHydrated = false;

  /// ⭐ v62: apply a vendor-dashboard payload to the in-memory lists
  /// (used by both the network refresh and the disk-cache hydrate).
  void _applyVendorDashboard(Map<String, dynamic> data) {
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
      _applyOptimisticStatuses();
      _todaySales = ((data['today_sales'] ?? 0) as num).round();
      _kitchenOpen = (data['kitchen_open'] ?? true) as bool;
      _menuCount = (data['menu_count'] ?? 0) as int;
      _availableCount = (data['available_count'] ?? 0) as int;
      notifyListeners();
  }

  Future<void> refreshVendorDashboard() async {
    if (ApiConfig.vendorToken == null) return;
    // ⭐ v62: cache-first — the dashboard fills instantly from the last
    // session while the live fetch runs in the background.
    if (!_vendorDashHydrated) {
      _vendorDashHydrated = true;
      try {
        final c = LocalStore.get('cache_vendor_dash');
        if (c != null && c.isNotEmpty && _vendorIncoming.isEmpty &&
            _vendorActive.isEmpty && _vendorHistory.isEmpty) {
          _applyVendorDashboard(
              Map<String, dynamic>.from(jsonDecode(c) as Map));
        }
      } catch (_) {}
    }
    try {
      final response = await api.get('/api/vendor/dashboard/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _applyVendorDashboard(data);
      serverReachable = true;
      try {
        LocalStore.set('cache_vendor_dash', jsonEncode(data));
      } catch (_) {}
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> vendorUpdateOrderStatus(int orderId, String action) async {
    // ⭐ optimistic: update the UI instantly, sync to the server in the background
    Order? moved;
    final i1 = _vendorIncoming.indexWhere((o) => o.id == orderId);
    if (i1 >= 0) {
      moved = _vendorIncoming.removeAt(i1);
    } else {
      final i2 = _vendorActive.indexWhere((o) => o.id == orderId);
      if (i2 >= 0) moved = _vendorActive[i2];
    }
    OrderStatus? target;
    if (action == 'accept') {
      target = OrderStatus.accepted;
    } else if (action == 'reject') {
      target = OrderStatus.rejected;
    } else if (action == 'prepare') {
      target = OrderStatus.preparing;
    } else if (action == 'ready') {
      target = OrderStatus.ready;
    }
    if (target != null) _optimisticStatus[orderId] = target;
    if (moved != null && target != null) {
      moved.status = target;
      if (action == 'accept') _vendorActive.insert(0, moved);
      notifyListeners();
    }
    try {
      await api.post('/api/vendor/orders/$orderId/$action/',
          token: ApiConfig.vendorToken, body: {});
    } catch (error) {
      // The action genuinely failed — drop the protection so the UI
      // falls back to the real server state on the next refresh.
      _optimisticStatus.remove(orderId);
      lastError = error.toString();
      notifyListeners();
    }
    refreshVendorDashboard();
  }

  /// The vendor delivers personally: start-delivery begins the OTP flow.
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
    // ⭐ v62: cache-first — the menu shows instantly, then refreshes live.
    if (_menuItems.isEmpty) {
      try {
        final c = LocalStore.get('cache_vendor_menu');
        if (c != null && c.isNotEmpty) {
          _menuItems.addAll([
            for (final item in (jsonDecode(c) as List? ?? []))
              FoodItem.fromJson(
                  (item as Map).cast<String, dynamic>(), ApiConfig.media),
          ]);
          notifyListeners();
        }
      } catch (_) {}
    }
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
      try {
        LocalStore.set('cache_vendor_menu', jsonEncode(data['items'] ?? []));
      } catch (_) {}
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> toggleItemAvailability(int itemId) async {
    // ⭐ optimistic: toggle instantly in the UI, sync to the server in the background
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
  /// v57: optimistic — the item disappears instantly; if the server
  /// call fails the menu reloads and the item comes back with an error.
  Future<String?> deleteMenuItem(int itemId) async {
    final idx = _menuItems.indexWhere((f) => f.id == itemId);
    final removed = idx >= 0 ? _menuItems.removeAt(idx) : null;
    if (removed != null) notifyListeners();
    try {
      await api.post('/api/vendor/menu/$itemId/delete/',
          token: ApiConfig.vendorToken, body: {});
      loadVendorMenu();
      return null;
    } catch (error) {
      lastError = error.toString();
      await loadVendorMenu(); // restore the real list
      return error.toString();
    }
  }

  Future<Map<String, dynamic>> saveFoodItem({
    int? id,
    required String name,
    required double price,
    required String description,
    required String category,
    required bool isAvailable,
    bool isVeg = true,
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
        'is_veg': isVeg,
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
    try {
      final response = await api.post('/api/vendor/profile/',
          token: ApiConfig.vendorToken,
          body: {'business_name': businessName, 'phone': phone});
      final data = api.dataOf(response);
      vendor.businessName =
          (data['business_name'] ?? businessName) as String;
      vendor.phone = (data['phone'] ?? phone) as String;
      LocalStore.set('vendor_name', vendor.businessName);
      LocalStore.set('vendor_phone', vendor.phone);
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return 'Could not save the profile. Please try again.';
    }
  }

  // ---------- vendor earnings ----------
  final List<Order> _completedOrders = [];
  final List<MapEntry<String, double>> _weeklyEarnings = [];
  double _weekTotal = 0;

  List<MapEntry<String, double>> get weeklyEarnings => _weeklyEarnings;
  double get weekTotal => _weekTotal;

  bool _earningsHydrated = false;

  Future<void> loadVendorEarnings() async {
    if (ApiConfig.vendorToken == null) return;
    // ⭐ v62: cache-first — earnings paint instantly from the last visit.
    if (!_earningsHydrated) {
      _earningsHydrated = true;
      try {
        final c = LocalStore.get('cache_vendor_earnings');
        if (c != null && c.isNotEmpty && _completedOrders.isEmpty) {
          _applyVendorEarnings(
              Map<String, dynamic>.from(jsonDecode(c) as Map));
        }
      } catch (_) {}
    }
    try {
      final response = await api.get('/api/vendor/earnings/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      try {
        LocalStore.set('cache_vendor_earnings', jsonEncode(data));
      } catch (_) {}
      _applyVendorEarnings(data);
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  void _applyVendorEarnings(Map<String, dynamic> data) {
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

  /// In a delivery partner session these lists come from the delivery
  /// dashboard; in a vendor session the vendor sees their own orders' panel.
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
    String txnId = '',
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
            'txn_id': txnId,
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

  /// ⭐ Server-side page count of the PDF (to fill the dropdowns).
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

  bool _printOrdersHydrated = false;

  Future<void> loadMyPrintOrders() async {
    // ⭐ v62: cache-first — print orders list paints instantly.
    if (!_printOrdersHydrated) {
      _printOrdersHydrated = true;
      try {
        final c = LocalStore.get('cache_my_print_orders');
        if (c != null && c.isNotEmpty && _printOrders.isEmpty) {
          _printOrders.addAll([
            for (final order in (jsonDecode(c) as List? ?? []))
              PrintOrder.fromJson(
                  (order as Map).cast<String, dynamic>(), ApiConfig.media),
          ]);
          notifyListeners();
        }
      } catch (_) {}
    }
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
      try {
        LocalStore.set(
            'cache_my_print_orders', jsonEncode(data['orders'] ?? []));
      } catch (_) {}
      notifyListeners();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  bool _printVendorHydrated = false;

  Future<void> loadPrintVendorDashboard() async {
    if (ApiConfig.vendorToken == null) return;
    // ⭐ v62: cache-first — the print vendor dashboard opens instantly.
    if (!_printVendorHydrated) {
      _printVendorHydrated = true;
      try {
        final c = LocalStore.get('cache_print_vendor_dash');
        if (c != null && c.isNotEmpty && _printVendorOrders.isEmpty) {
          _printVendorOrders.addAll([
            for (final order in (jsonDecode(c) as List? ?? []))
              PrintOrder.fromJson(
                  (order as Map).cast<String, dynamic>(), ApiConfig.media),
          ]);
          notifyListeners();
        }
      } catch (_) {}
    }
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
      try {
        LocalStore.set(
            'cache_print_vendor_dash', jsonEncode(data['orders'] ?? []));
      } catch (_) {}
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

  /// ⭐ v80: the print vendor types the OTP the student shows. The job
  /// is completed by the server the moment the OTP matches.
  Future<String?> printVerifyOtp(int orderId, String otp) async {
    try {
      await api.post('/api/print/orders/$orderId/verify-otp/',
          token: ApiConfig.vendorToken, body: {'otp': otp.trim()});
      await loadPrintVendorDashboard();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not verify that OTP. Try again.';
    }
  }

  /// ⭐ v80: the hostel vendor types the OTP the student reads out at
  /// the door — the order is marked delivered by the server.
  Future<String?> hostelVerifyOtp(int orderId, String otp) async {
    try {
      await api.post('/api/vendor/hostel-orders/$orderId/verify-otp/',
          token: ApiConfig.vendorToken, body: {'otp': otp.trim()});
      await loadVendorHostelOrders();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not verify that OTP. Try again.';
    }
  }

  /// Vendor dashboard status action buttons — like the Django template.
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

  bool _storeHomeHydrated = false;

  Future<void> loadStoreHome() async {
    // ⭐ v62: cache-first — the store opens full of content instantly.
    if (!_storeHomeHydrated) {
      _storeHomeHydrated = true;
      try {
        final c = LocalStore.get('cache_store_home');
        if (c != null && c.isNotEmpty && _storeCategories.isEmpty) {
          final data = Map<String, dynamic>.from(jsonDecode(c) as Map);
          _storeCategories.addAll([
            for (final category in (data['categories'] as List? ?? []))
              (category as Map).cast<String, dynamic>(),
          ]);
          _printVendors.addAll([
            for (final vendor in (data['print_vendors'] as List? ?? []))
              PrintVendor.fromJson((vendor as Map).cast<String, dynamic>()),
          ]);
          notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final response =
          await api.get('/api/store/home/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      try {
        LocalStore.set('cache_store_home', jsonEncode(data));
      } catch (_) {}
      _storeCategories
        ..clear()
        ..addAll([
          for (final category in (data['categories'] as List? ?? []))
            category as Map<String, dynamic>,
        ]);
      // Print vendors also appear on the store home.
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
  // ⭐ Hostel Essentials store (v60: individual products + cart)
  // ------------------------------------------------------------------
  Map<String, dynamic> _hostelInfo = {};
  Map<String, dynamic> get hostelInfo => _hostelInfo;

  Future<Map<String, dynamic>> loadHostelInfo() async {
    // ⭐ v62: cache-first — products render instantly, live data follows.
    if (_hostelInfo.isEmpty) {
      try {
        final c = LocalStore.get('cache_hostel_info');
        if (c != null && c.isNotEmpty) {
          _hostelInfo = Map<String, dynamic>.from(jsonDecode(c) as Map);
          notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final response =
          await api.get('/api/store/hostel/', token: ApiConfig.studentToken);
      final data = api.dataOf(response);
      _hostelInfo = data;
      try {
        LocalStore.set('cache_hostel_info', jsonEncode(data));
      } catch (_) {}
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
    // ⭐ v62: cache-first — hostel orders list paints instantly.
    if (_vendorHostelOrders.isEmpty) {
      try {
        final c = LocalStore.get('cache_vendor_hostel_orders');
        if (c != null && c.isNotEmpty) {
          _vendorHostelOrders = [
            for (final o in (jsonDecode(c) as List? ?? []))
              Map<String, dynamic>.from(o as Map),
          ];
          notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final response = await api.get('/api/vendor/hostel-orders/',
          token: ApiConfig.vendorToken);
      final data = api.dataOf(response);
      _vendorHostelOrders = [
        for (final o in (data['orders'] as List? ?? []))
          (o as Map<String, dynamic>)
      ];
      try {
        LocalStore.set(
            'cache_vendor_hostel_orders', jsonEncode(_vendorHostelOrders));
      } catch (_) {}
      notifyListeners();
    } catch (_) {}
  }

  // ------- ⭐ v61: hostel vendor's own catalogue (products) -------

  List<Map<String, dynamic>> _vendorHostelProducts = [];
  List<Map<String, dynamic>> get vendorHostelProducts =>
      _vendorHostelProducts;

  Future<void> loadVendorHostelProducts() async {
    if (ApiConfig.vendorToken == null) return;
    // ⭐ v62: cache-first — the catalogue appears instantly on open.
    if (_vendorHostelProducts.isEmpty) {
      try {
        final c = LocalStore.get('cache_vendor_hostel_products');
        if (c != null && c.isNotEmpty) {
          _vendorHostelProducts = [
            for (final p in (jsonDecode(c) as List? ?? []))
              Map<String, dynamic>.from(p as Map),
          ];
          notifyListeners();
        }
      } catch (_) {}
    }
    try {
      final r = await api.get('/api/vendor/hostel-products/',
          token: ApiConfig.vendorToken);
      _vendorHostelProducts = [
        for (final p in (api.dataOf(r)['products'] as List? ?? []))
          Map<String, dynamic>.from(p as Map),
      ];
      try {
        LocalStore.set('cache_vendor_hostel_products',
            jsonEncode(_vendorHostelProducts));
      } catch (_) {}
      notifyListeners();
    } catch (_) {}
  }

  /// POST helper for the vendor's hostel-product endpoints.
  Future<String?> vendorHostelProductPost(
      String path, Map<String, dynamic> body) async {
    try {
      await api.post(path, token: ApiConfig.vendorToken, body: body);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> vendorHostelProductDelete(String path) async {
    try {
      await api.delete(path, token: ApiConfig.vendorToken);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Upload one product photo from the vendor portal.
  Future<String?> vendorHostelPhoto(
      int productId, Uint8List bytes, String fileName) async {
    try {
      await api.postMultipart(
        '/api/vendor/hostel-products/$productId/photo/',
        token: ApiConfig.vendorToken,
        fields: const {},
        fileBytes: bytes,
        fileName: fileName,
        fileField: 'image',
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ------- ⭐ v61: vendor storefront settings (name + description) -------

  Future<Map<String, dynamic>> vendorStoreSettings(
      {Map<String, dynamic>? save}) async {
    try {
      final r = save == null
          ? await api.get('/api/vendor/store-settings/',
              token: ApiConfig.vendorToken)
          : await api.post('/api/vendor/store-settings/',
              body: save, token: ApiConfig.vendorToken);
      return api.dataOf(r);
    } on ApiException catch (e) {
      return {'error': e.message};
    } catch (e) {
      return {'error': e.toString()};
    }
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
      // Preserve the loaded messages of existing rooms.
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
      // Reload the room to refresh the poll (the caller knows the room name).
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

  // ⭐ The portal (on an outside network) is asking for captcha verification
  bool umsNeedsCaptcha = false;
  String? umsCaptchaB64;
  DateTime? _umsCaptchaCoolUntil;

  /// After a dismiss the dialog will not reopen for 10 minutes.
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

  /// Stage 1: send the uid — the captcha + password form comes back.
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

  /// Stage 2: send uid + password + captcha — login completes.
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

  /// Test/debug hook — for verifying screen rendering.
  void debugSetUmsDashboard(Map<String, dynamic> data) {
    _umsDashboard = data;
    notifyListeners();
  }

  /// ⭐ Silent UMS scrape on app open — captcha only when the portal
  /// session has fully expired (otherwise auto-scrape via cookies).
  void umsAutoScrape() {
    if ((umsUid ?? '').isEmpty) return;
    loadUmsDashboard();
  }

  /// ⭐ No re-login: if a saved UMS account exists on the backend the
  /// session restores itself - the app opens the dashboard, not the login.
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
    // ⭐ show the cached dashboard instantly (the UMS portal is slow)
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
      // ⭐ ANY-NETWORK: the portal is asking for a captcha -> flag for the dialog
      if (data['needs_captcha'] == true) {
        _umsDashboard = {};
        umsNeedsCaptcha = true;
        umsCaptchaB64 = (data['captcha_b64'] ?? '').toString();
        notifyListeners();
        return;
      }
      umsNeedsCaptcha = false;
      umsCaptchaB64 = null;
      // Never show data from an old/different session:
      // if the dashboard uid does not match the current login -> empty.
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

  /// Fresh captcha image (for the dialog refresh button).
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

  /// ⭐ The student enters the captcha -> backend portal login + live scrape.
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

  /// Version stamp of the uploaded ID card (null = not uploaded).
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

  /// ⭐ Merge the ping attendance numbers into the dashboard in place.
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
          body: {'image': dataUrl}, token: ApiConfig.studentToken);
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
      final raw = await api.postRaw(
          '/api/ums/id-card/remove/?uid=${umsUid ?? ''}',
          token: ApiConfig.studentToken);
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
      await api.post('/api/ums/logout/',
          body: {'uid': umsUid ?? ''}, token: ApiConfig.studentToken);
    } catch (_) {}
    umsUid = null;
    umsIdCardV = null;
    _umsDashboard = {};
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // ⭐ Admin panel — full app management (staff/superuser only)
  // ------------------------------------------------------------------
  String adminUsername = '';

  bool get adminLoggedIn => ApiConfig.adminToken != null;

  Future<LoginResult> adminLogin(String username, String password) async {
    try {
      final response = await api.post('/api/admin/login/',
          body: {'username': username.trim(), 'password': password});
      final data = api.dataOf(response);
      ApiConfig.adminToken = data['token'] as String?;
      adminUsername = (data['username'] ?? username) as String;
      LocalStore.set('admin_token', ApiConfig.adminToken ?? '');
      LocalStore.set('admin_username', adminUsername);
      notifyListeners();
      return LoginResult(true, 'Welcome, $adminUsername');
    } on ApiException catch (error) {
      return LoginResult(false, error.message);
    } catch (error) {
      return LoginResult(false, error.toString());
    }
  }

  void adminLogout() {
    ApiConfig.adminToken = null;
    adminUsername = '';
    LocalStore.remove('admin_token');
    LocalStore.remove('admin_username');
    notifyListeners();
  }

  /// ⭐ v62: last successful admin response for [path] — synchronous, so
  /// the panel paints INSTANTLY from cache while the network refreshes.
  Map<String, dynamic> adminCached(String path) {
    try {
      final c = LocalStore.get('cache_admin_$path');
      if (c != null && c.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(c) as Map);
      }
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> adminGet(String path) async {
    try {
      final r = await api.get(path, token: ApiConfig.adminToken);
      final d = api.dataOf(r);
      // ⭐ v62: persist every successful GET — next open is zero-wait.
      if (d.isNotEmpty) {
        try {
          LocalStore.set('cache_admin_$path', jsonEncode(d));
        } catch (_) {}
      }
      return d;
    } catch (_) {
      return {};
    }
  }

  /// POST helper for admin actions — returns null on success, else the
  /// error message.
  Future<String?> adminPost(String path, Map<String, dynamic> body) async {
    try {
      await api.post(path, token: ApiConfig.adminToken, body: body);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  /// ⭐ v58: admin banner create/update — multipart (optional media).
  /// v61: photo OR video via fileField 'media'.
  Future<String?> adminBannerSave({
    int? id,
    required Map<String, String> fields,
    Uint8List? imageBytes,
    String? imageName,
    String fileField = 'image',
  }) async {
    try {
      await api.postMultipart(
        id == null ? '/api/admin/banners/' : '/api/admin/banners/$id/',
        token: ApiConfig.adminToken,
        fields: fields,
        fileBytes: imageBytes,
        fileName: imageName,
        fileField: fileField,
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  /// ⭐ v60: upload a photo for a hostel product (admin portal).
  Future<String?> adminHostelPhoto(
      int productId, Uint8List bytes, String fileName) async {
    try {
      await api.postMultipart(
        '/api/admin/hostel-products/$productId/photo/',
        token: ApiConfig.adminToken,
        fields: const {},
        fileBytes: bytes,
        fileName: fileName,
        fileField: 'image',
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  /// ⭐ Admin feed composer — post any mix of text, media and a poll.
  Future<String?> adminFeedPost({
    String title = '',
    String message = '',
    String question = '',
    List<String> options = const [],
    String? mediaPath,
    Uint8List? mediaBytes,
    String? mediaName,
  }) async {
    try {
      await api.postMultipart(
        '/api/admin/feed/post/',
        token: ApiConfig.adminToken,
        fields: {
          'title': title,
          'message': message,
          'question': question,
          'options': jsonEncode(options),
        },
        filePath: mediaPath,
        fileBytes: mediaBytes,
        fileName: mediaName,
        fileField: 'media',
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  // ---------------- ⭐ v50: Admin Portal 2.0 helpers ----------------

  /// Full vendor-portal access: fetches the vendor's own session token
  /// and switches the app's vendor session to that vendor. The admin sees
  /// the EXACT same portal the vendor sees.
  /// ⭐ v50.1 speed: fetch the vendor-portal session data WITHOUT
  /// switching to it — used to pre-warm portals so opening is instant.
  Future<Map<String, dynamic>?> adminFetchVendorPortal(int vendorId) async {
    try {
      final r = await api.post('/api/admin/vendors/$vendorId/portal/',
          token: ApiConfig.adminToken, body: {});
      return api.dataOf(r);
    } catch (_) {
      return null;
    }
  }

  /// ⭐ v50.1 speed: apply an already-fetched portal session SYNCHRONOUSLY
  /// (zero network wait) and prefetch the vendor's data in the background
  /// while the screen is still animating in.
  void adminApplyVendorPortal(Map<String, dynamic> data) {
    // Clear the previous vendor's data so nothing stale flashes.
    _vendorIncoming.clear();
    _vendorActive.clear();
    _vendorHistory.clear();
    _vendorOutForDelivery.clear();
    _menuItems.clear();
    _todaySales = 0;
    _menuCount = 0;
    _availableCount = 0;
    ApiConfig.vendorToken = data['token'] as String?;
    vendor = VendorSession(
      id: (data['vendor_id'] ?? 0) as int,
      businessName: (data['business_name'] ?? '') as String,
      vendorType: (data['vendor_type'] ?? 'food') as String,
      phone: (data['phone'] ?? '') as String,
      ownerUsername: (data['owner_username'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      isActive: true,
      isApproved: true,
    );
    notifyListeners();
    // Fire-and-forget prefetch (runs while the screen transitions).
    refreshVendorDashboard();
    loadVendorMenu();
    loadVendorEarnings();
  }

  Future<String?> adminOpenVendorPortal(Map<String, dynamic> v) async {
    final data = await adminFetchVendorPortal((v['id'] ?? 0) as int);
    if (data == null) return 'Could not open the vendor portal.';
    adminApplyVendorPortal(data);
    return null;
  }

  /// ⭐ v50.1: Admin uploads / removes a vendor's UPI payment QR
  /// directly from the admin portal.
  Future<String?> adminVendorQr(int vendorId,
      {Uint8List? bytes, String? fileName, bool remove = false}) async {
    try {
      await api.postMultipart(
        '/api/admin/vendors/$vendorId/qr/',
        token: ApiConfig.adminToken,
        fields: remove ? {'remove': '1'} : {},
        fileBytes: remove ? null : bytes,
        fileName: fileName ?? 'qr.png',
      );
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  /// Leave the vendor-portal view opened from the admin panel (drops the
  /// impersonated vendor session without touching stored vendor logins).
  void adminCloseVendorPortal() {
    ApiConfig.vendorToken = LocalStore.get('vendor_token');
    if (ApiConfig.vendorToken == null ||
        (ApiConfig.vendorToken ?? '').isEmpty) {
      ApiConfig.vendorToken = null;
      vendor = VendorSession();
    } else {
      vendor = VendorSession(
        id: int.tryParse(LocalStore.get('vendor_id') ?? '') ?? 0,
        businessName: LocalStore.get('vendor_name') ?? '',
        vendorType: LocalStore.get('vendor_type') ?? 'food',
        phone: LocalStore.get('vendor_phone') ?? '',
        ownerUsername: LocalStore.get('vendor_owner') ?? '',
        email: LocalStore.get('vendor_email') ?? '',
        isActive: true,
        isApproved: true,
      );
    }
    notifyListeners();
  }

  Future<String?> adminDelete(String path) async {
    try {
      await api.delete(path, token: ApiConfig.adminToken);
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (error) {
      return error.toString();
    }
  }

  // ==================================================================
  // ⭐ v66: CUnnect RIDE — student booking + ride partner portal
  // ==================================================================

  List<dynamic> _rideOptions = [];
  List<dynamic> get rideOptions => _rideOptions;
  double _rideDistanceKm = 0;
  double get rideDistanceKm => _rideDistanceKm;

  Map<String, dynamic>? _activeRide;
  Map<String, dynamic>? get activeRide => _activeRide;
  List<dynamic> _pastRides = [];
  List<dynamic> get pastRides => _pastRides;

  // ---- rider portal state ----
  Map<String, dynamic>? _rideProfile;
  Map<String, dynamic>? get rideProfile => _rideProfile;
  List<dynamic> _rideVehicles = [];
  List<dynamic> get rideVehicles => _rideVehicles;

  /// ⭐ v77: the partner's own cars (name + number plate) — he picks one
  /// of these while accepting a request.
  List<dynamic> _rideGarage = [];
  List<dynamic> get rideGarage => _rideGarage;
  List<dynamic> _rideRequests = [];
  List<dynamic> get rideRequests => _rideRequests;
  List<dynamic> _rideVendorActive = [];
  List<dynamic> get rideVendorActive => _rideVendorActive;
  List<dynamic> _rideVendorPast = [];
  List<dynamic> get rideVendorPast => _rideVendorPast;

  // ⭐ v74: the partner's earnings summary + the student's own stats
  Map<String, dynamic> _rideVendorStats = {};
  Map<String, dynamic> get rideVendorStats => _rideVendorStats;
  Map<String, dynamic> _rideStudentStats = {};
  Map<String, dynamic> get rideStudentStats => _rideStudentStats;

  /// Fare estimate for a pickup -> drop pair (distance + per-vehicle fare).
  Future<String?> rideEstimate({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    String scheduledAt = '',
  }) async {
    try {
      final r = await api.post('/api/ride/estimate/',
          token: ApiConfig.studentToken,
          body: {
            'pickup_lat': pickupLat,
            'pickup_lng': pickupLng,
            'drop_lat': dropLat,
            'drop_lng': dropLng,
            // ⭐ v74: availability is checked for the slot the student
            // picked, so a blocked partner really shows as unavailable.
            'scheduled_at': scheduledAt,
          });
      final d = api.dataOf(r);
      _rideDistanceKm = (d['distance_km'] as num?)?.toDouble() ?? 0;
      _rideOptions = (d['options'] as List?) ?? const [];
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not calculate the fare. Please try again.';
    }
  }

  /// Book a ride. Returns the ride on success.
  Future<Map<String, dynamic>> rideBook({
    required String vehicleType,
    required String pickupText,
    required double pickupLat,
    required double pickupLng,
    required String dropText,
    required double dropLat,
    required double dropLng,
    required String phone,
    required String scheduledAt,
    String notes = '',
    // ⭐ v73: booked on someone else's behalf
    bool forOther = false,
    String otherName = '',
    String otherPhone = '',
  }) async {
    try {
      final r = await api.post('/api/ride/book/',
          token: ApiConfig.studentToken,
          body: {
            'vehicle_type': vehicleType,
            'pickup_text': pickupText,
            'pickup_lat': pickupLat,
            'pickup_lng': pickupLng,
            'drop_text': dropText,
            'drop_lat': dropLat,
            'drop_lng': dropLng,
            'phone': phone,
            'scheduled_at': scheduledAt,
            'notes': notes,
            'booking_for_other': forOther,
            'other_name': otherName,
            'other_phone': otherPhone,
          });
      final d = api.dataOf(r);
      final ride = Map<String, dynamic>.from(d['ride'] as Map? ?? {});
      _activeRide = ride;
      LocalStore.set('active_ride_code', '${ride['ride_code'] ?? ''}');
      _cacheRide(ride);
      notifyListeners();
      return {'ok': true, 'ride': ride};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {'ok': false, 'error': 'Could not book the ride. Try again.'};
    }
  }

  /// My rides (active + past).
  Future<void> loadRides() async {
    if (ApiConfig.studentToken == null) return;
    try {
      final r = await api.get('/api/ride/list/',
          token: ApiConfig.studentToken);
      final d = api.dataOf(r);
      final active = (d['active'] as List?) ?? const [];
      _pastRides = (d['past'] as List?) ?? const [];
      _activeRide = active.isNotEmpty
          ? Map<String, dynamic>.from(active.first as Map)
          : null;
      _cacheRide(_activeRide);
      if (_activeRide == null) {
        LocalStore.remove('active_ride_code');
      } else {
        LocalStore.set('active_ride_code', '${_activeRide!['ride_code'] ?? ''}');
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshActiveRide(String code) async {
    if (ApiConfig.studentToken == null || code.isEmpty) return;
    try {
      final r = await api.get('/api/ride/$code/',
          token: ApiConfig.studentToken);
      _activeRide = Map<String, dynamic>.from(
          (api.dataOf(r))['ride'] as Map? ?? {});
      _cacheRide(_activeRide);
      notifyListeners();
    } catch (_) {}
  }

  /// ⭐ v72: a single ride by code (used by the full-screen live map).
  /// Always refreshes the local cache so every screen paints instantly.
  Future<Map<String, dynamic>?> rideDetail(String code) async {
    if (ApiConfig.studentToken == null || code.isEmpty) return null;
    try {
      final r = await api.get('/api/ride/$code/',
          token: ApiConfig.studentToken);
      final ride = Map<String, dynamic>.from(
          (api.dataOf(r))['ride'] as Map? ?? {});
      _cacheRide(ride);
      return ride;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> ridePay(
      String code, String mode, String txnId) async {
    try {
      final r = await api.post('/api/ride/$code/pay/',
          token: ApiConfig.studentToken,
          body: {'mode': mode, 'txn_id': txnId});
      final d = api.dataOf(r);
      _activeRide = Map<String, dynamic>.from(d['ride'] as Map? ?? {});
      _cacheRide(_activeRide);
      notifyListeners();
      return {'ok': true, 'paid': d['paid']};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {'ok': false, 'error': 'Payment could not be recorded.'};
    }
  }

  Future<Map<String, dynamic>> ridePayBalance(String code, String txnId) async {
    try {
      final r = await api.post('/api/ride/$code/pay-balance/',
          token: ApiConfig.studentToken, body: {'txn_id': txnId});
      final d = api.dataOf(r);
      _activeRide = Map<String, dynamic>.from(d['ride'] as Map? ?? {});
      _cacheRide(_activeRide);
      notifyListeners();
      return {'ok': true, 'paid': d['paid']};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {'ok': false, 'error': 'Payment could not be recorded.'};
    }
  }

  Future<Map<String, dynamic>> rideVerifyOtp(String code, String otp) async {
    try {
      final r = await api.post('/api/ride/$code/verify-otp/',
          token: ApiConfig.studentToken, body: {'otp': otp.trim()});
      _activeRide = Map<String, dynamic>.from(
          (api.dataOf(r))['ride'] as Map? ?? {});
      _cacheRide(_activeRide);
      notifyListeners();
      return {'ok': true};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {'ok': false, 'error': 'Could not verify the OTP.'};
    }
  }

  Future<String?> rideCancel(String code) async {
    try {
      await api.post('/api/ride/$code/cancel/',
          token: ApiConfig.studentToken, body: {});
      _activeRide = null;
      notifyListeners();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not cancel the ride.';
    }
  }

  // ---------------------- ride partner portal ----------------------

  /// ⭐ v74: the student's ride statistics (rides, km, spent, favourites).
  Future<void> loadRideStats() async {
    if (ApiConfig.studentToken == null) return;
    try {
      final r = await api.get('/api/ride/stats/',
          token: ApiConfig.studentToken);
      final d = api.dataOf(r);
      if (d['stats'] is Map) {
        _rideStudentStats = Map<String, dynamic>.from(d['stats'] as Map);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> loadRideVendorProfile() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final r = await api.get('/api/ride/vendor/profile/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      _rideProfile = Map<String, dynamic>.from(d['profile'] as Map? ?? {});
      _rideVehicles = (d['vehicles'] as List?) ?? const [];
      _rideGarage = (d['garage'] as List?) ?? const [];
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> saveRideVendorProfile({
    required String vehicleNumber,
    required String vehicleModel,
    required bool isOnline,
    required Map<String, Map<String, dynamic>> rates,
    bool? isAuto,
  }) async {
    try {
      final body = <String, dynamic>{
        'vehicle_number': vehicleNumber,
        'vehicle_model': vehicleModel,
        'is_online': isOnline,
        // ⭐ v79: "I drive an auto" — these partners get the one-tap calls
        if (isAuto != null) 'is_auto': isAuto,
      };
      body.addAll(rates);
      final r = await api.post('/api/ride/vendor/profile/',
          token: ApiConfig.vendorToken, body: body);
      api.dataOf(r);
      await loadRideVendorProfile();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not save the ride profile.';
    }
  }

  Future<void> loadRideRequests() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final r = await api.get('/api/ride/vendor/requests/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      _rideRequests = (d['requests'] as List?) ?? const [];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadRideVendorRides() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final r = await api.get('/api/ride/vendor/rides/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      _rideVendorActive = (d['active'] as List?) ?? const [];
      _rideVendorPast = (d['past'] as List?) ?? const [];
      if (d['stats'] is Map) {
        _rideVendorStats = Map<String, dynamic>.from(d['stats'] as Map);
      }
      notifyListeners();
    } catch (_) {}
  }

  /// OTP the rider just triggered (shown once, right after arriving).
  String? _lastRideOtp;
  String? get lastRideOtp => _lastRideOtp;

  /// ⭐ v68: the RIDER types the OTP the student reads out to him.
  Future<String?> rideVendorStart(String code, String otp) async {
    try {
      await api.post('/api/ride/vendor/start/$code/',
          token: ApiConfig.vendorToken, body: {'otp': otp.trim()});
      await loadRideVendorRides();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not start the ride. Check the OTP.';
    }
  }

  /// ⭐ v68: rider app pushes its GPS so the student sees him move.
  Future<bool> rideVendorLocation(String code, double lat, double lng) async {
    try {
      await api.post('/api/ride/vendor/location/$code/',
          token: ApiConfig.vendorToken, body: {'lat': lat, 'lng': lng});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ⭐ v72: the student shares their own live position with the rider
  /// (pass `share` to switch it on/off).
  /// ⭐ v73: rider unavailability slots (daily + specific dates).
  Future<List<Map<String, dynamic>>> loadRideBlocks() async {
    try {
      final r = await api.get('/api/ride/vendor/blocks/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      final list = d['blocks'] as List? ?? [];
      _rideBlocks = [for (final e in list) Map<String, dynamic>.from(e as Map)];
      notifyListeners();
      return _rideBlocks;
    } catch (_) {
      return _rideBlocks;
    }
  }

  List<Map<String, dynamic>> _rideBlocks = const [];
  List<Map<String, dynamic>> get rideBlocks => _rideBlocks;

  Future<String?> addRideBlock(Map<String, dynamic> body) async {
    try {
      await api.post('/api/ride/vendor/blocks/',
          token: ApiConfig.vendorToken, body: body);
      await loadRideBlocks();
      return null;
    } catch (e) {
      return 'Could not save the slot.';
    }
  }

  Future<void> deleteRideBlock(int id) async {
    try {
      await api.post('/api/ride/vendor/blocks/$id/delete/',
          token: ApiConfig.vendorToken, body: {});
      await loadRideBlocks();
    } catch (_) {}
  }

  Future<bool> rideStudentLocation(String code,
      {double? lat, double? lng, bool? share}) async {
    try {
      final body = <String, dynamic>{
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (share != null) 'share': share,
      };
      await api.post('/api/ride/student/location/$code/',
          token: ApiConfig.studentToken, body: body);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ⭐ v68: everything the rider console needs, fetched IN PARALLEL so
  /// the screen paints in one round-trip instead of four.
  Future<void> loadRideConsole() async {
    if (ApiConfig.vendorToken == null) return;
    await Future.wait([
      loadRideVendorProfile(),
      loadRideRequests(),
      loadRideVendorRides(),
      loadRideBlocks(),
    ]);
  }

  /// ⭐ v68: last known ride snapshot — painted instantly on screen
  /// open while the fresh copy loads in the background (no blank wait).
  Map<String, dynamic>? cachedRide() {
    final raw = LocalStore.get('ride_cache');
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  void _cacheRide(Map<String, dynamic>? ride) {
    try {
      if (ride == null) {
        LocalStore.remove('ride_cache');
      } else {
        LocalStore.set('ride_cache', jsonEncode(ride));
      }
    } catch (_) {}
  }

  Future<String?> rideVendorAction(String action, String code) async {
    try {
      final r = await api.post('/api/ride/vendor/$action/$code/',
          token: ApiConfig.vendorToken, body: {});
      final d = api.dataOf(r);
      if (d['otp'] != null) _lastRideOtp = '${d['otp']}';
      await loadRideVendorRides();
      await loadRideRequests();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'That action did not go through. Please try again.';
    }
  }

  // ------------------------- v74 additions -------------------------

  /// ⭐ v78: ending a 50-50 ride PARKS it until the student pays the
  /// balance, so the console has to hear back what actually happened.
  /// ⭐ v79: ONE TAP on the AUTO button -> every auto partner on campus
  /// is alerted at the same moment. No booking, no fare, no payment —
  /// the pickup is always the campus main gate.
  /// \u2b50 v81: the AUTO portal — what is waiting for this partner.
  Future<void> loadAutoIncoming() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final r = await api.get('/api/ride/auto/incoming/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      _autoOnline = (d['auto_online'] ?? true) == true;
      _isAutoPartner = (d['is_auto'] ?? false) == true;
      _autoCalls = [
        for (final c in (d['calls'] as List? ?? [])) Map<String, dynamic>.from(c)
      ];
      _autoRecent = [
        for (final c in (d['recent'] as List? ?? [])) Map<String, dynamic>.from(c)
      ];
      _autoAcceptedToday = (d['accepted_today'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _autoCalls = [];
  List<Map<String, dynamic>> _autoRecent = [];
  bool _autoOnline = true;
  bool _isAutoPartner = false;
  int _autoAcceptedToday = 0;

  List<Map<String, dynamic>> get autoCalls => _autoCalls;
  List<Map<String, dynamic>> get autoRecent => _autoRecent;
  bool get autoOnline => _autoOnline;
  bool get isAutoPartner => _isAutoPartner;
  int get autoAcceptedToday => _autoAcceptedToday;

  /// \u2b50 v81: accept or decline an AUTO call.
  Future<Map<String, dynamic>> respondAutoCall(
      int callId, bool accept) async {
    try {
      final r = await api.post('/api/ride/auto/respond/',
          token: ApiConfig.vendorToken,
          body: {'call_id': callId, 'action': accept ? 'accept' : 'decline'});
      final d = api.dataOf(r);
      await loadAutoIncoming();
      return {'ok': true, 'call': d['call'] ?? {}};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {'ok': false, 'error': 'Could not answer that call. Try again.'};
    }
  }

  /// \u2b50 v81: the AUTO portal duty switch.
  Future<bool> setAutoOnline(bool value) async {
    _autoOnline = value;
    notifyListeners();
    try {
      await api.post('/api/ride/auto/status/',
          token: ApiConfig.vendorToken, body: {'auto_online': value});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadAutoHistory() async {
    if (ApiConfig.vendorToken == null) return;
    try {
      final r = await api.get('/api/ride/auto/history/',
          token: ApiConfig.vendorToken);
      final d = api.dataOf(r);
      _autoHistory = [
        for (final c in (d['calls'] as List? ?? [])) Map<String, dynamic>.from(c)
      ];
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _autoHistory = [];
  List<Map<String, dynamic>> get autoHistory => _autoHistory;

  // ---------------- admin: the AUTO portal from the panel ----------------

  Future<void> loadAdminAutoPartners() async {
    try {
      final r = await api.get('/api/admin/auto-partners/',
          token: ApiConfig.adminToken);
      final d = api.dataOf(r);
      _adminAutoPartners = [
        for (final p in (d['partners'] as List? ?? []))
          Map<String, dynamic>.from(p)
      ];
      _adminOtherPartners = [
        for (final p in (d['others'] as List? ?? []))
          Map<String, dynamic>.from(p)
      ];
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _adminAutoPartners = [];
  List<Map<String, dynamic>> _adminOtherPartners = [];
  List<Map<String, dynamic>> get adminAutoPartners => _adminAutoPartners;
  List<Map<String, dynamic>> get adminOtherPartners => _adminOtherPartners;

  Future<bool> adminSetAutoPartner(
      int vendorId, bool isAuto, bool autoOnline) async {
    try {
      await api.post('/api/admin/auto-partners/$vendorId/',
          token: ApiConfig.adminToken,
          body: {'is_auto': isAuto, 'auto_online': autoOnline});
      await loadAdminAutoPartners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// \u2b50 v81: the admin creates a whole AUTO account from the panel.
  Future<bool> adminCreateAutoPartner(
      String name, String phone, String password) async {
    try {
      await api.post('/api/admin/auto-partners/add/',
          token: ApiConfig.adminToken,
          body: {
            'business_name': name,
            'phone': phone,
            'password': password
          });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadAdminAutoCalls() async {
    try {
      final r = await api.get('/api/admin/auto-calls/',
          token: ApiConfig.adminToken);
      final d = api.dataOf(r);
      _adminAutoCalls = [
        for (final c in (d['calls'] as List? ?? [])) Map<String, dynamic>.from(c)
      ];
      notifyListeners();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _adminAutoCalls = [];
  List<Map<String, dynamic>> get adminAutoCalls => _adminAutoCalls;

  Future<Map<String, dynamic>> rideAutoCall() async {
    try {
      final r = await api.post('/api/ride/auto/call/',
          token: ApiConfig.studentToken, body: {});
      final d = api.dataOf(r);
      return {
        'ok': true,
        'sent': (d['sent'] as num?)?.toInt() ?? 0,
        'message': '${d['message'] ?? 'Auto partners alerted.'}',
      };
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {
        'ok': false,
        'error': 'Could not reach the auto partners. Try again.'
      };
    }
  }

  Future<Map<String, dynamic>> rideVendorComplete(String code) async {
    try {
      final r = await api.post('/api/ride/vendor/complete/$code/',
          token: ApiConfig.vendorToken, body: {});
      final d = api.dataOf(r);
      await loadRideVendorRides();
      await loadRideRequests();
      return {'ok': true, 'awaiting': d['awaiting_balance'] == true};
    } on ApiException catch (error) {
      return {'ok': false, 'error': error.message};
    } catch (_) {
      return {
        'ok': false,
        'error': 'That action did not go through. Please try again.'
      };
    }
  }

  /// The ride partner confirms he took the remaining cash.
  Future<String?> rideCollectBalance(String code) async {
    try {
      await api.post('/api/ride/vendor/collect-balance/$code/',
          token: ApiConfig.vendorToken, body: {});
      await loadRideVendorRides();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not update the payment. Try again.';
    }
  }

  /// ⭐ v75: the rider confirms the payment HIMSELF — nothing moves on
  /// automatically once the student has paid.
  /// ⭐ v77: accept a request WITH the car the rider will drive — one of
  /// his saved vehicles (id) or a one-off for this ride only.
  Future<String?> rideVendorAccept(String code,
      {int? vehicleId, String? vehicleName, String? vehiclePlate}) async {
    try {
      final body = <String, dynamic>{
        if (vehicleId != null) 'vehicle_id': vehicleId,
        if (vehicleName != null) 'vehicle_name': vehicleName,
        if (vehiclePlate != null) 'vehicle_plate': vehiclePlate,
      };
      await api.post('/api/ride/vendor/accept/$code/',
          token: ApiConfig.vendorToken, body: body);
      await loadRideVendorProfile();
      await loadRideVendorRides();
      await loadRideRequests();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'That action did not go through. Please try again.';
    }
  }

  /// ⭐ v77: the partner's garage — every car with its number plate.
  Future<String?> addRideVehicle(
      String type, String name, String plate) async {
    try {
      await api.post('/api/ride/vendor/vehicles/',
          token: ApiConfig.vendorToken,
          body: {'vehicle_type': type, 'name': name, 'plate': plate});
      await loadRideVendorProfile();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not save the vehicle. Try again.';
    }
  }

  Future<String?> deleteRideVehicle(int id) async {
    try {
      await api.post('/api/ride/vendor/vehicles/$id/delete/',
          token: ApiConfig.vendorToken, body: {});
      await loadRideVendorProfile();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not remove the vehicle. Try again.';
    }
  }

  Future<String?> rideVendorConfirm(String code) async {
    return rideVendorAction('confirm', code);
  }

  /// ⭐ v75: payment QR for a ride. The amount is baked into the QR and
  /// into the `upi://` link, so scanning fills the exact fare (the app
  /// cannot key in a different one).
  Future<Map<String, dynamic>?> fetchRideQr(String code, num amount) async {
    try {
      final r = await api.get(
          '/api/ride/upi/$code/?amount=${amount.toStringAsFixed(2)}',
          token: ApiConfig.studentToken);
      final d = api.dataOf(r);
      if (d.isEmpty) return null;
      return d;
    } on ApiException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Co-passengers on a ride (fare split between friends).
  Future<List<Map<String, dynamic>>> ridePax(String code) async {
    try {
      final r = await api.get('/api/ride/$code/pax/',
          token: ApiConfig.studentToken);
      final d = api.dataOf(r);
      return ((d['pax'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String?> ridePaxAdd(String code,
      {required String name, required String phone, required double amount}) async {
    try {
      await api.post('/api/ride/$code/pax/',
          token: ApiConfig.studentToken,
          body: {'name': name, 'phone': phone, 'amount': amount});
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not add that person.';
    }
  }

  Future<String?> ridePaxUpdate(String code, int paxId,
      {bool? paid, double? amount, String? name, String? phone}) async {
    try {
      await api.post('/api/ride/$code/pax/$paxId/',
          token: ApiConfig.studentToken,
          body: {
            if (paid != null) 'paid': paid,
            if (amount != null) 'amount': amount,
            if (name != null) 'name': name,
            if (phone != null) 'phone': phone,
          });
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not update that person.';
    }
  }

  Future<String?> ridePaxDelete(String code, int paxId) async {
    try {
      await api.post('/api/ride/$code/pax/$paxId/',
          token: ApiConfig.studentToken, body: {'delete': true});
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not remove that person.';
    }
  }

  /// ⭐ SOS — alerts this ride's partner and every other online partner.
  Future<String?> rideSos(String code, {double? lat, double? lng}) async {
    try {
      await api.post('/api/ride/$code/sos/',
          token: ApiConfig.studentToken,
          body: {'lat': lat, 'lng': lng});
      return null;
    } on ApiException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not send the SOS. Call your rider directly.';
    }
  }
}
