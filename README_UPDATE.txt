CUnnect v88 — sticky update popup + instant lock + lock size 24
===============================================================
(Cumulative: includes v61-v87.)

NO NEW MIGRATION. myapp.0037 (is_locked) from v85 is enough.

=================================================================
0) WHAT v88 FIXES
=================================================================
1. UPDATE POPUP STICKY (like before).
   - No more flash-and-vanish.
   - Stays until you tap Later OR install finishes.
   - Later = this session only. Next app open → popup again
     until you actually update. Never permanently silenced.

2. LOCK ICON SIZE = 24 (same as Food/Store/Feed/Ride icons).

3. LOCK FLAGS CACHED ON DISK.
   Cold start paints the lock IMMEDIATELY from last known
   admin state. No more "Food opens unlocked for a few seconds
   then lock appears".

4. Everything from v86/v87 kept:
   - Original Material hub icons (no emoji swap)
   - Locked = lock glyph only, no section name
   - Profile → My Orders admin-lockable (my_orders CORE)
   - My Orders ALL = food + print + hostel + ride + auto

=================================================================
1) HOW TO LOCK
=================================================================
Admin → Store → pencil on Food / Store / Feed / Ride / My Orders
→ "Lock (users cannot open)" → Save.
Student must force-close once after admin lock so the cache
refreshes; after that every reopen is instant-locked.

=================================================================
2) BUILD (Windows PowerShell) — ONE BLOCK
=================================================================
!! Zip name is EXACTLY: cunnect_v88_update.zip
!! Chat often turns .zip / manage.py into links — paste PLAIN text.
!! ALWAYS delete leftover universfield .wav before build.

cd C:\Users\adars\Downloads
Remove-Item -Recurse -Force .\cunnect_v88 -ErrorAction SilentlyContinue
Expand-Archive -Path .\cunnect_v88_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v88 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v88\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
Remove-Item -Force .\android\app\src\main\res\raw\universfield_new_notification_066_494545.wav -ErrorAction SilentlyContinue
Get-ChildItem .\android\app\src\main\res\raw\ | Format-Table Name
flutter pub get
cd backend\myproject
python manage.py migrate
git add -A ; git commit -m "v88: sticky update popup, instant lock cache, lock size 24" ; git push origin main
cd C:\Users\adars\Downloads\cunnect_food_flutter
git add -A ; git commit -m "v88: sticky update popup, instant lock cache, lock size 24" ; git push origin main
flutter build apk --release

NOTES
- TWO REPOS:
    backend\myproject  →  https://github.com/02Adarsh/cunnect-backend.git
    app root           →  https://github.com/02Adarsh/cunnect-full-app.git
  Always: git push origin main
- Get-ChildItem must show universfield_….mp3 ONLY (no .wav twin)
- After APK is hosted, set apk_url in deploy/app_version.json and
  push backend again so the sticky update can download.
