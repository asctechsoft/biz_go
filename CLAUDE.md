# CLAUDE.md

Hướng dẫn cho AI/dev khi làm việc trong repo này. Đọc trước khi sửa code.

## Là gì

App mobile **BizGo** — quản lý bán hàng / giao hàng / công nợ. **Flutter + Firebase (Auth email-password + Firestore)**. Không có backend riêng ngoài `noti-server/` (Node worker gửi push FCM). Nghiệp vụ gốc: `Dac_ta_nghiep_vu_App_Ban_Hang_Giao_Hang_Mobile.docx`.

## Kiến trúc

- **State:** `provider`. Chỉ có `AuthProvider` (ChangeNotifier). Còn lại đọc dữ liệu trực tiếp qua **StreamBuilder** từ `Db`.
- **Điều hướng:** `go_router` (`lib/core/router.dart`). `redirect` xử lý splash → login → home theo vai trò + chặn route ngoài quyền.
- **Data gateway:** **mọi** truy cập Firestore đi qua `lib/services/db.dart` (class `Db`, provider). Không gọi Firestore rải rác trong UI. Các hành động nghiệp vụ (tạo đơn, thu tiền, chuyển trạng thái, hủy đơn) chạy trong **transaction** và luôn append timeline + tạo notification.
- **Auth:** `lib/services/auth_service.dart`. Login bằng SĐT → map `<số>@bizgo.local`. `AuthProvider` giữ `AppUser` (có `role`).

## Firestore collections

`users` · `categories` · `products` · `customers` · `orders` · `payments` · `vehicles` · `drivers`(legacy, không dùng cho điều phối nữa) · `trips` · `notifications` · `price_history` · `audit_logs` · `counters` · `meta`.

- **users/{uid}:** `{name, phone, role, active, fcmTokens[]}`. `role` = tên enum (`owner`/`checker`/`shipper`).
- **orders:** snapshot `items[]` (giá tại thời điểm đặt), snapshot địa chỉ giao, `timeline[]` nhúng, các cờ trạng thái, `paidAmount`, `remaining`, `tripId`, `sequence`, `cancelReason`, `pushSent`(do noti-server set).
- **trips:** `driverId = uid tài khoản Giao hàng` (app tài xế lọc theo đây), `vehicleId/plate`, `driverName/phone`, `status`, counts.
- **notifications:** `{title, body, targetRoles[], refType, refId, at, read, icon, pushSent}` — noti-server đọc để push.
- **counters/{kind_yyMMdd}:** sinh mã đơn `DHyyMMdd-NNN`, chuyến `CXyyMMdd-NN` (transaction).

> Query **tránh composite index**: lọc bằng `where` rồi `.sort()` trong Dart. Giữ nguyên kiểu này khi thêm query mới.

## Bộ trạng thái (`lib/core/enums.dart`, spec §18)

- `OrderStatus`: NEW · CONFIRMED · PROCESSING · COMPLETED · CANCELLED
- `WarehouseStatus`: WAITING · PREPARING · PREPARED · PACKING · PACKED
- `DeliveryStatus`: WAITING_ASSIGNMENT · ASSIGNED · LOADING · ON_THE_WAY · ARRIVED · DELIVERED · FAILED · RESCHEDULED · RETURNED
- `PaymentStatus`: UNPAID · PARTIAL · PAID · REFUNDED · COD · DEBT
- `TripStatus`: DRAFT · READY · IN_PROGRESS · COMPLETED · CANCELLED
- **`UserRole`: owner (Chủ) · checker (Kiểm hàng) · shipper (Giao hàng)** — CHỈ 3 vai trò. `roleFromName` fallback về `shipper` (quyền thấp nhất).

Enum lưu Firestore bằng `.name`. Nhãn tiếng Việt + màu qua các hàm `*StatusUi()`.

## RBAC (`lib/core/permissions.dart` — class `Perm`)

- **owner:** toàn quyền. **checker:** kho/đóng hàng/in phiếu, xem đơn. **shipper:** chuyến của mình, giao, thu COD.
- Chặn 3 tầng: `Perm.tabs(role)` (bottom nav) · gate nút trong UI · `Perm.canRoute(role, loc)` (router redirect).
- **Chỉ 1 owner.** Owner tạo tài khoản khác qua **Quản lý người dùng** (`/users`). Tạo account dùng **FirebaseApp phụ** (`AuthService.createUserAsAdmin`) để owner không bị đăng xuất — KHÔNG tạo user bằng app chính.
- **Tài xế = account role shipper.** `trip.driverId = uid`. `delivery_hub` lọc `db.tripsForDriver(uid)` cho shipper.

## Quy ước bắt buộc (đừng phá)

- **Tiền = `int` đồng.** Format bằng `money()` (`lib/core/formatters.dart`). Không float.
- **Snapshot:** `order_item.unitPrice` và địa chỉ giao chốt lúc tạo đơn — sửa bảng giá/địa chỉ sau KHÔNG đổi đơn cũ.
- **Payment bất biến:** mỗi lần thu = 1 doc `payments` mới. Hủy đơn có tiền → ghi payment **âm** (hoàn), không sửa/xóa payment cũ (`Db.cancelOrder`).
- **Chuyển trạng thái** → append timeline + `_audit()` + `_notify()` (xem các method trong `Db`).
- **Ảnh lưu local** máy (`ImageService`), Firestore chỉ giữ path. Đổi máy/cài lại = mất ảnh (đúng thiết kế).
- Widget dùng lại: `StatusChip`, `SectionCard`, `KVRow`, `EmptyState`, `Avatar`, `pickImage()`, `confirmDialog()`, `toast()` trong `lib/widgets/common.dart`. Màu ở `AppColors` (`lib/core/theme.dart`).

## Luồng chính

Tạo đơn (owner) → notify checker → kho: WAITING→PREPARING→PREPARED→**PACKING**→PACKED → notify owner → điều phối tạo chuyến (chọn xe + tài xế-account) → gán đơn PACKED (chặn nếu chưa PACKED / đã ở chuyến khác) → xuất phát (ON_THE_WAY) → tài xế: Đã tới → Giao thành công (mở sheet thu tiền, tạo payment) hoặc Không giao được (FAILED/RESCHEDULED/RETURNED) → công nợ còn lại thu sau (FIFO nhiều đơn qua `Db.collectCustomerDebt`).

## Gotchas

- **Login fail** thường do Firebase **chưa bật Email/Password** hoặc Firestore rules khóa. `AuthProvider.signIn` in `SIGN-IN ERROR:` ra console. `invalid-credential` với account demo → app tự tạo (mật khẩu `123456`).
- **UI trong ListView:** Row chứa Column dễ crash "unbounded height" — đặt `mainAxisSize: MainAxisSize.min`, tránh `crossAxisAlignment.stretch`.
- **Dropdown trong bottom sheet** hay bung ngược/đè → dùng `_selectField` + `_pickFromList` (bottom sheet chọn) thay `DropdownButtonFormField`.
- **Toast bị modal sheet che** → validate trong sheet bằng banner đỏ inline (`setSheet(() => error = ...)`), không dùng `toast`.
- **Model dùng trong Dropdown** cần override `==`/`hashCode` theo `id` (xem `Vehicle`/`Driver`) vì stream tạo instance mới.
- **`fl_chart`** cần chiều cao bounded (bọc `SizedBox`).

## Lệnh hay dùng

```bash
flutter analyze                              # luôn chạy sau khi sửa
flutter run                                  # debug
flutter build apk --release --split-per-abi  # APK phát hành
dart run flutter_launcher_icons              # đổi icon từ assets/images/logo_app.png
cd noti-server && npm start                  # worker push
```

> Trên Windows, `flutter analyze` trả exit code ≠ 0 kể cả khi chỉ có lint `info`. Lọc dòng chứa ` error ` / ` warning ` để biết có lỗi thật không.

## Bảo mật

KHÔNG commit `*firebase-adminsdk*.json`, `.env`, keystore (đã trong `.gitignore`). `google-services.json` (client) thì có commit — cần để build.

## Chưa làm

In Bluetooth thật (mới có preview hoá đơn `InvoiceScreen`) · deep-link khi bấm push · iOS APNs.
