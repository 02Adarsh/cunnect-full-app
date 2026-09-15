# CU nnect — Flutter App + Tera Django Backend (Full Stack)

Tera poora Django project (food app, vendor portal, delivery portal, chat/network,
UMS/Collegia, dashboard, store, printout) Flutter mein convert kiya gaya hai —
**UI original Django templates jaisa hi** hai, aur **saara data tere REAL Django
backend se API ke through aata hai** (koi demo/fake data app ke andar nahi).

## Folder structure

```
cunnect_food/
├── lib/                  # Flutter app (saare panels)
│   ├── services/app_store.dart   # saara state + API calls
│   ├── services/api_client.dart  # HTTP layer
│   └── screens/...               # customer/vendor/delivery/chat/ums/print/store
├── test/                 # API-layer unit tests (mocked HTTP)
├── android/ , ios/ , web/
├── pubspec.yaml
└── backend/
    ├── api_requirements.txt      # backend ke liye chhoti dependency list
    └── myproject/                # TERA original Django project
        ├── api_app/              # NAYA: REST API layer (Flutter isi se baat karta hai)
        ├── food/  myapp/  network/  scraper_app/   # original apps (untouched)
        ├── media/                # tere real images/banners/food photos
        ├── db.sqlite3            # tera real database
        ├── templates/  static/
        └── .env
```

## Chalane ka tarika — pehle backend, phir app

### Step 1: Django backend

```bash
cd backend/myproject
python -m venv venv
venv\Scripts\activate          # Windows PowerShell
# Linux/Mac: source venv/bin/activate

pip install -r ..\api_requirements.txt

python manage.py migrate       # ek baar (API token table ban jata hai)
python manage.py runserver 0.0.0.0:8000
```

> Original website bhi `http://localhost:8000` par hi chalti hai — API `/api/...`
> par hai, baaki sab kuch pehle jaisa.

### Step 2: Flutter app

```bash
flutter pub get
flutter run
```

- **Android emulator:** default server URL `http://10.0.2.2:8000` set hai.
- **Real phone:** login screen par **⚙ chip** dabao aur apne computer ka LAN IP
  daalo, jaise `http://192.168.1.10:8000` (phone + computer same WiFi par).

## Logins (tere real db.sqlite3 ke accounts)

- **Student:** CUIMS UID + password (jaise tu website par karta hai)
- **Vendor portal:** vendor phone number + password
  (food vendor: Campus Kitchen · print vendor: printout)
- **Delivery portal:** delivery phone number + password
- **UMS/Collegia:** real CUIMS UID + password + captcha (2-step). Campus network
  na ho to **Demo Login** button se sample data dekh sakte ho.

## API layer

Saare endpoints `/api/` ke neeche, JSON, `Authorization: Token <key>` header.
Response hamesha `{"ok": true, "data": {...}}` ya `{"ok": false, "error": "..."}`.

| Area | Endpoints |
|------|-----------|
| Auth | `POST auth/student-login/` |
| Student | `student/dashboard/`, `student/support/` (POST), `student/profile/` |
| Food | `food/home/`, `food/orders/` (POST), `food/my-orders/`, `food/orders/status/`, `food/coupon/validate/` (POST), `food/notifications/`, `food/notifications/read/` (POST) |
| Vendor | `vendor/login/` (POST), `vendor/dashboard/`, `vendor/orders/<id>/<accept\|reject\|prepare\|ready>/` (POST), `vendor/orders/<id>/start-delivery/` (POST), `vendor/orders/<id>/verify-otp/` (POST), `vendor/menu/`, `vendor/menu/add/`, `vendor/menu/<id>/edit/`, `vendor/menu/<id>/toggle/`, `vendor/kitchen/<on\|off>/`, `vendor/earnings/` |
| Delivery | `delivery/login/` (POST), `delivery/dashboard/`, `delivery/claim/<id>/` (POST), `delivery/verify-otp/<id>/` (POST otp) |
| Printout | `print/vendors/`, `print/orders/` (POST multipart, file field `document`), `print/my-orders/`, `print/vendor/dashboard/`, `print/orders/<id>/<accept\|reject\|printing\|ready\|complete>/`, `print/vendor/prices/` (POST) |
| Chat | `chat/rooms/`, `chat/rooms/create/` (POST), `chat/rooms/<name>/`, `chat/rooms/<name>/join/` (POST), `chat/rooms/<name>/messages/` (POST), `chat/rooms/<name>/polls/` (POST), `chat/polls/<id>/vote/` (POST), `chat/messages/<id>/like/` (POST), `chat/messages/<id>/pin/` (POST) |
| Store | `store/home/` |
| UMS | `ums/stage1/` (POST uid), `ums/stage2/` (POST uid+password+captcha), `ums/demo/` (POST), `ums/dashboard/?uid=`, `ums/logout/` (POST) |

## Delivery OTP flow (original jaisa)

1. Vendor order **Ready** karta hai → delivery partner **Claim** karta hai
   (ya vendor khud **Start Delivery** dabata hai) → order `out_for_delivery`.
2. Customer ko apne order ke saath **OTP** dikhta hai.
3. Vendor/delivery customer se OTP lekar **Verify OTP** karta hai → order **Completed**.
   OTP sirf customer ke endpoints par expose hota hai.

## Notes

- Cart local hai (Django session cart jaisa); coupon validation server-side.
- Food home har 3s order-status poll karta hai; vendor/delivery/print dashboards 5s.
- Printout mein PDF ke pages **server par count hote hain** (pypdf), price
  vendor ke per-page rates se banta hai.
- UMS scraping tera original `scraper_app` (`CUIMSScraperBackend`) use karti hai.
- `flutter test` → API-layer ke mocked tests (server ke bina).

**Media note:** ZIP mein `media/chat/` (badi videos) aur `media/print_orders/`
(purane uploaded docs) size ki wajah se included nahi hain. Ye tere GitHub repo
(02Adarsh/new1) mein already hain — wahan se copy karke
`backend/myproject/media/` mein daal dena (optional, sirf purane attachments
dikhaane ke liye). Baaki sab media (banners, food images, hero slides, etc.)
included hai.
