import 'dart:convert';

import 'package:cunnect_food/services/api_client.dart';
import 'package:cunnect_food/services/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Ye tests AppStore ko mocked HTTP client ke saath chalate hain —
/// real Django backend ka response shape verify hota hai bina server ke.
void main() {
  setUp(() {
    ApiConfig.studentToken = null;
    ApiConfig.vendorToken = null;
    ApiConfig.deliveryToken = null;
  });

  MockClient _client(Map<String, dynamic> Function(http.Request request) handler) {
    return MockClient((request) async {
      final payload = handler(request);
      return http.Response(jsonEncode(payload), 200,
          headers: {'content-type': 'application/json'});
    });
  }

  testWidgets('student login stores token and profile', (tester) async {
    final store = AppStore(
      apiClient: ApiClient(
        httpClient: _client((request) {
          if (request.url.path == '/api/auth/student-login/') {
            return {
              'ok': true,
              'data': {
                'token': 'test-token-123',
                'uid': 'ede',
                'name': 'adars',
                'phone': '8974897597',
                'branch': 'BTech cse',
                'year': '1st Year',
              },
            };
          }
          // dashboard banners call
          return {
            'ok': true,
            'data': {
              'banners': [
                {'id': 1, 'title': 'B1', 'image_url': '/media/banners/1.png'},
              ],
            },
          };
        }),
      ),
    );

    final error = await store.studentLogin('ede', 'student123');
    expect(error, isNull);
    await store.loadDashboardBanners();
    expect(store.customerName, 'adars');
    expect(store.studentUid, 'ede');
    expect(store.customerPhone, '8974897597');
    expect(store.dashboardBanners.length, 1);
    expect(store.dashboardBanners.first.imageUrl, contains('/media/banners/1.png'));
  });

  testWidgets('invalid login returns backend error', (tester) async {
    final client = MockClient((request) async {
      return http.Response(
          jsonEncode({'ok': false, 'error': 'Invalid UID or password.'}), 401);
    });
    final store = AppStore(apiClient: ApiClient(httpClient: client));

    final error = await store.studentLogin('ede', 'wrong');
    expect(error, 'Invalid UID or password.');
    expect(store.studentLoggedIn, isFalse);
  });

  testWidgets('food home parses items, slides and coupons', (tester) async {
    final store = AppStore(
      apiClient: ApiClient(
        httpClient: _client((request) {
          return {
            'ok': true,
            'data': {
              'items': [
                {
                  'id': 2,
                  'name': 'Classic Veg Burger',
                  'price': 50.0,
                  'description': 'Crisped patty',
                  'image_url': '/media/food_images/burger.png',
                  'category': 'burger',
                  'vendor_id': 2,
                  'vendor_name': 'Campus Kitchen',
                  'is_available': true,
                },
              ],
              'hero_slides': [
                {'id': 1, 'title': '1', 'subtitle': '', 'image_url': '/media/hero.png'},
              ],
              'offers': <Map<String, dynamic>>[],
              'coupons': [
                {
                  'code': 'WELCOME10',
                  'discount_type': 'fixed',
                  'discount_value': 20.0,
                  'minimum_order_value': 100.0,
                },
              ],
            },
          };
        }),
      ),
    );

    await store.loadFoodHome();
    expect(store.foodItems.length, 1);
    expect(store.foodItems.first.name, 'Classic Veg Burger');
    expect(store.heroSlides.length, 1);
    expect(store.coupons.first.code, 'WELCOME10');
    expect(store.searchFood('burger').length, 1);
  });

  testWidgets('place order sends cart items and clears cart', (tester) async {
    Map<String, dynamic>? capturedBody;
    final store = AppStore(
      apiClient: ApiClient(
        httpClient: _client((request) {
          if (request.url.path == '/api/food/home/') {
            return {
              'ok': true,
              'data': {
                'items': [
                  {
                    'id': 2,
                    'name': 'Classic Veg Burger',
                    'price': 50.0,
                    'description': '',
                    'image_url': '',
                    'category': 'burger',
                    'vendor_id': 2,
                    'vendor_name': 'Campus Kitchen',
                    'is_available': true,
                  },
                ],
                'hero_slides': <Map<String, dynamic>>[],
                'offers': <Map<String, dynamic>>[],
                'coupons': <Map<String, dynamic>>[],
              },
            };
          }
          if (request.url.path == '/api/food/orders/') {
            capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
            return {
              'ok': true,
              'data': {
                'order_numbers': ['CU-TEST1234'],
                'orders': [
                  {
                    'id': 500,
                    'order_number': 'CU-TEST1234',
                    'vendor_id': 2,
                    'vendor_name': 'Campus Kitchen',
                    'customer_name': 'adars',
                    'customer_phone': '8974897597',
                    'delivery_address': 'Chandigarh University',
                    'landmark': '',
                    'payment_method': 'cash',
                    'note': '',
                    'subtotal': 100.0,
                    'discount': 0.0,
                    'total': 100.0,
                    'status': 'pending',
                    'delivery_otp': '1234',
                    'created_at_iso': DateTime.now().toIso8601String(),
                    'items': [
                      {'name': 'Classic Veg Burger', 'price': 50.0, 'quantity': 2},
                    ],
                  },
                ],
              },
            };
          }
          // my-orders refresh after placing
          return {'ok': true, 'data': {'orders': <Map<String, dynamic>>[]}};
        }),
      ),
    );

    await store.loadFoodHome();
    store.addToCart(2);
    store.addToCart(2);
    expect(store.cartCount, 2);
    expect(store.cartTotal, 100);

    final error = await store.placeOrder(paymentMethod: 'cash', orderNote: '');
    expect(error, isNull);
    expect(store.cart, isEmpty);
    expect(store.recentOrderSuccess.first.orderNumber, 'CU-TEST1234');
    expect(capturedBody, isNotNull);
    expect(capturedBody!['payment'], 'cash');
    expect((capturedBody!['items'] as List).first['quantity'], 2);
  });

  testWidgets('chat rooms parse with official flag', (tester) async {
    final store = AppStore(
      apiClient: ApiClient(
        httpClient: _client((request) {
          return {
            'ok': true,
            'data': {
              'rooms': [
                {
                  'id': 13,
                  'name': 'CUnnect',
                  'privacy': 'public',
                  'members_count': 6,
                  'online_count': 1,
                  'official': true,
                  'is_member': true,
                  'pending': false,
                },
                {
                  'id': 6,
                  'name': 'Boys Hostel',
                  'privacy': 'private',
                  'members_count': 2,
                  'online_count': 0,
                  'official': false,
                  'is_member': true,
                  'pending': false,
                },
              ],
            },
          };
        }),
      ),
    );

    await store.loadChatRooms();
    expect(store.chatRooms.length, 2);
    expect(store.chatRooms.first.name, 'CUnnect');
    expect(store.chatRooms.first.official, isTrue);
    expect(store.roomByName('Boys Hostel')?.privacy, 'private');
  });

  testWidgets('vendor login and dashboard parse', (tester) async {
    final store = AppStore(
      apiClient: ApiClient(
        httpClient: _client((request) {
          if (request.url.path == '/api/vendor/login/') {
            return {
              'ok': true,
              'data': {
                'token': 'vendor-token',
                'business_name': 'Campus Kitchen',
                'vendor_type': 'food',
              },
            };
          }
          return {
            'ok': true,
            'data': {
              'incoming_count': 1,
              'active_count': 0,
              'today_sales': 180.0,
              'menu_count': 6,
              'available_count': 6,
              'kitchen_open': true,
              'incoming_orders': [
                {
                  'id': 112,
                  'order_number': 'CU-B12056EB',
                  'vendor_id': 2,
                  'vendor_name': 'Campus Kitchen',
                  'customer_name': 'adars',
                  'customer_phone': '',
                  'delivery_address': '',
                  'landmark': '',
                  'payment_method': 'cash',
                  'note': '',
                  'subtotal': 180.0,
                  'discount': 0.0,
                  'total': 180.0,
                  'status': 'pending',
                  'delivery_otp': '',
                  'created_at_iso': DateTime.now().toIso8601String(),
                  'items': <Map<String, dynamic>>[],
                },
              ],
              'active_orders': <Map<String, dynamic>>[],
              'history_orders': <Map<String, dynamic>>[],
              'out_for_delivery_orders': <Map<String, dynamic>>[],
            },
          };
        }),
      ),
    );

    final result = await store.vendorLogin('9874563210', 'vendor123');
    expect(result.success, isTrue);
    await store.refreshVendorDashboard();
    expect(store.vendor.businessName, 'Campus Kitchen');
    expect(store.vendorIncomingOrders.length, 1);
    expect(store.vendorIncomingOrders.first.orderNumber, 'CU-B12056EB');
    expect(store.todaySales, 180);
    expect(store.kitchenOpen, isTrue);
  });
}
