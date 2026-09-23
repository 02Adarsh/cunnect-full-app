/// ⭐ v75: which portal the user is looking at RIGHT NOW.
///
/// One phone can be logged in as a student AND as a ride partner (and as
/// a food/print vendor). Every push therefore says which portal it belongs
/// to (`data['portal']` = student / rider / vendor) and the app only plays
/// the ring and raises in-app popups when the portal matches what is on
/// screen. Tray notifications still arrive for everything — those are
/// supposed to work with the screen off.
enum AppPortal { student, vendor, rider, auto }

class ActivePortal {
  ActivePortal._();

  static AppPortal current = AppPortal.student;

  static void set(AppPortal p) => current = p;

  static bool get isStudent => current == AppPortal.student;
  static bool get isVendor => current == AppPortal.vendor;
  static bool get isRider => current == AppPortal.rider;
  static bool get isAuto => current == AppPortal.auto;

  /// Does a push tagged [pushPortal] belong to the portal on screen?
  ///
  /// Unknown/empty tags are treated as student pushes (the default) so
  /// older pushes keep behaving the way they always did.
  static bool accepts(String? pushPortal) {
    final p = (pushPortal ?? '').trim().toLowerCase();
    if (p.isEmpty) return isStudent;
    if (p == 'rider') return isRider;
    // ⭐ v81: the AUTO portal only reacts to auto calls — a car console
    // never rings for one and the auto portal never rings for a booking.
    if (p == 'auto') return isAuto;
    if (p == 'vendor') return isVendor;
    return isStudent;
  }
}
