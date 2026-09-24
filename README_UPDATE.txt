CUnnect v87 — My Orders ALL hardened + v86 lock/icons
=====================================================
(Cumulative: includes v61-v86.)

NO NEW MIGRATION. myapp.0037 (is_locked) from v85 is enough.
my_orders is a BUILTIN section row (auto-created on first sections call).

=================================================================
0) WHAT v87 CHANGES (on top of v86)
=================================================================
1. HUB ICONS STAY THE ORIGINAL MATERIAL ICONS (v86).
   Food / Store / Feed / Ride = restaurant / shopping_bag /
   dynamic_feed / local_taxi. Lock never swaps an emoji in.

2. LOCKED = LOCK GLYPH ONLY, NO SECTION NAME (v86).
   Bottom bar, store cards, Profile → My Orders.

3. PROFILE → MY ORDERS LOCKABLE FROM ADMIN (v86).
   Admin → Store → "My Orders" (CORE) → Lock → Save.

4. MY ORDERS → ALL REALLY SHOWS EVERYTHING (v87 harden):
   - Dashboard preloads food + print + hostel + ride + AUTO
     the moment you land on home.
   - Profile opens MyOrdersScreen(mode: 'all') explicitly.
   - Each loader is isolated (one bad row / endpoint cannot
     wipe the other lists).
   - PrintOrder parser is type-safe (no crash on num/string mix).
   - First open shows a thin progress bar while all 5 endpoints
     load in parallel; tabs scroll horizontally.
   - Every 3s live refresh still re-pulls non-food lists.

5. Fast in-app update + one notif tone kept from v85.

=================================================================
1) HOW TO LOCK
=================================================================
Admin panel → Store page → pencil on:
  Food / Store / Feed / Ride / Printout / Hostel / My Orders
→ toggle "Lock (users cannot open)" → Save.

=================================================================
2) BUILD (Windows PowerShell) — ONE BLOCK
=================================================================
!! BEFORE BUILD: delete any leftover duplicate sound !!
  Your PC keeps the vendor ring as .mp3 in res/raw. NEVER keep a
  .wav with the same base name next to it.
  Copy-Item NEVER deletes leftover files — you MUST Remove-Item the .wav.

cd C:\Users\adars\Downloads
Remove-Item -Recurse -Force .\cunnect_v87 -ErrorAction SilentlyContinue
Expand-Archive -Path .\cunnect_v87_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v87 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v87\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
Remove-Item -Force .\android\app\src\main\res\raw\universfield_new_notification_066_494545.wav -ErrorAction SilentlyContinue
Get-ChildItem .\android\app\src\main\res\raw\ | Format-Table Name
flutter pub get
cd backend\myproject
python manage.py migrate
git add -A ; git commit -m "v87: My Orders ALL hardened, lock keeps icons hides name" ; git push origin main
cd C:\Users\adars\Downloads\cunnect_food_flutter
git add -A ; git commit -m "v87: My Orders ALL hardened, lock keeps icons hides name" ; git push origin main
flutter build apk --release

NOTES
- Zip file name is EXACTLY: cunnect_v87_update.zip
  (do not let chat turn it into a link — paste the plain name)
- TWO REPOS (both required):
    backend\myproject  →  https://github.com/02Adarsh/cunnect-backend.git  (Render)
    app root           →  https://github.com/02Adarsh/cunnect-full-app.git
  Always `git push origin main`.
- Get-ChildItem must show universfield_….mp3 ONLY (no .wav twin).
- makemigrations warning is a red herring — do not run it.
- After APK is up, put the direct APK URL into
  backend deploy/app_version.json → apk_url, then push backend again
  so students get the fast in-app update.
