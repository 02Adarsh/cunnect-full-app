# CUnnect — Notification Fix (Student vs Vendor alag) + Footer Toast Removed

Date: 2026-09-15

## Problem
1. Student aur vendor dono ke notification section mein **same notifications** dikh rahe the
   (kyunki backend mein sab notifications ek hi list mein the, koi audience/role separation nahi tha).
2. Student dashboard ke footer/neeche jo **green toast** aata tha
   ("Order accepted: ORD-xx is now accepted" type) — usko hatana tha.

---

## Backend changes (`cunnect-backend` — Render wala repo)

### 1. `food/models.py`
- `Notification` model mein naya field:
  ```python
  audience = models.CharField(max_length=10,
      choices=[("student","Student"),("vendor","Vendor")],
      default="student", db_index=True)
  ```

### 2. `food/migrations/0020_notification_audience.py` (NAYA FILE)
- `audience` field add karta hai.
- **Purane data ko bhi fix karta hai**: jinke title vendor-wale hain
  ("New food order received", "New order received", "Order pending - alert",
  "Delivery started") unhe `audience="vendor"` mark kar deta hai —
  taaki purane vendor notifications student section se hat jaayein.
- Render pe deploy ke baad `python manage.py migrate` chalna zaroori hai
  (Render build command mein migrate already hai to auto ho jayega).

### 3. `api_app/views.py`
- `food_notifications` — ab `?audience=student` / `?audience=vendor` query param
  ke hisaab se filter karta hai (default: student). `unread_count` bhi usi audience ka.
- `food_notifications_read` — ab sirf usi audience ke notifications read mark karta hai
  (body/query mein `audience` bhejo).
- Naya helper `_notify_vendor()` — vendor ke liye DB row (`audience="vendor"`) + FCM push.
- Vendor push wali jagah ab `_notify_vendor` use hota hai (pehle sirf push jaata tha, DB row student
  ke naam se nahi banta tha ya mix hota tha):
  - Order place hone par → "New order received" (vendor list mein)
  - Vendor action confirm → "Order accepted/preparing/ready marked" (vendor list mein)
  - "Delivery started" (vendor list mein)
- Student ko jaane wale sab `_notify()` calls ab explicitly `audience="student"`.

### 4. `food/views.py` (website side)
- Order place par vendor wala `Notification.objects.create(...)` ab `audience="vendor"`.
- `notifications_page` aur `notifications_api` ab `?audience=` filter respect karte hain.

### 5. Templates (website)
- `food_home.html` → bell link + API call mein `?audience=student`
- `vendor_dashboard.html` → bell link + API call mein `?audience=vendor`

---

## App changes (`cunnect-full-app` — Flutter)

### 1. `lib/services/app_store.dart`
- Alag lists: `_notifications` (student) + `_vendorNotifications` (vendor),
  alag unread counts.
- `loadNotifications()` → `?audience=student` + student token.
- **Naya** `loadVendorNotifications()` → `?audience=vendor` + vendor token.
- `notificationsFor(userId)` / `unreadCountFor(userId)` ab vendorUserId pe vendor list dete hain.
- `markAllRead(userId)` ab sahi token + audience ke saath sirf apna section clear karta hai.
- `addLocalNotification` — "New order" wale local alerts vendor list mein jaate hain.

### 2. `lib/screens/customer/notifications_screen.dart`
- Naya param `forVendor` — vendor se khulne par vendor notifications load/show/read.
- Subtitle bhi context ke hisaab se badla ("New orders and updates for your kitchen.").

### 3. `lib/screens/vendor/vendor_dashboard_screen.dart`
- Bell ab `NotificationsScreen(forVendor: true)` kholta hai.
- 15-sec poll mein `loadVendorNotifications()` bhi add — badge count live rahega.

### 4. `lib/screens/dashboard/student_dashboard_screen.dart`
- ⭐ Footer wala **green toast (Order accepted waghera) REMOVE** kar diya
  (`_maybeNotifToast` + uska call + `_shownNotif` set hata diye).
- Notification polling waise hi chal rahi hai — bell badge ab bhi update hota hai,
  bas neeche wala popup nahi aayega.

---

## Deploy steps
1. **Backend**: changes commit karke Render pe push karo. Migrate zaroor chale
   (`python manage.py migrate`).
   > Note: backend pehle deploy karo — purani app v38 `?audience=` nahi bhejti,
   > to default `student` milega = purana behaviour, kuch nahi tootega.
2. **App**: Flutter app build karke naya release (v39) upload karo —
   auto-update se sab users ko mil jayega.

## Test result (local)
- Student API (`?audience=student`) → sirf student notifications ✔
- Vendor API (`?audience=vendor`) → sirf vendor notifications ✔
- Vendor "mark all read" karne par student unread count untouched ✔

Patch files: `backend_changes.patch`, `app_changes.patch`
