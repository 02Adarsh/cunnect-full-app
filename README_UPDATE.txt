CUnnect v86 — lock keeps original icons, hides name; My Orders lock + ALL fix
==========================================================================
(Cumulative: includes v61-v85.)

NO NEW MIGRATION. myapp.0037 (is_locked) from v85 is enough.
my_orders is a new BUILTIN section row (created automatically on first
/api/store/sections/ or /api/admin/sections/ call).

=================================================================
0) WHAT v86 CHANGES
=================================================================
1. HUB ICONS STAY THE ORIGINAL MATERIAL ICONS.
   Lock no longer swaps in an emoji. Food / Store / Feed / Ride keep
   restaurant / shopping_bag / dynamic_feed / local_taxi forever.

2. LOCKED = LOCK GLYPH ONLY, NO NAME UNDER IT.
   Bottom bar: lock icon, blank label.
   Store cards: lock icon only (title + subtitle hidden).
   Profile → My Orders: lock icon, blank label.
   Tap does nothing — no toast, no open, no "coming soon".

3. PROFILE → MY ORDERS IS LOCKABLE FROM ADMIN.
   Admin → Store → section "My Orders" (CORE) → Lock switch → Save.
   Student profile then shows a lock instead of "My Orders".

4. MY ORDERS → ALL REALLY LOADS EVERYTHING.
   Print / hostel / rides / AUTO calls fire in PARALLEL the moment
   the page opens and every 3 seconds after. Active ride sits on top.
   Silent failures no longer wipe the other lists.

5. Fast in-app update from v85 is kept (progress bar + auto-install).
6. One notification tone (universfield) from v85 is kept.

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

cd C:\Users\adars\Downloads
Remove-Item -Recurse -Force .\cunnect_v86 -ErrorAction SilentlyContinue
Expand-Archive -Path .\cunnect_v86_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v86 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v86\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
Remove-Item -Force .\android\app\src\main\res\raw\universfield_new_notification_066_494545.wav -ErrorAction SilentlyContinue
Get-ChildItem .\android\app\src\main\res\raw\ | Format-Table Name
flutter pub get
cd backend\myproject
python manage.py migrate
git add -A ; git commit -m "v86: lock keeps icons hides name, My Orders lock, ALL tab fix" ; git push origin main
cd C:\Users\adars\Downloads\cunnect_food_flutter
git add -A ; git commit -m "v86: lock keeps icons hides name, My Orders lock, ALL tab fix" ; git push origin main
flutter build apk --release

NOTES
- TWO REPOS (both required):
    backend\myproject  →  https://github.com/02Adarsh/cunnect-backend.git  (Render)
    app root           →  https://github.com/02Adarsh/cunnect-full-app.git
  Always `git push origin main`.
- Get-ChildItem must show universfield_….mp3 ONLY (no .wav twin).
- makemigrations warning is a red herring — do not run it.
