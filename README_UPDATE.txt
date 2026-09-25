CUnnect v89 — sticky update (real fix) + instant lock + lock size 24
====================================================================
(Cumulative: includes v61-v88.)

NO NEW MIGRATION. myapp.0037 (is_locked) from v85 is enough.

=================================================================
0) WHAT v89 FIXES (your 3 bugs)
=================================================================
1. UPDATE POPUP — OLD BEHAVIOUR RESTORED
   Root cause of flash→vanish: dialog was shown ON the splash route,
   then pushReplacement destroyed it and marked it "already shown".
   v89 NEVER shows on splash. It only shows AFTER the next screen
   (dashboard/login) is on the stack, via PendingUpdate on the root
   navigator.
   - Stays until you tap Later OR install finishes (back blocked).
   - Later = this session only. Next app open → popup again until
     you actually install. Never permanently silenced.

2. LOCK ICON SIZE = 24 (same as Food/Store/Feed/Ride hub icons).

3. LOCK INSTANT ON COLD START
   - Disk cache of builtin is_locked hydrated in AppStore ctor.
   - Splash refreshes /api/store/sections/ BEFORE routing.
   - Dashboard AWAITS loadStoreSections before other work.
   So Food cannot open unlocked for a few seconds after reopen.

Also kept from v86/v87:
   - Original Material hub icons (no emoji swap)
   - Locked = lock glyph only, no section name
   - Profile → My Orders admin-lockable (my_orders CORE)
   - My Orders ALL = food + print + hostel + ride + auto

=================================================================
1) HOW TO LOCK
=================================================================
Admin → Store → pencil on Food / Store / Feed / Ride / My Orders
→ "Lock (users cannot open)" → Save.

=================================================================
2) BUILD — use the .ps1 script (chat cannot break it into links)
=================================================================
Download BOTH:
  cunnect_v89_update.zip
  cunnect_v89_build.ps1
into C:\Users\adars\Downloads

Then run ONLY:

  cd C:\Users\adars\Downloads
  powershell -ExecutionPolicy Bypass -File .\cunnect_v89_build.ps1

The script does Expand + Copy + wav delete + pub get + migrate +
both git push origin main + flutter build apk --release.

Manual block (plain text only — no [http] junk allowed):

cd C:\Users\adars\Downloads
Remove-Item -Recurse -Force .\cunnect_v89 -ErrorAction SilentlyContinue
Expand-Archive -Path .\cunnect_v89_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v89 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v89\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
Remove-Item -Force .\android\app\src\main\res\raw\universfield_new_notification_066_494545.wav -ErrorAction SilentlyContinue
Get-ChildItem .\android\app\src\main\res\raw\ | Format-Table Name
flutter pub get
cd backend\myproject
python manage.py migrate
git add -A ; git commit -m "v89: sticky update after route, instant lock, lock size 24" ; git push origin main
cd C:\Users\adars\Downloads\cunnect_food_flutter
git add -A ; git commit -m "v89: sticky update after route, instant lock, lock size 24" ; git push origin main
flutter build apk --release

NOTES
- backend\myproject → https://github.com/02Adarsh/cunnect-backend.git
- app root → https://github.com/02Adarsh/cunnect-full-app.git
- Always: git push origin main
- Get-ChildItem must show universfield_….mp3 ONLY (no .wav twin)
- After APK is hosted set apk_url in deploy/app_version.json and
  push backend so the sticky update can download.
