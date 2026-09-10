# BizGo

Ứng dụng mobile **quản lý bán hàng – giao hàng – công nợ** cho xưởng sản xuất/bán lẻ (khoai lang, ngô chiên…).
Flutter + Firebase. Một đơn hàng có đầy đủ vòng đời: **tạo đơn → kho chuẩn bị → đóng hàng → xuất phát → giao → thu tiền → công nợ → báo cáo**.

> Tài liệu nghiệp vụ gốc: `Dac_ta_nghiep_vu_App_Ban_Hang_Giao_Hang_Mobile.docx`.

---

## 1. Công nghệ

| Mảng      | Dùng                                                                                                               |
| ---------- | ------------------------------------------------------------------------------------------------------------------- |
| UI         | Flutter (Material 3),`go_router`, `provider`                                                                    |
| Backend    | Firebase**Auth** (email/password) + **Cloud Firestore**                                                 |
| Biểu đồ | `fl_chart` (donut, line)                                                                                          |
| Ảnh       | `image_picker` + `flutter_image_compress` — **lưu local trên máy**, Firestore chỉ giữ đường dẫn |
| Push       | `firebase_messaging` (app) + **noti-server** Node.js (Admin SDK)                                            |
| Khác      | `flutter_slidable`, `url_launcher`, `flutter_launcher_icons`                                                  |

- **Firebase project:** `bizgo-877df` · **Android package:** `com.asc.bizgo`
- Auth dùng email/password nhưng **đăng nhập bằng SĐT**: SĐT được map thành `<số>@bizgo.local`.
- Tiền lưu **số nguyên (đồng)**, không dùng float.

---

## 2. Yêu cầu môi trường

- Flutter SDK (Dart ≥ 3.11).
- Android SDK / thiết bị hoặc emulator.
- Node.js ≥ 18 (chỉ cho noti-server).
- File **`google-services.json`** đã có sẵn trong repo (`android/app/`).
- File **service account** (`bizgo-877df-firebase-adminsdk-*.json`) **KHÔNG có trong git** (bảo mật) — chỉ cần cho noti-server, xin từ chủ project.

---

## 3. Cấu hình Firebase (bắt buộc — không thì login fail)

1. **Authentication → Sign-in method → bật Email/Password.**
2. **Firestore → Rules** (giai đoạn dev):
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /{document=**} {
         allow read, write: if request.auth != null;
       }
     }
   }
   ```
3. (Tuỳ chọn) Thêm SHA-1 nếu sau này dùng Google Sign-In / Phone Auth — **email/password không cần**.

> Query trong app đều tránh composite index (lọc `where` rồi sort trong bộ nhớ), nên **không cần tạo index** thủ công.

---

## 4. Chạy app

```bash
flutter pub get
flutter run                 # chạy debug lên máy/emulator
flutter analyze             # kiểm tra lỗi
```

### Build APK

```bash
flutter build apk --release                 # 1 file (~40-55MB)
flutter build apk --release --split-per-abi # tách theo CPU, arm64 ~18-25MB
flutter build appbundle --release           # cho Google Play
```

APK ra tại `build/app/outputs/flutter-apk/`.

### Icon launcher (khi đổi logo)

```bash
dart run flutter_launcher_icons   # đọc assets/images/logo_app.png
```

> VS Code: `Ctrl+Shift+B` = build apk release (đã cấu hình `.vscode/tasks.json`); `F5` = chạy debug.

---

## 5. Đăng nhập lần đầu

Chỉ có **một** tài khoản bootstrap: `0900000000` / `123456` (điền sẵn ở màn login). Đăng nhập lần đầu app khoá ở màn **Thiết lập tài khoản** — bắt đổi SĐT đăng nhập + mật khẩu mới cho vào. Các tài khoản khác do Chủ tự tạo sau.

| SĐT           | Vai trò               | Thấy gì                                                                                                 |
| -------------- | ---------------------- | --------------------------------------------------------------------------------------------------------- |
| `0900000000` | **Chủ** (owner) | tất cả: đơn, khách, sản phẩm, giao hàng, thu tiền, báo cáo, quản lý người dùng, nhật ký |

> Số bootstrap chỉ "mọc" ra Chủ khi `users` **chưa có Chủ nào** — không phải cửa hậu.

---

## 6. Phân quyền (RBAC) — 3 vai trò

| Vai trò                        | Làm được                                                                                                                        |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Chủ** (owner)          | toàn quyền. Người**duy nhất** xem Tổng quan (doanh thu) và đối soát giao hàng + thu tiền                          |
| **Kiểm hàng** (checker) | kho/đóng hàng/in phiếu, xem đơn, bấm**Xuất phát**. KHÔNG thấy Tổng quan, KHÔNG thấy bất kỳ con số tiền nào |
| **Sale** (sale) | CHỈ tạo đơn + xem đơn + in/chia sẻ phiếu. KHÔNG sửa/xoá/hủy đơn, KHÔNG thao tác kho, KHÔNG thấy Tổng quan, KHÔNG thấy tiền (trừ lúc tự soạn đơn — phải thấy giá mới lên được đơn) |

> Ẩn tiền là ẩn **triệt để**: đơn giá, thành tiền, tổng cộng, đã thu, còn thiếu, trạng thái thanh toán — trong app lẫn trên **phiếu in**. Phiếu do nhân viên in ra chỉ có mặt hàng + số lượng + tổng số lượng.

- **Có thể có nhiều Chủ** (2 người đồng sở hữu cùng quản 1 cửa hàng), nhưng hệ thống luôn giữ **ít nhất 1 Chủ** — không cho xoá/hạ cấp/khoá người cuối cùng. Chủ vào **Cài đặt → Quản lý người dùng** tạo tài khoản Chủ / Kiểm hàng / Sale; họ tự đăng nhập.
- ⚠️ **Nhiều Chủ KHÔNG phải để tách 2 cơ sở.** App là single-tenant: một Firebase project = một cửa hàng, mọi Chủ nhìn chung một kho dữ liệu (đơn, khách, giá, công nợ, doanh thu). Bán cho 2 cơ sở khác nhau thì phải dựng **2 Firebase project riêng**.
- Tạo tài khoản dùng **FirebaseApp phụ** nên Chủ **không bị đăng xuất** (không cần server).
- **KHÔNG có vai trò tài xế.** Kho đóng hàng xong bấm Xuất phát (từng đơn hoặc cả lô), cuối ngày Chủ vào tab **Giao hàng** tick đơn nào giao thành công + thu tiền.

Chặn ở 3 tầng: tab (bottom nav) · nút hành động · route guard. Xem `lib/core/permissions.dart`.

---

## 7. Push notification (noti-server)

App ghi doc vào collection `notifications` kèm `targetRoles` mỗi khi có sự kiện. **noti-server** (Node, Admin SDK) lắng nghe realtime → gửi FCM tới đúng người theo vai trò.

```bash
cd noti-server
cp .env.example .env          # trỏ tới file service account
npm install
npm start                     # chạy nền, lắng nghe notifications
npm run test-send owner "Tiêu đề" "Nội dung"   # gửi thử
```

App phải lưu FCM token (`lib/services/push_service.dart` — tự chạy khi đăng nhập). Chi tiết: `noti-server/README.md`.

---

## 8. Cấu trúc thư mục

```
lib/
├── core/            enums (bộ trạng thái), theme, router, permissions, formatters, demo_accounts
├── models/          order, order_filter, customer, product, payment, shop_info, app_user, app_notification, audit_log
├── providers/       auth_provider
├── services/        db (Firestore gateway), auth_service, seed_service, image_service, push_service
├── features/
│   ├── auth/        login
│   ├── splash/      màn khởi động
│   ├── dashboard/   tổng quan (donut + line chart + việc cần làm)
│   ├── orders/      danh sách, tạo đơn, chi tiết, hoá đơn, thu tiền
│   ├── customers/   khách, địa chỉ, công nợ
│   ├── products/    sản phẩm, phân loại, quy cách/giá, lịch sử giá (không có danh mục)
│   ├── warehouse/   kho & đóng hàng (tab "Chờ xuất phát" có nút cho đơn đi)
│   ├── delivery/    giao hàng: chờ xuất phát / đang giao / xong hôm nay
│   │                + delivery_actions.dart (thao tác dùng chung)
│   └── more/        cài đặt, báo cáo, quản lý người dùng, nhật ký hệ thống
├── shell/           main_shell (bottom nav theo vai trò)
└── widgets/         common (StatusChip, SectionCard, KVRow, pickImage…)

noti-server/         worker Node.js gửi push FCM theo vai trò
```

---

## 9. Bảo mật

- **KHÔNG commit** service account (`*firebase-adminsdk*.json`), `.env`, keystore — đã có trong `.gitignore`.
- Nếu lỡ đẩy khóa admin lên git: **tạo khóa mới ngay** (Firebase Console → Service accounts → generate new private key), vì git giữ lịch sử.

---

## 10. MVP đã có

Đăng nhập/phân quyền · sản phẩm/giá/lịch sử giá · khách/nhiều địa chỉ/công nợ · tạo đơn (snapshot giá + địa chỉ) · in hoá đơn (preview + PDF) · kho/đóng hàng (mã kiện tự sinh) · xuất phát từng đơn hoặc cả lô · đối soát cuối ngày/thu COD · thu công nợ (FIFO nhiều đơn) · hủy đơn (hoàn tiền, đối trừ) · timeline · notification theo vai trò + push · dashboard/báo cáo · audit log · quản lý người dùng.

> Dọn dữ liệu để bàn giao: `cd noti-server && npm run wipe-orders` (xoá đơn + phiếu thu + reset công nợ, **giữ** sản phẩm/khách/tài khoản). App không còn nút "Xoá toàn bộ dữ liệu" — nút đó chỉ để test lúc dev.

**Chưa làm:** in Bluetooth thật (mới preview hoá đơn), deep-link khi bấm push, iOS APNs.

flutter build web --release
firebase deploy --only hosting
