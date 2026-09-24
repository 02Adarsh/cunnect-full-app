CUnnect v85 — lock tiles, one notification tone, My Orders ALL fixed
==========================================================================
(Cumulative: includes v61-v84.)

ONE NEW MIGRATION THIS TIME (run it once):
  python manage.py migrate
    myapp.0037  StoreSection gets is_locked (hub/store lock from admin)

Also keep the two v84 migrations if you never ran them:
    myapp.0036  HostelOrder OUT FOR DELIVERY
    food.0024   notification categories (hostel + auto)

=================================================================
0) WHAT v85 CHANGES
=================================================================
1. ADMIN LOCK ON ANY SECTION (Food / Store / Feed / Ride / hostel /
   printout / any custom store). Edit the section → turn on
   "Lock (users cannot open)". The hub tile and the store card then
   show a LOCK icon. Tapping does NOTHING — no toast, no "available
   soon", no open. Turn the lock off to unlock.

2. ADMIN CAN CHANGE THE ICON of Food / Store / Feed / Ride (and every
   other section) from the same Edit sheet — the emoji you type is
   what the bottom bar and the store card show.

3. "COMING SOON" is no longer forced on locked tiles. Lock and
   Coming Soon are separate switches (turning one off clears the other).

4. MY ORDERS → ALL really refreshes. Print, hostel, rides (including
   the active ride) and AUTO calls re-fetch every 6 seconds and again
   the moment you switch tabs. Active rides sit on top of the list.

5. ONE NOTIFICATION TONE APP-WIDE. The same file the vendor ring
   uses (universfield_new_notification_066_494545) is now also the
   tray / heads-up notification sound. Backend push + Android
   channels moved to v7 so phones pick up the new tone.

6. AUTO accounts stay pure AUTO — the car console never offers them
   car bookings (v81 carry-forward, re-asserted).

=================================================================
1) HOW TO LOCK A SECTION
=================================================================
Admin panel → Store page → pencil on the section (Food, Store, Feed,
Ride, hostel, printout, or any custom) → toggle
"Lock (users cannot open)" → Save.
Change the Icon field on the same sheet to swap the emoji.

=================================================================
2) NOTIFICATION SOUND
=================================================================
Vendor ring (in-app) and the phone notification tray now share:
  assets/sounds/universfield_new_notification_066_494545.wav
  android/app/src/main/res/raw/universfield_new_notification_066_494545.wav
Replace BOTH with your own file (SAME base name), then rebuild the APK.
Do NOT leave a .mp3 and a .wav with the same base name — that breaks
the release build (mergeReleaseResources).

=================================================================
3) BUILD (Windows PowerShell) — ONE BLOCK
=================================================================
cd C:\Users\adars\Downloads
Remove-Item -Recurse -Force .\cunnect_v85 -ErrorAction SilentlyContinue
Expand-Archive -Path .\cunnect_v85_update.zip -DestinationPath C:\Users\adars\Downloads\cunnect_v85 -Force
Copy-Item -Path C:\Users\adars\Downloads\cunnect_v85\* -Destination C:\Users\adars\Downloads\cunnect_food_flutter -Recurse -Force
cd C:\Users\adars\Downloads\cunnect_food_flutter
flutter pub get
cd backend\myproject
python manage.py migrate
git add -A ; git commit -m "v85: section lock + icon, one notif tone, My Orders ALL refresh" ; git push origin main
cd C:\Users\adars\Downloads\cunnect_food_flutter
git add -A ; git commit -m "v85: section lock + icon, one notif tone, My Orders ALL refresh" ; git push origin main
flutter build apk --release

NOTES
- Backend repo is https://github.com/02Adarsh/cunnect-backend.git (main)
  — that is what Render deploys. The app repo is
  https://github.com/02Adarsh/cunnect-full-app.git (main).
  Both pushes above are required; use `git push origin main`.
- Expand-Archive -Force does NOT overwrite — always Remove-Item first.
- If res/raw still has universfield_… .wav AND .mp3, delete the .wav
  duplicate only if you intentionally keep the .mp3 — never both.
- First launch after install recreates notification channels (v7) so
  the new sound is heard even if an older channel was stuck on mute.
