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

`users` · `categories` · `products` · `customers` · `orders` · `payments` · `notifications` · `price_history` · `audit_logs` · `counters` · `meta`.

> `vehicles` · `drivers` · `trips` là **legacy** — phân hệ chuyến xe/tài xế đã bỏ. Code không đọc/ghi nữa, chỉ còn nằm trong danh sách xoá của `Db.clearAllData` để dọn dữ liệu cũ.

- **users/{uid}:** `{name, phone, role, active, fcmTokens[], mustChangeCredentials?}`. `role` = tên enum (`owner`/`checker`/`warehouse`). `mustChangeCredentials` KHÔNG nằm trong `AppUser.toMap()` (tránh bị `set(merge)` reset) — chỉ ghi ở chỗ cố ý.
- **orders:** snapshot `items[]` (giá tại thời điểm đặt), snapshot địa chỉ giao, `timeline[]` nhúng, các cờ trạng thái, `paidAmount`, `remaining`, `cancelReason`, `pushSent`(do noti-server set).
- **notifications:** `{title, body, targetRoles[], refType, refId, at, read, icon, pushSent}` — noti-server đọc để push.
- **counters/{kind_yyMMdd}:** sinh mã đơn `DHyyMMdd-NNN`, mã kiện `KIyyMMdd-NNN` (transaction).

> Query **tránh composite index**: lọc bằng `where` rồi `.sort()` trong Dart. Giữ nguyên kiểu này khi thêm query mới.

## Bộ trạng thái (`lib/core/enums.dart`, spec §18)

- `OrderStatus`: NEW · CONFIRMED · PROCESSING · COMPLETED · CANCELLED
- `WarehouseStatus`: WAITING · PREPARING · PREPARED · PACKING · PACKED
- `DeliveryStatus`: WAITING_ASSIGNMENT (nhãn "Chờ xuất phát") · ON_THE_WAY · DELIVERED · FAILED · RESCHEDULED · RETURNED. **ASSIGNED · LOADING · ARRIVED là legacy** của luồng chuyến xe cũ — chỉ đọc cho đơn cũ, KHÔNG ghi mới. Ô lọc dùng `deliveryStatusFilterValues`.
- `PaymentStatus`: UNPAID · PARTIAL · PAID · REFUNDED · COD · DEBT
- **`UserRole`: owner (Chủ) · checker (Kiểm hàng) · warehouse (Kiểm kho)** — CHỈ 3 vai trò, KHÔNG còn `shipper`. `roleFromName` fallback về `warehouse` (quyền thấp nhất), nên hồ sơ cũ còn `role: 'shipper'` tự rơi về Kiểm kho.

Enum lưu Firestore bằng `.name`. Nhãn tiếng Việt + màu qua các hàm `*StatusUi()`.

## RBAC (`lib/core/permissions.dart` — class `Perm`)

- **owner:** toàn quyền — là người DUY NHẤT đối soát giao hàng + thu tiền (`Perm.confirmDelivery`, `Perm.collectPayment`). **checker:** kho/đóng hàng/in phiếu, xem đơn, bấm **Xuất phát** (`Perm.startDelivery`). **warehouse:** chỉ thao tác kho + xem đơn.
- Chặn 3 tầng: `Perm.tabs(role)` (bottom nav) · gate nút trong UI · `Perm.canRoute(role, loc)` (router redirect).
- **Nhiều owner được, nhưng luôn phải còn ít nhất 1.** Owner tạo tài khoản khác (kể cả owner thứ hai) qua **Quản lý người dùng** (`/users`). Tạo account dùng **FirebaseApp phụ** (`AuthService.createUserAsAdmin`) để owner không bị đăng xuất — KHÔNG tạo user bằng app chính.
- **Nhiều owner = nhiều người quản CÙNG một cửa hàng**, dùng chung toàn bộ dữ liệu. App là **single-tenant**: một Firestore = một cửa hàng, không có `tenantId` ở đâu cả. Muốn 2 cơ sở tách dữ liệu thì phải 2 Firebase project riêng, **đừng** tạo 2 owner.
- **Chặn mất quyền quản trị ở tầng `Db`** (không chỉ ở UI, vì 2 owner mở màn `/users` cùng lúc thì danh sách trên máy ai cũng còn đủ người): `deleteUser` chặn xoá chính mình + xoá owner cuối cùng; `updateUser` chặn hạ cấp owner cuối cùng; `setUserActive` chặn khoá owner đang hoạt động cuối cùng.
- `Db.ownerPhone()` (SĐT fallback in trên phiếu) phải chọn **tất định** — sắp theo uid rồi lấy đầu, vì `limit(1)` với nhiều owner sẽ trả lúc số này lúc số kia.
- **KHÔNG có tài xế/chuyến xe.** Kho đóng hàng xong bấm Xuất phát (từng đơn hoặc cả lô) → đơn sang `ON_THE_WAY`. Cuối ngày Chủ vào tab Giao hàng đối soát.
- **Xoá tài khoản:** swipe sang trái ở `/users` → `Db.deleteUser` (chặn owner + chính mình). Chỉ xoá doc Firestore; account Firebase Auth cần Admin SDK → **SĐT đã xoá không tạo lại được** (`email-already-in-use`). Để nút Xoá có hiệu lực thật, `AuthService.signIn` **từ chối** account không có hồ sơ (`account-removed`) và account `active: false` (`account-disabled`) — KHÔNG tự tạo hồ sơ mặc định như trước.
- **Thiết lập lần đầu (bắt buộc).** Tài khoản Chủ bootstrap (`0900000000`/`123456`) được tạo với `mustChangeCredentials: true` → router khoá ở `/setup-account` (`SetupAccountScreen`), phải đổi SĐT đăng nhập + mật khẩu mới vào được app. Đổi SĐT = **tạo account Auth mới + chuyển hồ sơ sang uid mới + xoá account cũ** (`AuthService.changeCredentials`), vì email `<sđt>@bizgo.local` là domain giả nên `verifyBeforeUpdateEmail` vô dụng. `signIn` chặn cửa hậu: số demo chỉ "mọc" ra Chủ khi `users` chưa có Chủ nào khác (`owner-already-exists`).

## Quy ước bắt buộc (đừng phá)

- **Tiền = `int` đồng.** Format bằng `money()` (`lib/core/formatters.dart`). Không float.
- **Khối lượng = `double` kg.** `order.weightKg` LUÔN quy về kg; `order.weightUnit` (`kg`/`tạ`/`tấn`, hệ số ở `weightUnits`) chỉ để hiển thị lại đúng đơn vị đã nhập — dùng `fmtWeight()`. Không lưu số theo đơn vị người dùng chọn.
- **Mã kiện tự sinh.** Đóng hàng xong → `Db.nextPackageCode()` cấp `KIyyMMdd-NNN` (counter `package_yyMMdd`), hiện sẵn read-only trong dialog; người dùng CHỈ nhập khối lượng + đơn vị. `order.packageCount` là **legacy** (số kiện nhập tay trước đây) — chỉ đọc để hiện đơn cũ, không ghi mới.
- **Snapshot:** `order_item.unitPrice` và địa chỉ giao chốt lúc tạo đơn — sửa bảng giá/địa chỉ sau KHÔNG đổi đơn cũ.
- **Payment bất biến:** mỗi lần thu = 1 doc `payments` mới. Hủy đơn có tiền → ghi payment **âm** (hoàn), không sửa/xóa payment cũ (`Db.cancelOrder`).
- **Chuyển trạng thái** → append timeline + `_audit()` + `_notify()` (xem các method trong `Db`).
- **Xuất phát ở tầng `Db`.** `Db.departOrder` (1 đơn) / `Db.departOrders` (cả lô, 1 batch) — kiểm `PACKED` + chưa đi + chưa hủy ngay trong `Db`, đừng chỉ chặn ở UI. Bấm lại đơn đã đi thì bỏ qua (không sinh timeline rác). Thao tác UI dùng chung ở `lib/features/delivery/delivery_actions.dart` (`departOrder` / `departAllOrders` / `deliverOrder` / `failOrder`) — sửa nghiệp vụ giao hàng thì sửa ở đó, đừng chép lại vào từng màn.
- **Ảnh lưu local** máy (`ImageService`), Firestore chỉ giữ path. Đổi máy/cài lại = mất ảnh (đúng thiết kế).
- Widget dùng lại: `StatusChip`, `SectionCard`, `KVRow`, `EmptyState`, `Avatar`, `pickImage()`, `confirmDialog()`, `toast()` trong `lib/widgets/common.dart`. Màu ở `AppColors` (`lib/core/theme.dart`).

## Luồng chính

Tạo đơn (owner) → notify checker → kho: WAITING→PREPARING→PREPARED→**PACKING**→PACKED → **Xuất phát** (owner/checker, bấm từng đơn hoặc "Xuất phát tất cả" ở tab Kho › Chờ xuất phát hoặc tab Giao hàng › Chờ xuất phát) → `ON_THE_WAY` → **cuối ngày owner đối soát** ở tab Giao hàng › Đang giao: Giao thành công (mở sheet thu tiền, tạo payment) hoặc Không giao được (FAILED/RESCHEDULED/RETURNED; RESCHEDULED quay lại danh sách chờ xuất phát) → công nợ còn lại thu sau (FIFO nhiều đơn qua `Db.collectCustomerDebt`).

Màn `/delivery` (`DeliveryHubScreen`) 3 tab: **Chờ xuất phát** (`Db.ordersWaitingDepart`) · **Đang giao** (`Db.ordersDelivering`, kèm tổng tiền cần thu) · **Xong hôm nay** (`Db.ordersSettledOn`).

## Gotchas

- **Login fail** thường do Firebase **chưa bật Email/Password** hoặc Firestore rules khóa. `AuthProvider.signIn` in `SIGN-IN ERROR:` ra console. `invalid-credential` với account demo → app tự tạo (mật khẩu `123456`).
- **UI trong ListView:** Row chứa Column dễ crash "unbounded height" — đặt `mainAxisSize: MainAxisSize.min`, tránh `crossAxisAlignment.stretch`.
- **Dropdown trong bottom sheet** hay bung ngược/đè → dùng `_selectField` + `_pickFromList` (bottom sheet chọn) thay `DropdownButtonFormField`.
- **Toast bị modal sheet che** → validate trong sheet bằng banner đỏ inline (`setSheet(() => error = ...)`), không dùng `toast`.
- **Model dùng trong Dropdown** cần override `==`/`hashCode` theo `id` vì stream tạo instance mới.
- **`fl_chart`** cần chiều cao bounded (bọc `SizedBox`).
- **Widget hệ thống ra tiếng Anh** (date/time picker, nút Cancel/OK, menu sao chép-dán) → thiếu `flutter_localizations`. `main.dart` đã khoá `locale: Locale('vi')` + 3 `GlobalXxxLocalizations.delegate`; đừng bỏ. Time picker bị ép 24h qua `MediaQuery(alwaysUse24HourFormat: true)` trong `builder` của `MaterialApp` cho khớp `fmtTime` (`HH:mm`).

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

> Thông báo cũ có `refType: 'trip'` thì bấm vào KHÔNG mở gì (màn chuyến đã xoá) — `NotifRefType.trip` giữ lại chỉ để parse doc cũ.
