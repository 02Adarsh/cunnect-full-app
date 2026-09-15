/// Data models — Flutter mirror of the Django models.
/// Har model `fromJson` ke saath aata hai jo `/api/...` responses parse karta hai.

// ---------------------------------------------------------------------
// Food app
// ---------------------------------------------------------------------

class FoodItem {
  final int id;
  final String name;
  final double price;
  final String description;
  final String imageUrl;
  final String category;
  final int vendorId;
  final String vendorName;
  final String vendorLogo;
  bool isAvailable;
  final int stock;

  FoodItem({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.vendorId,
    required this.vendorName,
    required this.vendorLogo,
    required this.isAvailable,
    required this.stock,
  });

  /// Purani screens `item.image` use karti thi — ab URL hai.
  String get image => imageUrl;

  factory FoodItem.fromJson(Map<String, dynamic> json, String Function(String) media) {
    return FoodItem(
      id: (json['id'] ?? 0) as int,
      name: (json['name'] ?? '') as String,
      price: ((json['price'] ?? 0) as num).toDouble(),
      description: (json['description'] ?? '') as String,
      imageUrl: media((json['image_url'] ?? '') as String),
      category: (json['category'] ?? '') as String,
      vendorId: (json['vendor_id'] ?? 0) as int,
      vendorName: (json['vendor_name'] ?? '') as String,
      vendorLogo: (json['vendor_logo'] ?? '') as String,
      isAvailable: (json['is_available'] ?? false) as bool,
      stock: (json['stock'] ?? 0) as int,
    );
  }
}

class HeroSlide {
  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;

  HeroSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  String get image => imageUrl;

  factory HeroSlide.fromJson(Map<String, dynamic> json, String Function(String) media) {
    return HeroSlide(
      id: (json['id'] ?? 0) as int,
      title: (json['title'] ?? '') as String,
      subtitle: (json['subtitle'] ?? '') as String,
      imageUrl: media((json['image_url'] ?? '') as String),
    );
  }
}

class FoodOffer {
  final int id;
  final String title;
  final String description;
  final String couponCode;
  final String imageUrl;

  FoodOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.couponCode,
    required this.imageUrl,
  });

  factory FoodOffer.fromJson(Map<String, dynamic> json, String Function(String) media) {
    return FoodOffer(
      id: (json['id'] ?? 0) as int,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      couponCode: (json['coupon_code'] ?? '') as String,
      imageUrl: media((json['image_url'] ?? '') as String),
    );
  }
}

class Coupon {
  final String code;
  final String discountType; // 'percent' | 'fixed'
  final double discountValue;
  final double minimumOrderValue;

  Coupon({
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minimumOrderValue,
  });

  String get discountLabel => discountType == 'percent'
      ? '$discountValue% off'
      : '₹${discountValue.round()} off';

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      code: (json['code'] ?? '') as String,
      discountType: (json['discount_type'] ?? 'fixed') as String,
      discountValue: ((json['discount_value'] ?? 0) as num).toDouble(),
      minimumOrderValue: ((json['minimum_order_value'] ?? 0) as num).toDouble(),
    );
  }
}

class CartItem {
  final FoodItem foodItem;
  int quantity;

  CartItem({required this.foodItem, this.quantity = 1});

  double get lineTotal => foodItem.price * quantity;

  double get subtotal => lineTotal;
}

enum OrderStatus {
  pending,
  accepted,
  rejected,
  preparing,
  ready,
  outForDelivery,
  completed,
  cancelled,
}

OrderStatus parseOrderStatus(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'accepted':
      return OrderStatus.accepted;
    case 'rejected':
      return OrderStatus.rejected;
    case 'preparing':
      return OrderStatus.preparing;
    case 'ready':
      return OrderStatus.ready;
    case 'out_for_delivery':
      return OrderStatus.outForDelivery;
    case 'completed':
      return OrderStatus.completed;
    case 'cancelled':
      return OrderStatus.cancelled;
    default:
      return OrderStatus.pending;
  }
}

extension OrderStatusX on OrderStatus {
  /// Customer-facing copy — Django my_orders.html wale messages jaise.
  String get customerCopy {
    switch (this) {
      case OrderStatus.pending:
        return 'Waiting for the kitchen to accept';
      case OrderStatus.accepted:
        return 'Kitchen ne order accept kar liya';
      case OrderStatus.rejected:
        return 'Order rejected by the kitchen';
      case OrderStatus.preparing:
        return 'Your food is being prepared';
      case OrderStatus.ready:
        return 'Ready — assigning a delivery partner';
      case OrderStatus.outForDelivery:
        return 'Out for delivery — keep your OTP ready';
      case OrderStatus.completed:
        return 'Delivered. Enjoy!';
      case OrderStatus.cancelled:
        return 'Order cancelled';
    }
  }

  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.outForDelivery:
        return 'Out for delivery';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class OrderItem {
  final String name;
  final double price;
  final int quantity;

  String get itemName => name;

  OrderItem({required this.name, required this.price, required this.quantity});

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: (json['name'] ?? '') as String,
      price: ((json['price'] ?? 0) as num).toDouble(),
      quantity: (json['quantity'] ?? 1) as int,
    );
  }
}

class Order {
  final int id;
  final String orderNumber;
  final int vendorId;
  final String vendorName;
  final String customerName;
  final String customerPhone;
  final String customerUid;
  final String customerBranch;
  final String customerYear;
  final String customerHostel;
  final String customerRoom;
  final String customerUpi;
  final String txnLast4;
  final String txnId;
  final String deliveryAddress;
  final String landmark;
  final String paymentMethod;
  final String note;
  final double subtotal;
  final double discount;
  final double total;
  OrderStatus status;
  final String deliveryOtp;
  final DateTime createdAt;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.orderNumber,
    required this.vendorId,
    required this.vendorName,
    required this.customerName,
    required this.customerPhone,
    required this.customerUid,
    required this.customerBranch,
    required this.customerYear,
    required this.customerHostel,
    required this.customerRoom,
    required this.customerUpi,
    required this.txnLast4,
    this.txnId = '',
    required this.deliveryAddress,
    required this.landmark,
    required this.paymentMethod,
    required this.note,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.status,
    required this.deliveryOtp,
    required this.createdAt,
    required this.items,
  });

  double get totalAmount => total;
  DateTime get updatedAt => createdAt;
  DateTime? get deliveredAt => status == OrderStatus.completed ? createdAt : null;
  bool get otpVerified =>
      status == OrderStatus.completed || deliveryOtp.isEmpty;

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: (json['id'] ?? 0) as int,
      orderNumber: (json['order_number'] ?? '') as String,
      vendorId: (json['vendor_id'] ?? 0) as int,
      vendorName: (json['vendor_name'] ?? '') as String,
      customerName: (json['customer_name'] ?? '') as String,
      customerPhone: (json['customer_phone'] ?? '') as String,
      customerUid: (json['customer_uid'] ?? '') as String,
      customerBranch: (json['customer_branch'] ?? '') as String,
      customerYear: (json['customer_year'] ?? '') as String,
      customerHostel: (json['customer_hostel'] ?? '') as String,
      customerRoom: (json['customer_room'] ?? '') as String,
      customerUpi: (json['customer_upi'] ?? '') as String,
      txnLast4: (json['txn_last4'] ?? '') as String,
      txnId: (json['txn_id'] ?? '') as String,
      deliveryAddress: (json['delivery_address'] ?? '') as String,
      landmark: (json['landmark'] ?? '') as String,
      paymentMethod: (json['payment_method'] ?? 'cash') as String,
      note: (json['note'] ?? '') as String,
      subtotal: ((json['subtotal'] ?? 0) as num).toDouble(),
      discount: ((json['discount'] ?? 0) as num).toDouble(),
      total: ((json['total'] ?? 0) as num).toDouble(),
      status: parseOrderStatus(json['status'] as String?),
      deliveryOtp: (json['delivery_otp'] ?? '') as String,
      createdAt: DateTime.tryParse((json['created_at_iso'] ?? '') as String) ??
          DateTime.now(),
      items: [
        for (final item in (json['items'] as List? ?? []))
          OrderItem.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}

class AppNotification {
  final int id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: (json['id'] ?? 0) as int,
      title: (json['title'] ?? '') as String,
      message: (json['message'] ?? '') as String,
      isRead: (json['is_read'] ?? false) as bool,
      createdAt: DateTime.tryParse((json['created_at_iso'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}

/// Dashboard banner (myapp.Banner).
class DashboardBanner {
  final int id;
  final String title;
  final String imageUrl;

  DashboardBanner({required this.id, required this.title, required this.imageUrl});

  factory DashboardBanner.fromJson(Map<String, dynamic> json, String Function(String) media) {
    return DashboardBanner(
      id: (json['id'] ?? 0) as int,
      title: (json['title'] ?? '') as String,
      imageUrl: media((json['image_url'] ?? '') as String),
    );
  }
}

// ---------------------------------------------------------------------
// Chat (network app)
// ---------------------------------------------------------------------

enum ChatMessageKind { text, image, attachment, poll }

class ChatMessage {
  final int id;
  final String username;
  final String displayName;
  final String content;
  final ChatMessageKind kind;
  final String imageUrl;
  final String videoUrl;
  final int likeCount;
  final bool likedByMe;
  final bool pinned;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.username,
    required this.displayName,
    required this.content,
    required this.kind,
    required this.imageUrl,
    required this.videoUrl,
    required this.likeCount,
    required this.likedByMe,
    required this.pinned,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String Function(String) media) {
    ChatMessageKind kind = ChatMessageKind.text;
    final rawKind = (json['kind'] ?? 'text') as String;
    if (rawKind == 'image') {
      kind = ChatMessageKind.image;
    } else if (rawKind == 'attachment') {
      kind = ChatMessageKind.attachment;
    } else if (rawKind == 'poll') {
      kind = ChatMessageKind.poll;
    }
    return ChatMessage(
      id: (json['id'] ?? 0) as int,
      username: (json['username'] ?? '') as String,
      displayName: (json['display_name'] ?? json['username'] ?? '') as String,
      content: (json['content'] ?? '') as String,
      kind: kind,
      imageUrl: media((json['image_url'] ?? '') as String),
      videoUrl: media((json['video_url'] ?? '') as String),
      likeCount: (json['like_count'] ?? 0) as int,
      likedByMe: (json['liked_by_me'] ?? false) as bool,
      pinned: (json['pinned'] ?? false) as bool,
      createdAt: DateTime.tryParse((json['created_at_iso'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}

class PollOption {
  final int id;
  final String text;
  final int votes;
  final bool votedByMe;

  PollOption({
    required this.id,
    required this.text,
    required this.votes,
    required this.votedByMe,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: (json['id'] ?? 0) as int,
      text: (json['text'] ?? '') as String,
      votes: (json['votes'] ?? 0) as int,
      votedByMe: (json['voted_by_me'] ?? false) as bool,
    );
  }
}

class ChatPoll {
  final int id;
  final String question;
  final List<PollOption> options;

  ChatPoll({required this.id, required this.question, required this.options});

  int get totalVotes => options.fold<int>(0, (sum, o) => sum + o.votes);

  factory ChatPoll.fromJson(Map<String, dynamic> json) {
    return ChatPoll(
      id: (json['id'] ?? 0) as int,
      question: (json['question'] ?? '') as String,
      options: [
        for (final option in (json['options'] as List? ?? []))
          PollOption.fromJson(option as Map<String, dynamic>),
      ],
    );
  }
}

class ChatRoom {
  final int id;
  final String name;
  final String privacy;
  final int membersCount;
  final int onlineCount;
  final bool official;
  final bool isMember;
  final bool pending;

  /// Messages room kholne par load hote hain; loaded flag se pata chalta hai
  /// ki first fetch ho chuka hai (reload par dubara spinner na dikhe).
  bool loaded;
  final List<ChatMessage> messages;
  ChatPoll? activePoll;

  ChatRoom({
    required this.id,
    required this.name,
    required this.privacy,
    required this.membersCount,
    required this.onlineCount,
    required this.official,
    required this.isMember,
    required this.pending,
    this.loaded = false,
    List<ChatMessage>? messages,
    this.activePoll,
  }) : messages = messages ?? [];

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: (json['id'] ?? 0) as int,
      name: (json['name'] ?? '') as String,
      privacy: (json['privacy'] ?? 'public') as String,
      membersCount: (json['members_count'] ?? 0) as int,
      onlineCount: (json['online_count'] ?? 0) as int,
      official: (json['official'] ?? false) as bool,
      isMember: (json['is_member'] ?? false) as bool,
      pending: (json['pending'] ?? false) as bool,
    );
  }
}

// ---------------------------------------------------------------------
// Printout (myapp.PrintOrder + vendor pricing)
// ---------------------------------------------------------------------

class PrintVendor {
  final int id;
  final String businessName;
  final String phone;
  final double bwPricePerPage;
  final double colorPricePerPage;

  PrintVendor({
    required this.id,
    required this.businessName,
    required this.phone,
    required this.bwPricePerPage,
    required this.colorPricePerPage,
  });

  factory PrintVendor.fromJson(Map<String, dynamic> json) {
    return PrintVendor(
      id: (json['id'] ?? 0) as int,
      businessName: (json['business_name'] ?? '') as String,
      phone: (json['phone'] ?? '') as String,
      bwPricePerPage: ((json['bw_price_per_page'] ?? 0) as num).toDouble(),
      colorPricePerPage: ((json['color_price_per_page'] ?? 0) as num).toDouble(),
    );
  }
}

enum PrintOrderStatus { pending, accepted, rejected, printing, ready, completed }

PrintOrderStatus parsePrintStatus(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'accepted':
      return PrintOrderStatus.accepted;
    case 'rejected':
      return PrintOrderStatus.rejected;
    case 'printing':
      return PrintOrderStatus.printing;
    case 'ready':
      return PrintOrderStatus.ready;
    case 'completed':
      return PrintOrderStatus.completed;
    default:
      return PrintOrderStatus.pending;
  }
}

extension PrintOrderStatusX on PrintOrderStatus {
  String get label {
    switch (this) {
      case PrintOrderStatus.pending:
        return 'Pending';
      case PrintOrderStatus.accepted:
        return 'Accepted';
      case PrintOrderStatus.rejected:
        return 'Rejected';
      case PrintOrderStatus.printing:
        return 'Printing';
      case PrintOrderStatus.ready:
        return 'Ready';
      case PrintOrderStatus.completed:
        return 'Completed';
    }
  }
}

class PrintOrder {
  final int id;
  final int vendorId;
  final String vendorName;
  final String fileName;
  final String fileUrl;
  final int copies;
  final String printSide;
  final int bwPages;
  final int colorPages;
  final String bwPageRanges;
  final String colorPageRanges;
  final String note;
  final PrintOrderStatus status;
  final double totalPrice;
  final DateTime createdAt;

  PrintOrder({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.fileName,
    required this.fileUrl,
    required this.copies,
    required this.printSide,
    required this.bwPages,
    required this.colorPages,
    required this.bwPageRanges,
    required this.colorPageRanges,
    required this.note,
    required this.status,
    required this.totalPrice,
    required this.createdAt,
  });

  factory PrintOrder.fromJson(Map<String, dynamic> json, String Function(String) media) {
    return PrintOrder(
      id: (json['id'] ?? 0) as int,
      vendorId: (json['vendor_id'] ?? 0) as int,
      vendorName: (json['vendor_name'] ?? '') as String,
      fileName: (json['file_name'] ?? '') as String,
      fileUrl: media((json['file_url'] ?? '') as String),
      copies: (json['copies'] ?? 1) as int,
      printSide: (json['print_side'] ?? 'single') as String,
      bwPages: (json['bw_pages'] ?? 0) as int,
      colorPages: (json['color_pages'] ?? 0) as int,
      bwPageRanges: (json['bw_page_ranges'] ?? '') as String,
      colorPageRanges: (json['color_page_ranges'] ?? '') as String,
      note: (json['notes'] ?? '') as String,
      status: parsePrintStatus(json['status'] as String?),
      totalPrice: ((json['total_price'] ?? 0) as num).toDouble(),
      createdAt: DateTime.tryParse((json['created_at_iso'] ?? '') as String) ??
          DateTime.now(),
    );
  }
}
