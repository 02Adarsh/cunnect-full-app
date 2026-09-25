CUnnect v90 — Overlay sticky update + durable instant lock
==========================================================
(Cumulative v61-v89.)

NO NEW MIGRATION. myapp.0037 enough.

0) YOUR 3 BUGS — FIXED FOR REAL
--------------------------------
1. UPDATE POPUP FLASH→VANISH
   Root cause: showDialog lived on a ROUTE. Splash pushReplacement
   destroyed it. v90 uses a ROOT OverlayEntry — survives every
   navigation. Stays until Later OR install. Later = this session
   only; next cold start → popup again. Never permanently silenced.

2. LOCK ICON SIZE = 24 (same as Food/Store/Feed/Ride).

3. LOCK LATE AFTER REOPEN
   - Lock flags cached to disk + in-memory mirror (never lost).
   - Splash ALWAYS refreshes locks before routing to dashboard.
   - Hub blocks Food/Store/Feed/Ride taps until locks are ready
     when cache is empty (no race).
   - Cached locks paint on first frame.

1) BUILD — use the .ps1 (chat cannot break it)
----------------------------------------------
Download BOTH into Downloads:
  cunnect_v90_update.zip
  cunnect_v90_build.ps1

  cd C:\Users\adars\Downloads
  powershell -ExecutionPolicy Bypass -File .\cunnect_v90_build.ps1

2) AFTER APK
------------
Set apk_url + version>90 in deploy/app_version.json, push
cunnect-backend, reopen app → sticky overlay update.
