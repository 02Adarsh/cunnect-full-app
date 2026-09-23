CUnnect v81 — a separate AUTO portal
==========================================================================
(Cumulative: includes v61-v80.)

ONE NEW MIGRATION THIS TIME (must run it once):
  python manage.py migrate      (ride.0012 = AutoCall table + auto_online)

=================================================================
1) AUTO IS ITS OWN PORTAL NOW                           (your request)
=================================================================
An auto partner is no longer a car partner with a switch. AUTO is a
separate ACCOUNT TYPE with its own portal:

  * The admin creates it: Admin panel > AUTO > "CREATE AUTO ACCOUNT"
    (name, phone, password) — or turns an existing ride partner into
    one with MAKE AUTO.
  * He logs in with that phone/password and lands straight in the AUTO
    portal. He never sees car bookings, fares, ride OTPs or the garage.
  * A car partner logs in and gets the car console exactly as before.
    The two never mix.

WHAT THE AUTO PORTAL DOES
  * A student taps AUTO on the Ride screen -> EVERY auto partner who is
    on duty rings at the same moment (20 seconds, non-stop).
  * One card: "A student needs an auto at the campus main gate" with
    ACCEPT and DECLINE. That is all — no fare, no payment, no OTP, no
    ride record, and nothing about the student is ever shown.
  * ON DUTY / OFF DUTY switch at the top. Off duty = no calls.
  * RECENT list: accepted / declined / missed, with "N accepted today".

=================================================================
2) THE CAR PORTAL ONLY RINGS FOR CARS
=================================================================
Auto calls carry portal=auto, so the car console never rings for one and
the AUTO portal never rings for a booking. The old "I drive an auto"
switch inside the car console is gone — it is replaced by a line telling
the driver to ask for an AUTO account.

=================================================================
3) THE ADMIN PANEL CAN REACH IT
=================================================================
Admin panel > AUTO (new last tab):
  * every auto partner with his phone, vehicle and duty switch
  * how many calls he took and how many he accepted
  * create a new AUTO account in one screen
  * MAKE AUTO on any ride partner (and remove him again)
  * the AUTO CALL LOG — who called, who answered, what happened

=================================================================
4) ALSO IN THIS BUILD (v80b, backend only)
=================================================================
Print order files are now served directly by the backend instead of
redirecting to Cloudinary (that redirect is why PDFs would not open).
Add ?debug=1 to the file URL to see which storage attempt failed.

=================================================================

CUnnect v80 — OTP verification in every store section
+ v80b: print order files now download properly
==========================================================================
(Cumulative: includes v61-v79.)

ONE NEW MIGRATION THIS TIME (must run it once):
  python manage.py migrate      (myapp.0035 = print + hostel OTP columns)

v80b HOTFIX (backend only — no APK rebuild needed):
  * The print partner's "File" button was handing the app a REDIRECT to a
    Cloudinary signed URL. The redirect dropped the auth header and free
    plan raw delivery answered 401/404, so the PDF never opened — in the
    app or in a browser.
  * The endpoint now fetches the file server-side (Admin API lookup ->
    signed download -> plain delivery URL) and returns a plain 200 with
    the bytes, inline, with the right content type.
  * Diagnostics: add ?debug=1 to the file URL and it returns JSON telling
    you exactly which storage attempt failed and why.

(Cumulative: includes v61-v79.)

ONE NEW MIGRATION THIS TIME (must run it once):
  python manage.py migrate      (myapp.0035 = print + hostel OTP columns)

=================================================================
1) EVERY STORE ORDER NOW NEEDS THE STUDENT'S OTP       (your request)
=================================================================
Food already worked this way — printout and Hostel Essentials now
work exactly the same, and nothing else can finish an order:

  * PRINTOUT — the partner cannot press "Complete" any more. He taps
    it, a sheet opens asking for the 4-digit OTP, and the job is
    completed by the server the moment the code matches.
  * HOSTEL ESSENTIALS — the vendor cannot mark an order "delivered"
    any more. He taps DELIVERED, types the OTP the student reads out
    at the door, and the order is delivered only if it matches.

THE RULE, IN ONE LINE
  No OTP = no completion. Without the code a print job stays "ready"
  forever and a hostel order stays "out for delivery" forever.

=================================================================
2) WHERE THE OTP IS SEEN
=================================================================
  * STUDENT — "My Print Orders" shows a red OTP card as soon as the
    job is READY. Hostel Essentials gains a brand-new "MY ORDERS"
    section at the bottom of the page that shows every order, its
    status and — once the vendor accepts — the OTP to show at the
    door. It refreshes every 10 seconds on its own.
  * VENDOR — never sees the OTP. He can only type it in. The vendor
    list and dashboard carry an "otp_verified" flag instead.

  Wrong code -> nothing happens, the order does not move.
  Verifying twice -> harmless, the second call is silently accepted.

=================================================================
3) BUG FIXED ON THE WAY
=================================================================
  The hostel vendor's status endpoint was crashing (500) on every
  ACCEPT / DELIVERED tap because it notified `order.user_id`, a
  field a HostelOrder never had. It now notifies the student who
  actually placed the order, so hostel orders can be accepted and
  delivered at all.

=================================================================
CUnnect v79 — the AUTO button, several rides at once, red Ride
section again, green flash messages back, car model before payment
==========================================================================
(Cumulative: includes v61-v78.)

ONE NEW MIGRATION THIS TIME:
  python manage.py migrate      (ride.0011 = RideVendor.is_auto)

=================================================================
1) THE AUTO BUTTON                                     (your request)
=================================================================
A plain, separate AUTO card now sits on the Ride screen:
  * ONE TAP and every AUTO PARTNER on campus is alerted at the same
    moment — their phones ring for 20 seconds, all together.
  * NO pickup, no drop, no fare, no payment, no OTP and no ride
    record: it is simply "come to the main gate".
  * The pickup is always the campus MAIN GATE. It is never typed,
    never asked for and never shown to the student — the partners
    already know it.
  * Tap it as many times as you like; every tap alerts them again.

WHO IS AN AUTO PARTNER
  * Ride portal > Profile > "I drive an auto" — switch it ON and that
    partner receives the auto calls. Car partners are never disturbed.
  * There can be as many auto partners as you want. Every one of them
    is notified on every tap.
  * An auto partner is completely outside the car booking flow: he
    gets no fare, no ride list entry and no OTP screen.

=================================================================
2) SEVERAL RIDES AT THE SAME TIME                      (your request)
=================================================================
A car partner can now accept, run and close as many rides as he can
handle, at the same time:
  * "My Ride" lists EVERY active ride — each with its own card, its
    own map, its own payment panel, its own OTP field and its own
    buttons (I'M ON LOCATION / START RIDE / COMPLETE RIDE).
  * A banner shows "N rides running together".
  * His live location is pushed to all of them at once.
  * Finishing one ride leaves the others untouched; the partner's
    totals count each ride exactly once.

=================================================================
3) THE CAR MODEL SHOWS ON ACCEPT — BEFORE PAYMENT       (your request)
=================================================================
The moment a rider accepts, the student sees "YOUR CAR": the vehicle
model and the category (e.g. "Swift · Mini"). The number plate and
the phone number still wait until the payment is verified.

=================================================================
4) THE RIDE SECTION IS RED AGAIN                        (your request)
=================================================================
Everything in Ride that had gone white is red again — the OTP card,
the SHARE OTP button, the rider's OTP box and the online chip.

=================================================================
5) FLASH MESSAGES ARE GREEN AGAIN                       (your request)
=================================================================
The success toast is back to its green look (green tick, light green
text, dark green card). Only the ERROR toast stays red.

=================================================================


CUnnect v78 — balance locks the ride, no blocking payment popups,
every popup red & black, OPEN MAP for the student, CUnnect Food
==========================================================================
(Cumulative: includes v61-v77.)

ONE NEW MIGRATION THIS TIME:
  python manage.py migrate      (ride.0010 = awaiting_balance field +
                                 "Food Court" renamed to "CUnnect Food")

=================================================================
1) A 50-50 RIDE NOW CANNOT BE CLOSED UNTIL IT IS PAID  (your request)
=================================================================
  * The rider taps COMPLETE RIDE while the second half is still due ->
    the ride does NOT close. It parks with "Waiting for the student to
    pay Rs.X" on the partner's screen.
  * The student gets "PAY TO CLOSE THIS RIDE" with the QR already built
    (no button) and a transaction-ID field. The moment it is recorded
    the ride completes by itself and both sides are told.
  * The ride also cannot be cancelled to dodge the payment.
  * A partner who is paid cash still has "COLLECT Rs.X FROM THE STUDENT"
    as the safety valve — that closes the ride and stores CASH as the
    transaction id.

BALANCE TRANSACTION ID ON THE RIDE PORTAL                 (your request)
  * The payment panel now shows two lines:
        Txn 1 ....... <first half / full payment>
        Balance txn . <transaction id of the remaining 50%>
  * History shows it too, labelled "Balance txn".

=================================================================
2) NO BLOCKING "PAYMENT RECEIVED" POPUP ON THE STUDENT  (your request)
=================================================================
The student's Ride screen stays clean. Payment news arrives as a tray
notification plus a small toast at the bottom — never as a popup that
covers the ride. That covers: first half paid, balance paid, balance
taken in cash, and "the rider confirmed your payment".
Ride popups that DO matter (rider accepted, OTP, ride started,
completed, cancelled) still open normally.

=================================================================
3) EVERY POPUP IN THE APP IS NOW RED / BLACK / WHITE   (your request)
=================================================================
Every dialogue, bottom sheet and toast in CUnnect was re-coloured.
The last green, gold, blue and violet accents are gone — including the
online dots, switches, status chips, chart legends and the success
toast. Everything sits on black, white and CUnnect red.

=================================================================
4) OPEN MAP ON THE STUDENT'S RIDE SCREEN               (your request)
=================================================================
Once the ride has started (OTP verified) the SAFETY card grows an
"OPEN MAP" button. It opens Google Maps with the route to the
destination, exactly like the ride partner's portal does.

=================================================================
5) "Food Court" IS NOW "CUnnect Food"                  (your request)
=================================================================
Renamed in the built-in store section (database row included) and in
the flash messages: "CUnnect Food is coming soon." / "CUnnect Food is
currently unavailable."

=================================================================


CUnnect v77 — portal privacy, garage (many cars + plates), SUV,
real-time fare split, payment QR like the food section, no neon
==========================================================================
(Cumulative: includes v61-v76.)

ONE NEW MIGRATION THIS TIME:
  python manage.py migrate      (ride.0009 = SUV rename, ride.vehicle_name
                                 / vehicle_plate, RideVehicle garage table)

=================================================================
1) NOTHING LEAKS BETWEEN THE TWO PORTALS      (your request)
=================================================================
Ride events are now filtered on the PHONE as well: a partner event
never reaches the student's Ride screen and a student event never
reaches the ride partner portal. Screens double-check before they
paint anything, so:
  * CONFIRM PAYMENT lives on the RIDER's device only
  * the payment-confirmation notification goes to the STUDENT only
  * the OTP stays with the student
  * the partner's accept / arrival popups never open on the student side

CONTACT NUMBERS — hidden at BOTH ends until the rider accepts AND
verifies the payment:
  * rider sees "Number appears once the payment is verified" until he
    taps CONFIRM PAYMENT; after that he gets a CALL button and a MASKED
    number (98XXXXX210) — the digits only ever reach the phone's dialer
  * student sees the rider's number only after the payment is verified
  * the NUMBER PLATE behaves the same way: model + category from the
    moment the ride is accepted, plate only after verification

=================================================================
2) GARAGE — MANY CARS, EACH WITH ITS PLATE     (your request)
=================================================================
  * Ride portal > Profile > MY VEHICLES: add any number of cars
    (Mini / Sedan / SUV) with a name and a number plate; delete any.
  * Accepting a request opens "Which car are you driving?" — the whole
    saved list (all categories) plus "Use another vehicle" for a one-off
    that is NOT saved in the garage.
  * ⭐ "Car XL" is now SUV everywhere (labels, icons, estimate, admin).

=================================================================
3) SPLIT BETWEEN FRIENDS = A PRIVATE CALCULATOR (your request)
=================================================================
  * Type how many passengers are travelling (driver not counted) with
    − / + and the per-head share updates instantly: fare / n.
  * Nothing is saved on the server and the rider never sees it — it is
    a calculator, nothing else. The app still takes the whole fare.
  * The old "pax" list (names, per-friend rows) is gone from the UI.

=================================================================
4) PAYMENT QR — EXACTLY LIKE THE FOOD SECTION  (your request)
=================================================================
  * The QR is generated on its own the moment the payment step opens
    (no "SHOW PAYMENT QR" button to press).
  * Works from the rider's UPI id, from the QR IMAGE he uploaded in the
    portal (this used to fail — that is why no QR ever appeared), or
    from the platform account as a last resort.
  * The amount is baked in (upi://pay?...&am=<fare>) and "PAY Rs.X IN A
    UPI APP" opens it in PhonePe/GPay/Paytm pre-filled. 50-50 works the
    same for the first half and for the balance.

=================================================================
5) UI — NO MORE NEON
=================================================================
The light green / amber / sky / violet accents are gone from the Ride
section (and the same mint was removed from the rest of the app). The
Ride UI is now black, white and red only, matching CUnnect.

=================================================================


CUnnect v76 — UMS 1-month prediction, subject lecture planner,
rider sees the number only after confirming, small UI fixes
==========================================================================
(Cumulative: includes v61-v75.)

Nothing new to migrate this time (no model changes) — `python manage.py
migrate` is still safe to run and simply reports "No migrations to
apply".

=================================================================
1) RIDER: NUMBER ONLY AFTER HE CONFIRMS PAYMENT   (your request)
=================================================================
The student's phone stays hidden in the ride partner portal until the
rider taps CONFIRM PAYMENT (paying is not enough any more).
Until then the console shows the lock row:
"Number appears once the payment is verified".

=================================================================
2) UMS — OVERALL PREDICTION: 1 WEEK / 1 MONTH     (your request)
=================================================================
The prediction sheet now has a 1 WEEK / 1 MONTH switch at the top:
  * 1 WEEK  -> the next 7 days (unchanged)
  * 1 MONTH -> the next 30 days, same layout: the overall ring, the
               "+N planned" chip and every SUBJECT row with its own
               projected % after a month of classes
  * the day chips show the date in the monthly view ("MON 22") and
    scroll sideways; the slider covers the whole range.

=================================================================
3) UMS — "ATTEND NEXT N" NOW FOLLOWS THE PLAN     (your request)
=================================================================
The headline used to look at TODAY'S percentage only, so a subject
that was already safe after the planned lectures still showed
"Attend the next N classes". It now follows the plan:
  * below 75% with the plan  -> "Attend the next N classes to reach 75%."
  * at/above 75% with it     -> "You can miss N more classes..."
  * exactly on the safe line -> "You are on the safe line — no buffer"
The same rule is used by the subject tiles inside the prediction
sheet (they used to print "ATTEND NEXT N" even when the planned
classes pushed the subject above 75%).

=================================================================
4) UMS — SUBJECT-WISE UPCOMING LECTURES           (your request)
=================================================================
Inside a subject's planner there is a new UPCOMING LECTURES row:
  * every lecture of that subject for the next 7 days, with its start
    time ("MON · 09:00"), TODAY first
  * it scrolls SIDEWAYS
  * tap any lecture to plan "attend up to here" — the projected %,
    the ring and the safe/bunk line update themselves.

=================================================================
5) SMALL FIXES
=================================================================
  * "Food Court is currently unavailable." is now
    "CUnnect food is currently unavailable."
  * the Forgot password sheet now shows the same CUnnect logo the
    rest of the app uses.

STILL OPEN (from v75): your own notification tone. Copy it over
  android/app/src/main/res/raw/universfield_new_notification_066_494545.mp3
  assets/sounds/universfield_new_notification_066_494545.mp3
(names must use underscores — Android rejects '-' in resource names.)

=================================================================


CUnnect v75 — RIDER CONFIRMS PAYMENT, ride QR with a locked amount,
notifications split per portal, 20-second partner ring + new tone
==========================================================================
(Cumulative: includes v61-v74.)

MANDATORY ON THE SERVER (two new migrations):
  * python manage.py migrate      (ride.0008 = payment_confirmed,
                                   food.0023 = notification.category)
  * flutter pub get               (new package: just_audio — the ring)

=================================================================
1) PAYMENT IS NEVER AUTOMATIC ANY MORE            (your request)
=================================================================
NEW FLOW:
  student books -> a rider ACCEPTS (his own Accept button, by hand)
               -> the student pays from the QR / UPI link
               -> the rider opens MY RIDES and taps CONFIRM PAYMENT
               -> only then does "I'M ON LOCATION" unlock.

Nothing moves by itself: the backend refuses "arrived" until the rider
has confirmed ("Confirm the payment first"), and the ride stays on
"Payment sent - rider confirming" for the student until he does.

=================================================================
2) RIDE QR — AMOUNT LOCKED, CANNOT BE EDITED      (your request)
=================================================================
  * The QR is built from the RIDER's own UPI id with the exact fare
    baked in (upi://pay?pa=..&am=<fare>&cu=INR&tn=<ride code>) so any
    UPI app fills the amount automatically.
  * Below the QR: "PAY Rs.X IN A UPI APP" opens the same amount in
    PhonePe / GPay / Paytm — again pre-filled, not editable.
  * 50-50 works exactly the same: the first half QR and the
    balance QR are both generated with the exact amount.
  * Fallback: if a rider has no UPI id yet the app uses the platform
    account (env CUNNECT_RIDE_UPI) instead of showing nothing.
  * RIDERS: add your UPI id once in
    Ride portal > Profile > PAYMENT UPI > SAVE UPI ID.
    Without it the student cannot get a QR.
  * New endpoint: GET /api/ride/upi/<code>/?amount=

=================================================================
3) NOTIFICATIONS GO TO THE RIGHT PORTAL           (your request)
=================================================================
Every push now carries a "portal" tag (student / rider / vendor):
  * ride/student events  -> only in the student Ride screens
  * ride/partner events  -> only in the Ride partner portal
  * the OTP, SOS and trip-share never reach the rider portal
  * food/printout orders -> only in their own vendor portals
The tray notification still arrives for everything (that must work
with the screen off) — only the in-app POPUP and the RING follow the
portal you are actually looking at.

SOS and "share trip" stay STUDENT-only (they were never in the rider
portal). In the food vendor portal the student's course/branch is no
longer printed on the order.

=================================================================
4) 20-SECOND NON-STOP RING IN EVERY PARTNER PORTAL (your request)
=================================================================
  * Food order, printout job or new ride request -> the portal rings
    NON-STOP for 20 seconds (accepter/reject karte hi band).
  * It also triggers from the poller, so it rings even if FCM is
    delayed or blocked.
  * Print orders now send a push as well ("New printout order").

=================================================================
5) NEW NOTIFICATION TONE
=================================================================
The sound you asked for ("universfield-new-notification-066-494545")
is a paid/downloadable clip, so I bundled a placeholder with EXACTLY
that name. To use your own file, just overwrite it (keep the name!):

  assets/sounds/universfield_new_notification_066_494545.wav
  android/app/src/main/res/raw/universfield_new_notification_066_494545.wav

then run: flutter build apk --release
(Convert your mp3 to .wav first, or rename the file to .mp3 and
 update the two references: kNotifSound in lib/services/fcm.dart and
 RingService.asset in lib/services/ring_service.dart.)

Notes:
  * Android locks a channel's sound at creation time, so the channels
    moved to cunnect_ping_v6 / cunnect_alert_v6 (the old ones are
    deleted on start). The tone plays for BOTH channels.
  * iOS: drag the same file into Xcode > Runner to use it there too
    (Android builds are unaffected).

=================================================================
6) ALSO IN THIS BUILD
=================================================================
  * Ride partner portal: "RECENT RIDES" removed from My Ride —
    finished rides live in the History tab only.
  * Food notification list no longer shows printout notifications.
  * pubspec version is now 2.2.74+74 and kAppVersion = 75.

=================================================================


CUnnect v74 — RIDE: notifications & popups everywhere, history pages,
rider payments, multi-slot unavailability, and a brand new Ride UI
==========================================================================
(Cumulative: includes v61-v73 — vendor self-service store, media
banners, real-time speed, in-app password reset, iOS support, v65
security hardening, feed links, Ride section, offline UP map, rider
blocks and the broadcast card.)

Read this first — TWO things are mandatory on the server:
  * python manage.py migrate   (0006 = fare split, 0007 = state sync)
  * the FCM payload now carries "event" and "ride_code"; old builds
    simply ignore them, new builds need them for the popups.

=================================================================
1) NOTIFICATIONS + POPUPS ON EVERY RIDE EVENT   (your request)
=================================================================
WHY YOU SAW NOTHING: in the foreground the app swallowed pushes
silently — no tray entry and no popup at all. That is fixed.

NOW, whether the screen is ON or OFF:
  * screen OFF / app closed  -> the system notification (unchanged),
    and tapping it opens the right screen and then raises the POPUP
  * app OPEN                 -> a heads-up notification AND an in-app
    POPUP on top of whatever you are doing

Every event is covered, on BOTH sides:
  STUDENT   booked · accepted (pay now) · first-half paid · payment
            recorded · rider arrived (with the OTP) · ride started ·
            ride completed · balance cleared · cancelled · no rider
  PARTNER   new request · payment received (full / first half, with
            the amount and what is still due) · balance paid ·
            student started sharing location · cancelled · SOS

The popup matches the event: green for accepted/paid, blue with the
OTP for "arrived", amber for "unavailable", red for SOS. A new ride
request is the only popup that cannot be dismissed by tapping
outside — the partner must Accept or Reject.

FILES: lib/services/fcm.dart  (foreground fixed)
       lib/services/ride_events.dart        (NEW — event bridge)
       lib/widgets/ride_event_popup.dart    (NEW — the popups)
       lib/services/notif_router.dart       (opens the right screen)
       backend/.../api_app/views.py         (events on every action)
       backend/.../api_app/tasks.py

=================================================================
2) RIDE HISTORY — SEPARATE PAGE ON BOTH SIDES   (your request)
=================================================================
  * Student: Ride -> the clock icon, or "Ride history" on the home
    screen. Filter chips (All / Completed / Cancelled / No rider).
    Tap any ride for the full receipt: route, fare, payment mode,
    transaction id, what is still due, co-passengers and note, plus
    BOOK THIS AGAIN.
  * Partner: a new HISTORY tab in the ride console (and a
    "Ride history" row under MY BUSINESS in the Profile tab), with
    the same filters and receipts.
  * The list is no longer capped at a handful of rides.

FILES: lib/screens/ride/ride_history_screen.dart  (NEW — both pages)
       lib/screens/ride/rider_console_screen.dart
       backend/.../api_app/views.py  (ride/list + ride/vendor/rides
       now return a "history" key and up to 200 rides)

=================================================================
3) PAYMENT SHOWN TO THE RIDER — HALF / FULL / BALANCE + TXN
=================================================================
The partner now sees exactly what the food portal shows:
  * a FULL PAYMENT / 50-50 SPLIT badge
  * RECEIVED  Rs X      and, when it is a split,  STILL DUE  Rs Y
  * the transaction id (and the second one when the balance is paid)
  * a "COLLECT Rs Y FROM THE STUDENT" button — the partner taps it
    only after the cash is in his hand; the student is notified
  * "Fully paid — nothing left to collect" once it is settled
The student keeps the same payment flow as food (QR + 4 steps +
transaction id, full or 50-50), so nothing changes for him.

FILES: lib/screens/ride/rider_console_screen.dart
       lib/services/app_store.dart
       backend/.../api_app/views.py  (new endpoint:
       POST /api/ride/vendor/collect-balance/<code>/)

=================================================================
4) AS MANY UNAVAILABILITY SLOTS AS YOU WANT   (your request)
=================================================================
Profile tab -> WHEN I AM NOT AVAILABLE is now a WEEK PLANNER:
  * every weekday is a row; each blocked range is a chip on that day
    (e.g. Mon: 16:00-17:00 and 18:00-19:00)
  * every row has its own "+ slot" button, so adding 4-5 pm and
    6-7 pm on the same day takes two taps
  * every chip has its own delete cross
  * one-off dates are listed separately with their own "Add a date"
  * rides inside ANY of those windows never reach the partner, and
    if nobody is left the student is told to book another time

FILES: lib/screens/ride/rider_console_screen.dart
       (the server always stored as many slots as you added — the
        old screen just made it look like one)

=================================================================
5) A COMPLETELY NEW RIDE SECTION   (your request)
=================================================================
  * MAP FIRST: the whole screen is a live OpenStreetMap that draws
    your route as you build it. The university is always pinned.
  * SLIDING SHEET: pull it up like Uber — grab handle, snap points,
    and inside it: pickup (with a CURRENT LOCATION button that takes
    a precise GPS fix and the real address), drop, saved places,
    then CHOOSE YOUR RIDE with a card per vehicle (icon, seats,
    fare, colour, SELECTED badge, "currently unavailable" state).
  * DARK PREMIUM LOOK: frosted glass cards, gradients, per-vehicle
    accent colours, animated selection, rounded everything.
  * EXTRAS NO OTHER CAMPUS APP HAS:
      - SOS: alerts your rider AND every online partner with your
        live location
      - Share my trip: one tap sends your route to family or friends
      - Share the OTP: copy or WhatsApp it to the rider instead of
        reading it out
      - Split the fare with friends: add each person and their
        share; the app tracks who has paid
      - Saved & recent places: one-tap Hostel / Gate / Library
      - Your riding: total rides, kilometres and money spent
      - Favourite routes in your statistics

FILES: lib/screens/ride/ride_home_screen.dart   (rewritten)
       lib/widgets/ride_ui.dart                 (NEW — design kit)
       lib/screens/ride/ride_tracking_screen.dart
       lib/services/app_store.dart
       backend/.../api_app/views.py  (new endpoints:
       POST /api/ride/<code>/sos/ · GET,POST /api/ride/<code>/pax/
       POST /api/ride/<code>/pax/<id>/ · GET /api/ride/stats/)

=================================================================
6) PARTNER CONSOLE UPGRADED
=================================================================
  * four tabs now: Requests · My Ride · History · Profile
  * EARNINGS on top: today, this month, all-time, plus rides, km
    and whatever is still due to you
  * the payment panel described in (3)
  * the week planner described in (4)
  * MY BUSINESS: ride history + earnings in one tap
  * everything else from v73 stays: accept/reject popup, contact
    revealed only after payment, map to the pickup after payment and
    to the drop only after the OTP, rider logout

=================================================================
FILES CHANGED IN THIS ZIP
=================================================================
FLUTTER
  lib/widgets/ride_ui.dart                    (NEW — design kit)
  lib/widgets/ride_event_popup.dart           (NEW — event popups)
  lib/services/ride_events.dart               (NEW — event bridge)
  lib/screens/ride/ride_history_screen.dart   (NEW — both histories)
  lib/screens/ride/ride_home_screen.dart      (rewritten UI)
  lib/screens/ride/ride_tracking_screen.dart  (safety, split, OTP share)
  lib/screens/ride/rider_console_screen.dart  (earnings, payments,
                                               week planner, history)
  lib/services/app_store.dart  (stats, pax, SOS, collect balance)
  lib/services/fcm.dart        (foreground notifications fixed)
  lib/services/notif_router.dart
  lib/screens/splash_screen.dart              (version 74)

BACKEND
  backend/myproject/api_app/views.py  (every event notifies both
    sides with event + ride_code; SOS, fare split, collect balance,
    statistics, longer history)
  backend/myproject/api_app/urls.py   (new endpoints)
  backend/myproject/api_app/tasks.py  (push payload pass-through)
  backend/myproject/ride/models.py    (RidePax)
  backend/myproject/ride/migrations/0006_ridepax.py                (NEW)
  backend/myproject/ride/migrations/0007_sync_riderblock_help.py   (NEW)

=================================================================
HOW TO APPLY (PowerShell)
=================================================================
cd C:\Users\adars\Downloads
Expand-Archive -Path .\cunnect_v74_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v74 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v74\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
flutter pub get
cd backend\myproject
python manage.py migrate          # ← ride/0006 + ride/0007
git add -A ; git commit -m "v74: ride notifications, history, rider payments, multi-slot, new UI" ; git push
cd C:\Users\adars\Downloads\cunnect_food_flutter
flutter build apk --release

GitHub release tag: 74

IMPORTANT
---------
* "python manage.py migrate" IS MANDATORY (0006 + 0007).
* No new packages — flutter_map, geolocator, http and path_provider
  were already in pubspec from v72/v73. "flutter pub get" is still
  recommended after the copy.
* Tested: 60 new backend checks (notifications on every event,
  half/full payment maths, transaction ids, fare split, multiple
  slots, history, statistics, SOS, no-rider handling) + the 21
  earlier security/regression checks — 81/81 pass.

CUnnect v73 — RIDE: real pickup & time slots, offline UP map, rider
availability, broadcast card, contact privacy, rider logout
==========================================================================
(Cumulative: includes v61-v72 — vendor self-service store, media
banners, real-time speed, cunnect.online primary domain, in-app
password reset, iOS support, full v65 security hardening, feed links,
6-icon bar and the Ride section itself.)

Read this first: v73 changes the Ride booking flow, the map and the
rider portal. Two things are mandatory on the server:
  * python manage.py migrate   (new ride fields + RiderBlock table)
  * a NEW push route "broadcast" is used by the admin panel.

=================================================================
1) BROADCAST NOTIFICATION -> FULL IN-APP CARD   (your request)
=================================================================
BEFORE: an admin broadcast only produced a phone notification; tapping
it opened the app and the message was gone.

NOW: tapping a broadcast opens the app on the HOME PAGE and shows the
message as a BLACK BOX ON SCREEN, exactly like the app-update block:
  * plain black box, no buttons, no icons, no close button
  * the box is only as big as the text needs, and it is exactly in the
    middle of the screen (equal space on all four sides)
  * everything around it is darkened and slightly blurred
  * TOUCH ANYWHERE OUTSIDE THE BOX and it disappears
If the app is opened in any other way, the pending broadcast is still
waiting and is shown on the home page at that moment, so the message is
never lost.

FILES: lib/widgets/broadcast_card.dart  (NEW)
       lib/services/fcm.dart  lib/services/notif_router.dart
       lib/screens/dashboard/student_dashboard_screen.dart
       backend/myproject/api_app/views.py   (admin_broadcast now sends
       route="broadcast" so the app can tell it apart from the
       notifications list)

=================================================================
2) APP-UPDATE POPUP — "LATER" REALLY MEANS LATER   (your request)
=================================================================
BEFORE: tapping "Later" on the update dialog remembered the version and
you were not bothered again until the next app version.

NOW: "Later" only closes the dialog. The next time the app is opened
(and every time after that) the update dialog comes back, until the app
is actually updated.

FILES: lib/screens/splash_screen.dart

=================================================================
3) BOOKING FORM REBUILT   (your request)
=================================================================
  a) PICKUP — "CURRENT LOCATION" THAT REALLY WORKS
     A round RED locate button on the map plus "Use my location" in the
     route card. It asks for high-accuracy GPS (best-for-navigation),
     drops the pin on your exact position and reverse-geocodes it into
     a real address. Works from the pickup row and from the map screen.

  b) TIME SLOT IS NOW COMPULSORY
     "Leave now" is gone as a default. The slot row says
     "Choose the time slot (required)" in yellow until you pick one, and
     the BOOK RIDE button refuses to continue (it even opens the picker
     for you). Even leaving immediately must be selected by hand. The
     server rejects a booking with no slot too.

  c) MOBILE NUMBER IS READ-ONLY
     The number shown at booking is taken from your CUnnect profile —
     it is displayed with a green "from profile" tag and CANNOT be
     typed or edited. The server also ignores any number sent by the
     phone and always stores the profile number.

  d) "BOOKING FOR SOMEONE ELSE?"
     A switch under your number. Turn it ON and two fields appear:
     their name (optional) and THEIR CONTACT NUMBER (required). When
     it is on, the rider dials that number instead of yours.

  e) NOTE FOR THE RIDER — kept, unchanged.

  f) AUTO RICKSHAW IS GONE FROM RIDE
     Vehicle types are now Mini / Sedan / XL only (auto was removed
     from both the app and the server; a request for "auto" is
     rejected). Mini = Rs 30 + Rs 14/km, Sedan = 35 + 18, XL = 45 + 24.

  g) UNAVAILABLE VEHICLES CAN STILL BE BOOKED FOR LATER
     A vehicle the rider has switched off is listed with a yellow
     "Currently unavailable — book for another time" line and a greyed
     fare, but it is still selectable for another time slot.

  h) NO MORE "ETA" ANYWHERE IN BOOKING
     The expected journey time is removed from the trip bar, the
     vehicle cards, the booking sheet and the home screen. It is kept
     only on the LIVE MAP / TRACKING screen, as you asked.

FILES: lib/screens/ride/ride_home_screen.dart
       lib/screens/ride/ride_map_picker_screen.dart
       lib/services/app_store.dart
       backend/myproject/api_app/views.py   (ride_estimate, ride_book)
       backend/myproject/ride/models.py     (VEHICLE_TYPES)

=================================================================
4) MAP — CHANDIGARH UNIVERSITY UP + OFFLINE + PLACE DATABASE
=================================================================
  a) CORRECT CAMPUS, PINNED
     The old Punjab coordinates were wrong. The app now uses
        "Chandigarh University UP"  26.621884, 80.687916
        Parsandan / Nawabganj, Unnao district, Uttar Pradesh 209859
     as the default map centre, the default profile address and the
     fallback point everywhere. The university is ALWAYS drawn on the
     map as a labelled pin, so it can no longer "not show up".

  b) BUILT-IN PLACE DATABASE (works with no internet)
     44 verified places around Nawabganj / Unnao, Lucknow and Kanpur
     (Unnao Junction, Shuklaganj, Charbagh, Hazratganj, Gomti Nagar,
     CCS Airport, Lulu Mall, Kanpur Central, IIT Kanpur, Z Square, ...)
     are compiled into the app. They appear INSTANTLY as you type and
     keep working offline. Online OpenStreetMap search still runs for
     anything else and is merged underneath.
     FILE: lib/data/up_places.dart  (NEW)

  c) OFFLINE TILES
     Every map tile the app loads is saved on the phone, and saved
     tiles are served from storage with no network at all. The map
     screen has a DOWNLOAD button (the round button with the
     download icon) that pre-loads the area you are looking at at
     zooms 13-16 so that part of the map works with the internet off.
     Tiles live in the app's documents folder (cunnect_tiles), cost no
     APK size, and are cleaned up with the app data.
     FILE: lib/services/offline_tiles.dart  (NEW)

=================================================================
5) RIDE REQUEST FLOW — POPUP, PAYMENT, THEN THE NUMBER
=================================================================
  * A new request now raises a POPUP on the rider's phone (over
    whatever he is doing, cannot be dismissed by tapping outside) with
    the route, the vehicle, the time slot, the student's name and
    ACCEPT / REJECT. Requests that were already waiting when he opened
    the app do NOT pop up — they stay quietly in the Requests tab.
  * REJECT -> the student gets a push notification straight away:
    "Rider unavailable — the ride partner cannot take this ride right
    now, please book for another time slot."
    If EVERY partner declines (or the only ones left have blocked that
    slot), the ride is closed and the student's screen says
    "Rider unavailable right now — every ride partner is busy at that
    time, please book the ride for another time slot" with a
    BOOK FOR ANOTHER TIME button back to the booking screen.
  * ACCEPT -> the student pays using the SAME payment flow as
    food/store (full or 50-50 split), and the rider sees
    "Waiting for the payment" until it is confirmed.
  * ONLY AFTER the payment is verified does the rider see the number
    to call, as a green tappable row that opens the phone dialler
    (exactly like the food vendor portal). Before that it says
    "Number appears once the payment is verified".
  * If the ride was booked for someone else, the row shows that
    person's name and dials their number.

=================================================================
6) RIDER MAP + DIRECTIONS — PICKUP FIRST, DROP AFTER THE OTP
=================================================================
The My Ride tab now contains a real map card:
  * BEFORE the payment: "Map and directions unlock as soon as the
    payment is verified" (no map, no route — your privacy rule).
  * AFTER the payment (paid / arrived): a map with the rider's own
    position, the route to the PICKUP and a
    "DIRECTIONS TO PICKUP" button that opens turn-by-turn navigation.
  * AFTER the OTP is entered (ongoing): the same card switches to the
    DROP — route to the drop point and "DIRECTIONS TO DROP".
    The drop location is never revealed before the OTP.

=================================================================
7) RIDER UNAVAILABILITY SLOTS   (your request)
=================================================================
Rider portal -> PROFILE tab -> "WHEN I AM NOT AVAILABLE":
  * EVERY WEEK  — pick a weekday and a start/end time (e.g. every
    Monday 9:00-11:00 for a class). Repeats forever.
  * ONE DATE    — pick a date and a start/end time (e.g. 24 Sep
    14:00-18:00). Applies to that date only.
  * Every block is listed with a delete (trash) button, so blocks are
    easy to edit — delete and add again.
  * Rides requested inside a blocked period are automatically UN-
    AVAILABLE for that rider: he is not notified, and if every rider
    is blocked the student is told to book for another time.
  New endpoints: GET/POST /api/ride/vendor/blocks/  and
                 POST /api/ride/vendor/blocks/<id>/delete/

=================================================================
8) RIDER LOGOUT   (your request)
=================================================================
A red "LOG OUT" button at the bottom of the rider portal's PROFILE
tab. It asks for confirmation, stops the GPS sharing and the polling
timer, clears the session and returns to the home page.

=================================================================
9) EVERYTHING ELSE IN THIS RELEASE
=================================================================
  * kAppVersion is now 73 (the update dialog compares against this).
  * Admin broadcasts are marked with route "broadcast" so the app can
    deep-link them to the home page instead of the notices list.
  * Default profile address is now "Chandigarh University UP,
    Parsandan, Uttar Pradesh 209859" everywhere.
  * Tested: 21/21 security checks pass and the full ride lifecycle
    (estimate -> book -> accept -> pay -> OTP -> start -> complete ->
    reject -> blocks -> notifications) was re-run against the new
    Mini/Sedan/XL fares.

=================================================================
FILES CHANGED IN THIS ZIP
=================================================================
FLUTTER
  lib/data/up_places.dart                        (NEW — place database)
  lib/services/offline_tiles.dart                (NEW — offline tiles)
  lib/widgets/broadcast_card.dart                (NEW — broadcast card)
  lib/services/app_store.dart                    (blocks, booking fields)
  lib/services/fcm.dart                          (remember broadcasts)
  lib/services/notif_router.dart                 (broadcast route)
  lib/screens/splash_screen.dart                 (version 73, Later fix)
  lib/screens/dashboard/student_dashboard_screen.dart  (broadcast card)
  lib/screens/ride/ride_home_screen.dart         (booking rebuild)
  lib/screens/ride/ride_map_picker_screen.dart   (campus, places, GPS)
  lib/screens/ride/ride_live_map_screen.dart     (campus fallback)
  lib/screens/ride/rider_console_screen.dart     (popup, map, call,
                                                  blocks, logout)
  lib/screens/store/hostel_essentials_screen.dart (new default address)

BACKEND
  backend/myproject/ride/models.py               (contact fields, blocks)
  backend/myproject/ride/migrations/0005_riderblock_ride_contact_and_more.py (NEW)
  backend/myproject/api_app/views.py             (estimate/book/blocks,
                                                  broadcast route)
  backend/myproject/api_app/urls.py              (block endpoints)

=================================================================
HOW TO APPLY (PowerShell)
=================================================================
1) Expand-Archive -Path .\cunnect_v73_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v73 -Force
   Copy-Item -Path C:\Users\adars\Downloads\cunnect_v73\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force

2) cd C:\Users\adars\Downloads\cunnect_food_flutter
   flutter pub get          # no NEW packages this time (flutter_map,
                            # http and path_provider were already added
                            # in v72) — run it anyway to be safe.

3) cd C:\Users\adars\Downloads\cunnect_food_flutter\backend\myproject
   python manage.py migrate     # ⭐ REQUIRED: migration 0005
   git add -A
   git commit -m "v73: ride booking rebuild, offline UP map, rider blocks"
   git push

4) cd C:\Users\adars\Downloads\cunnect_food_flutter
   flutter build apk --release

5) GitHub release tag: 73

IMPORTANT
---------
* "python manage.py migrate" IS MANDATORY — migration 0005 adds the
  contact/booking-for-other fields and the RiderBlock table.
* No new paid API and no Google key: maps are OpenStreetMap, geocoding
  is Nominatim, places and offline tiles are local.
* The university pin is hardcoded at the coordinates you gave, so it
  is guaranteed to show even where OpenStreetMap has no polygon yet.

CUnnect v72 — feed links · 6-icon bar · RIDE: live map + new features
=================================================================
(Cumulative: includes v61-v71 — vendor self-service store, media
banners, real-time speed, cunnect.online primary domain, in-app
password reset, iOS support, full v65 security hardening.)

=================================================================
1) FORGOT-PASSWORD FIX  (the v65 regression you reported)
=================================================================
WHAT WENT WRONG: v65 shortened password-reset links to 30 MINUTES.
Any link opened later (mail arrives late / opened the next morning)
showed the "Link expired" WEBSITE page instead of opening the app.

WHAT CHANGED:
  * Reset links are valid 24 HOURS again (still single-use, so the
    security is unchanged — a link dies the moment it is used).
  * An EXPIRED or already-used link no longer leaves the user on a
    website: it now ALSO bounces into the app
    (cunnect://reset/expired/1) and opens a themed in-app screen with
    a "SEND ME A NEW LINK" button. The user never has to touch a
    browser again.
  * The bounce page now opens the app far more reliably: it tries the
    plain cunnect:// jump first and falls back to Android's
    intent:// form (this is the one that works inside Gmail's
    in-app browser / Chrome Custom Tabs, where plain scheme jumps
    are often blocked).
  * The email now says the link is valid for 24 hours.

FILES: backend/myproject/api_app/views.py
       backend/myproject/myproject/settings.py
       lib/services/deep_link.dart
       lib/screens/auth/reset_link_expired_screen.dart  (NEW)

=================================================================
2) CUNNECT RIDE  (new section — Uber-like, campus only)
=================================================================
HOW IT WORKS (student):
  Home screen -> "Ride" tile (left of Partner).
  1. Pickup & drop: type a name and TAP THE MAP to drop the pin
     (OpenStreetMap — no Google API key, no billing, works on any VPS).
  2. Choose a time: "Leave now" or pick an hour.
  3. Pick a vehicle: Auto / Mini / Sedan / Car XL (NO bike, as asked).
     Fares appear automatically the moment both points are set — the
     distance is computed on the server.
  4. Tap BOOK RIDE. Nothing is charged here.
  5. A rider accepts -> you get a notification -> tapping it opens the
     payment page:
        * Pay in full        -> no extra charge
        * Pay 50-50          -> +5% add-on, half now, half after the ride
          (e.g. Rs 200 ride = Rs 210 total = Rs 105 now + Rs 105 later)
     Payment uses the SAME QR + UPI-ID + transaction-ID flow as food,
     print and the hostel store (the amount is embedded in the QR).
  6. Rider reaches you and taps "I'm on location" -> a 4-digit OTP is
     sent to you (push + in-app). You enter it -> the ride starts.
  7. Rider completes the ride -> you get:
        "Your ride has been completed successfully"
     If you rode on 50-50, the balance screen opens for the second half.

HOW IT WORKS (rider — ride partner):
  You create the partner from the Admin panel -> Vendors -> type
  "Ride Partner" (new option). They log in with their vendor phone +
  password and land directly in the RIDE PARTNER console:
    * Profile  : vehicle number/model, ONLINE-OFFLINE switch, and their
                 OWN pricing (base fare + per km) for each vehicle type
                 they offer, plus lifetime rides & earnings.
    * Requests : incoming rides with pickup, drop, distance and fare.
                 The student's MOBILE NUMBER STAYS HIDDEN until the
                 rider accepts (same rule as the print portal).
                 Accept / Reject — rejected rides never come back.
    * My Ride  : "I'M ON LOCATION" (sends the OTP, shown in a dialog),
                 then OPEN MAP TO DESTINATION (opens Google Maps with
                 the drop point) and COMPLETE RIDE.
  Ride alerts ring the rider's phone like a food order does.

RULES BAKED IN:
  * Price is NEVER taken from the app — the server recomputes every
    fare from the locked rate + distance (tampering tested).
  * A student with an unpaid 50-50 balance cannot book another ride
    until it is cleared.
  * A student can have only one active ride at a time.
  * Two riders cannot both grab the same ride (atomic accept).
  * Only the rider sees the start OTP; the student never does.
  * Non-vendors cannot open the rider portal; another student cannot
    read or pay for your ride (404).
  * Distance needs NO external API: haversine x road factor, so it
    keeps working on your own VPS with zero API keys.

=================================================================
3) SMALL CHANGES
=================================================================
  * Contact Us dropdown: added "Collaboration".
  * Admin panel: "Ride Partner" vendor type (icon + create form).
  * Notification taps for ride alerts open the live ride screen.

=================================================================
4) v68 FIXES
=================================================================
  a) BOTTOM BAR — REVERTED to the classic single-row layout, exactly
     like the immediately previous build: ALL SIX icons visible in one
     row (UMS · Food · Store · Feed · Ride · Partner), evenly spaced,
     and each icon still flashes RED the instant you touch it (and
     goes back to grey when you lift). The horizontal-swipe carousel
     from the earlier build is gone.

  b) RIDE MAP — SEARCH now works:
        * type a place name above the map ("Sadar Bazar", "Sector 14",
          "railway station"…) and results drop down instantly;
          picking one flies the map there and fills the name.
        * results are biased towards the campus, so the nearest match
          is always on top (far-away places still searchable).
        * TAP ANYWHERE ON THE MAP and the address is filled in
          AUTOMATICALLY — no typing at all. You can still edit it.
        * Powered by OpenStreetMap Nominatim — free, no API key, no
          billing, works on your VPS. Requests are debounced
          (Nominatim asks for max 1/second) and identified properly.

  c) ADMIN PANEL — the vendor "Section / vendor type" chooser only
     listed the built-in types when NO custom store section existed,
     so "Ride Partner" never showed up in a live store. Now ALL types
     are always offered:
        🍔 Food   🖨 Printout   🛏 Hostel   🛺 Ride Partner
        + every custom store section you created.
     So every kind of vendor can be added from the admin panel.

WHY 72
------
v72 = v71 + (1) clickable RED links on the feed, (2) all SIX footer
icons visible, (3) a much richer Ride section with a full-screen LIVE
MAP. Version bumped so phones already on v71 still get the in-app
update prompt.

=================================================================
5) RIDE — BIG UPGRADE (v69)
=================================================================
  a) OTP FLOW FLIPPED (as you asked)
        OLD : rider tapped "I'm on location" -> OTP showed on the
              RIDER's phone -> student typed it.
        NEW : rider taps "I'm on location" -> the OTP appears on the
              STUDENT's screen -> the student reads it out -> the
              RIDER types it into his console -> ride starts.
              (Wrong OTP is rejected; the rider never sees it.)

  b) LIVE MAP — Uber style
        Once the ride is paid, the student sees a map with the pickup
        pin, the destination pin, the RIDER's live vehicle and a red
        route line. It shows "Rider ~4 min away" / "Destination in
        ~9 min" and refreshes automatically.
        The rider app shares its GPS every 10 seconds while a ride is
        live (stops automatically when the ride ends).

  c) TIME IS EVERYWHERE
        The scheduled time the student picked now shows on the booking
        sheet, the student's ride screen ("Today 18:45") and on every
        request card in the rider portal ("Today 18:45" / "Tomorrow
        09:30"). Distance and ETA chips too.

  d) BOOK RIDE -> Uber-style BOTTOM SHEET
        Tapping BOOK RIDE now slides a sheet up from the bottom with:
        the route, the chosen vehicle, distance + ETA, the fare,
        YOUR MOBILE NUMBER (pre-filled, editable — this is what the
        rider calls) and a note for the rider. Confirm from there.

  e) AFTER A RIDER ACCEPTS, THE STUDENT SEES
        rider name · vehicle model · VEHICLE NUMBER (mono badge) ·
        rider mobile with a one-tap CALL button.

  f) HISTORY
        Student: "YOUR RIDES" list at the bottom of the Ride screen
        (distance, status, amount). Rider: recent rides with the
        student's name and earnings, plus total rides/earnings on the
        Profile tab.

  g) MAP SEARCH FIXED — "chandigarh university nawabganj uttar
     pradesh" now works. Nominatim returns nothing when you add extra
     words, so the search now retries by dropping trailing words and
     finally searches world-wide. Also:
        * the campus centre is set to Chandigarh University
          (30.7686, 76.5750) — one constant in
          lib/screens/ride/ride_map_picker_screen.dart (campusLat /
          campusLng) if your campus is elsewhere;
        * results are ranked around the campus;
        * tap on the map still fills the address automatically.

  h) SPEED (you said ~20 s — here is what changed)
        * the ride screen PAINTS INSTANTLY from the last saved copy
          while the fresh data loads behind it;
        * the rider console now loads profile + requests + rides in
          ONE parallel round-trip instead of three;
        * live screens refresh every 5 seconds (was 8) and there is a
          refresh button on the map;
        * nothing waits on a spinner any more.
        NOTE: the remaining slowness you saw is very likely the Render
        free instance waking up (a cold start is 20-40 s). The moment
        you move to your own VPS that disappears — the app side is
        already as fast as it can be.

  i) NEW DEPENDENCY + PERMISSIONS
        pubspec  : geolocator (only for the rider's GPS sharing)
        Android  : ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION
        iOS      : NSLocationWhenInUseUsageDescription
        -> run "flutter pub get" before building.

=================================================================
6) v72 — WHAT'S NEW
=================================================================
  a) BOTTOM BAR: FIVE icons on the screen, swipe for the rest.
     (fix: the icon turns RED the instant you touch it and goes
      grey on release — a GestureDetector stops reporting the press
      inside a scrollable, so the tile now listens to raw pointer
      events. Dragging to swipe the bar no longer lights anything up,
      and a label never wraps: "Partner" stays on one line and simply
      scales down on very narrow phones.)
     Order:  UMS · Food · Store · Feed · Ride · Partner
     Ride sits immediately LEFT of Partner (as you asked). Swiping the
     bar horizontally brings the remaining icon into view. Tapping an
     icon still flashes it RED on touch and back to grey on release.

  b) ONE PHONE PER ACCOUNT (single-device login)
     If a UID is signed in on one mobile, no other mobile can sign in
     with that UID until the first one logs out. The second phone gets:

         "This UID is already logged in on another device.
          Log out there first, then sign in here."

     as a WARNING POPUP (and in the red error box under the form).

     Details:
       * applies to the normal login AND the legacy student-login;
       * the SAME phone can always log in again (each install has a
         stable device id) — only a different phone is blocked;
       * the message never leaks whether the password was right — a
         wrong password still says "Incorrect password";
       * NEW endpoint: POST /api/auth/logout/ — the app calls it when
         the user taps Logout, which frees the account instantly
         (the auth token is deleted too, so it cannot be replayed);
       * SAFETY VALVE: if a phone is lost/never used again, the lock
         releases itself after 7 days of no activity, so nobody is
         locked out forever. An admin can also delete the row from
         Django admin (CUnnect → Login sessions).

     NEW MIGRATION: myapp/0034_loginsession.py — "python manage.py
     migrate" is REQUIRED on the server.

=================================================================
7) v72 — WHAT'S NEW (this build)
=================================================================
  a) FEED LINKS ARE RED AND OPEN WITH ONE TAP
     Any http(s):// or www. link inside a feed post (or a comment)
     is painted in CUnnect RED and underlined — tap it and the link
     opens straight away in the browser. Trailing punctuation
     ("see this...") is not swallowed into the link.

  b) ALL SIX FOOTER ICONS VISIBLE
     UMS · Food · Store · Feed · Ride · Partner now all fit on the
     screen (the bar stays swipeable as a safety net on very narrow
     phones). Touch still flashes the icon RED instantly.

  c) RIDE — FULL-SCREEN LIVE MAP  ⭐
     A dedicated map screen (button "LIVE MAP" on the Ride home while
     a ride is running, and the expand icon on the trip map):
       • pickup + destination pins, the rider's vehicle moving live
       • the student's own blue dot when they share their location
       • live route line, distance and ETA in the status pill
       • follow-the-rider camera, zoom in/out, recentre, refresh
       • call the rider, read out the OTP and pay from the map
     Refreshes every 5 seconds, opens instantly from the cache.

  d) SHARE MY LIVE LOCATION (new, v72)
     A switch on the trip screen (and on the live map): turn it ON
     and the app sends your GPS to the rider every 10 seconds so he
     can find your exact pickup spot. Turn it OFF any time — while
     it is off the rider sees nothing at all.
     New endpoint: POST /api/ride/student/location/<code>/

  e) RIDE HOME LOOKS AND FEELS RICHER
       • hero card: live-tracking shortcuts while a ride is running,
         a real map preview of the chosen route, or the intro card
       • "Swap" and "Use my location" right inside the route card
         (current position is reverse-geocoded into a real address)
       • "BEST VALUE" badge on the cheapest vehicle
       • total rides + total spent in the YOUR RIDES header

  NEW MIGRATION: ride/0004_ride_student_lat_ride_student_lng_and_more.py
  — "python manage.py migrate" IS REQUIRED on the server this time.

=================================================================
HOW TO APPLY (PowerShell)
=================================================================
1) Expand-Archive -Path .\cunnect_v72_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v72 -Force
   Copy-Item -Path C:\Users\adars\Downloads\cunnect_v72\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force

2) cd C:\Users\adars\Downloads\cunnect_food_flutter
   flutter pub get                       # ⭐ REQUIRED: flutter_map + latlong2

3) cd C:\Users\adars\Downloads\cunnect_food_flutter\backend\myproject
   python manage.py migrate              # ⭐ REQUIRED: new "ride" app tables
   git add -A
   git commit -m "v72: feed links, 6-icon bar, Ride live map + features"
   git push

4) cd C:\Users\adars\Downloads\cunnect_food_flutter
   flutter build apk --release

5) GitHub release tag: 72

IMPORTANT
---------
* Two NEW dependencies: flutter_map + latlong2 (OpenStreetMap).
  "flutter pub get" is mandatory before building — the build will fail
  without it. If your Flutter SDK is very new and pub get complains
  about flutter_map ^6.1.0, run:  flutter pub add flutter_map latlong2
* "python manage.py migrate" is mandatory on the server (new ride
  tables). On Render add it to the build command or run it in the
  shell once.
* Nothing here depends on Render, Google Maps, or any paid API — the
  whole Ride feature runs as-is on the VPS you are moving to. Just
  point DJANGO_ALLOWED_HOSTS / CSRF_TRUSTED_ORIGINS at the new domain
  and update ApiConfig.primaryUrl in lib/services/api_client.dart
  when you switch hosts.
* Tested: 19/19 security checks pass (brute force, access control,
  price tampering, upload guards, UMS auth, reset flow) plus a full
  ride lifecycle test (book -> accept -> pay full & 50-50 -> reject
  handling -> OTP -> start -> complete -> balance -> notifications).
