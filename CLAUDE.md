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

`users` · `products` · `customers` · `carriers` · `orders` · `payments` · `notifications` · `price_history` · `audit_logs` · `counters` · `meta`.

> `categories` · `vehicles` · `drivers` · `trips` là **legacy** — phân hệ chuyến xe/tài xế đã bỏ. Code không đọc/ghi nữa, chỉ còn nằm trong danh sách xoá của `Db.clearAllData` để dọn dữ liệu cũ.

- **users/{uid}:** `{name, phone, role, active, fcmTokens[], mustChangeCredentials?}`. `role` = tên enum (`owner`/`checker`/`warehouse`). `mustChangeCredentials` KHÔNG nằm trong `AppUser.toMap()` (tránh bị `set(merge)` reset) — chỉ ghi ở chỗ cố ý.
- **customers.addresses[]:** `{id, receiver, phone, address, carrierName, carrierPhone, note, mapUrl, isDefault}`. `note` = dặn dò cố định của địa chỉ ("gọi trước khi tới"), snapshot sang `order.deliveryAddressNote`. KHÔNG còn `label` ("Tên địa chỉ") — bản thân địa chỉ đã đủ nhận biết; doc cũ còn field đó thì cứ để, code không đọc tới. `carrierName`/`carrierPhone` = **nhà xe** chở hàng tới địa chỉ đó, để trống nếu giao thẳng.
- **carriers/{id}:** `{name, phone, nameLower}` — **danh mục nhà xe** (Cài đặt › Nhà xe, chỉ Chủ: `Perm.manageCarriers`). Chỉ là **sổ tay gợi ý**: form địa chỉ khách bấm chọn (`pickCarrier` trong `features/more/carriers_screen.dart`) thì điền sẵn tên + SĐT vào 2 ô, sửa lại được cho riêng địa chỉ đó. Địa chỉ khách chép ra `carrierName`/`carrierPhone`, đơn snapshot lần nữa → sửa/xoá nhà xe trong danh mục KHÔNG đổi địa chỉ đã lưu hay phiếu đã in. **Đừng** đổi sang lưu `carrierId` rồi join: số đã in phải đứng yên. Tên nhà xe unique (chặn trùng ở sheet thêm/sửa) để ô chọn không có 2 dòng y hệt.
- **orders:** snapshot `items[]` (giá tại thời điểm đặt), snapshot địa chỉ giao + nhà xe (`deliveryCarrierName`/`deliveryCarrierPhone`), `timeline[]` nhúng, các cờ trạng thái, `paidAmount`, `remaining`, `plannedDepartAt`, `cancelReason`, `pushSent`(do noti-server set).
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

- **owner:** toàn quyền — là người DUY NHẤT xem màn Tổng quan (`Perm.viewDashboard`) và đối soát giao hàng + thu tiền (`Perm.confirmDelivery`, `Perm.collectPayment`). **checker:** kho/đóng hàng/in phiếu, xem đơn, bấm **Xuất phát** (`Perm.startDelivery`). **warehouse:** chỉ thao tác kho + xem đơn.
- **Phiếu in mặc định KHÔNG có giá** (`ShopInfo.hidePrices`, lưu ở `meta/shop`, doc cũ thiếu field → `true`). Hai tầng quyết định: `Perm.viewMoney(role)` là khoá cứng (false thì không nút nào mở lại được), rồi mới tới cài đặt cửa hàng — Chủ lật cho RIÊNG lần in bằng nút trên thanh tiêu đề `InvoiceScreen`. Tham số của màn phiếu là `canSeeMoney` (**quyền**), đừng nhầm với `showMoney` của `InvoicePdf`/`downloadInvoicePdf` (**kết quả đã tính**). Thêm nút tải PDF mới ở đâu thì nhớ truyền `showMoney` đúng bằng giá trị đang hiển thị, kẻo xem bản ẩn giá mà tải ra bản đủ giá.
- **Tiền chỉ owner (`Perm.viewMoney`).** Đơn giá, thành tiền, tổng cộng, đã thu, còn thiếu, trạng thái thanh toán — ẩn hết với checker/warehouse, cả trong app lẫn **trên phiếu in**. KHÔNG có chỗ chặn chung: phải gate ở TỪNG nơi hiện tiền. Hiện đang gate ở `orders_screen` (thẻ đơn + tổng theo ngày + thanh lọc), `order_detail_screen` (dòng hàng, tổng cộng, `_PaymentCard`, chip trạng thái thanh toán), `delivery_hub_screen` (cả 3 tab — checker vào được cả 3, chỉ nút bấm bị chặn, nên phải truyền `showMoney` theo VAI TRÒ chứ đừng suy ra từ "tab này ai thao tác"), `quick_filter_screen` (bỏ ô lọc trạng thái thanh toán), `InvoiceScreen(showMoney:)` và `InvoicePdf.build(showMoney:)`. Thêm chỗ hiện `money()` mới thì nhớ gate.
- **`/dashboard` chỉ owner.** `Perm.home(role)` = tab đầu tiên, nên checker/warehouse đăng nhập vào thẳng `/orders`. Hộp thông báo `/notifications` trước đây CHỈ mở được từ màn Tổng quan → màn Đơn hàng có thêm chuông (`_NotifButton`) cho vai trò không thấy Tổng quan; bỏ nút đó đi là checker mất chỗ đọc thông báo "Đơn mới".
- Chặn 3 tầng: `Perm.tabs(role)` (bottom nav) · gate nút trong UI · `Perm.canRoute(role, loc)` (router redirect).
- **Nhiều owner được, nhưng luôn phải còn ít nhất 1.** Owner tạo tài khoản khác (kể cả owner thứ hai) qua **Quản lý người dùng** (`/users`). Tạo account dùng **FirebaseApp phụ** (`AuthService.createUserAsAdmin`) để owner không bị đăng xuất — KHÔNG tạo user bằng app chính.
- **Nhiều owner = nhiều người quản CÙNG một cửa hàng**, dùng chung toàn bộ dữ liệu. App là **single-tenant**: một Firestore = một cửa hàng, không có `tenantId` ở đâu cả. Muốn 2 cơ sở tách dữ liệu thì phải 2 Firebase project riêng, **đừng** tạo 2 owner.
- **Chặn mất quyền quản trị ở tầng `Db`** (không chỉ ở UI, vì 2 owner mở màn `/users` cùng lúc thì danh sách trên máy ai cũng còn đủ người): `deleteUser` chặn xoá chính mình + xoá owner cuối cùng; `updateUser` chặn hạ cấp owner cuối cùng; `setUserActive` chặn khoá owner đang hoạt động cuối cùng.
- `Db.ownerPhone()` (SĐT fallback in trên phiếu) phải chọn **tất định** — sắp theo uid rồi lấy đầu, vì `limit(1)` với nhiều owner sẽ trả lúc số này lúc số kia.
- **KHÔNG có tài xế/chuyến xe.** Kho đóng hàng xong bấm Xuất phát (từng đơn hoặc cả lô) → đơn sang `ON_THE_WAY`. Cuối ngày Chủ vào tab Giao hàng đối soát.
- **Đổi SĐT nhân viên** (`AuthService.changePhoneAsAdmin`, sheet Sửa người dùng): SĐT LÀ danh tính đăng nhập nên không sửa tại chỗ được — tạo account Auth mới trên **FirebaseApp phụ** + chuyển hồ sơ sang uid mới + xoá hồ sơ cũ. Chủ không biết mật khẩu nhân viên nên bắt buộc đặt mật khẩu mới. Tạo account mới TRƯỚC, xoá hồ sơ cũ SAU (SĐT mới trùng thì chưa phá gì). Account Auth cũ không xoá được từ client → **SĐT cũ bị chiếm vĩnh viễn**. Chặn đổi SĐT của **chính mình** — hồ sơ nhảy sang uid mới trong khi phiên đang chạy trỏ uid cũ đã xoá là tự khoá mình ra ngoài.
- **KHÔNG có nút "Xoá toàn bộ dữ liệu" trong app nữa** (nút cũ chỉ để test lúc dev, đã gỡ khỏi Cài đặt cùng `Db.clearAllData`). Dọn dữ liệu để bàn giao thì chạy `cd noti-server && npm run wipe-orders` — xoá `orders`/`payments`/counter mã đơn và reset công nợ cộng dồn của khách, **giữ nguyên** sản phẩm, hồ sơ khách, tài khoản. Script có danh sách trắng chốt cứng nên không thể lỡ tay xoá `customers`/`products`.
- **Xoá tài khoản:** swipe sang trái ở `/users` → `Db.deleteUser` (chặn owner + chính mình). Chỉ xoá doc Firestore; account Firebase Auth cần Admin SDK → **SĐT đã xoá không tạo lại được** (`email-already-in-use`). Để nút Xoá có hiệu lực thật, `AuthService.signIn` **từ chối** account không có hồ sơ (`account-removed`) và account `active: false` (`account-disabled`) — KHÔNG tự tạo hồ sơ mặc định như trước.
- **Thiết lập lần đầu (bắt buộc).** Tài khoản Chủ bootstrap (`0900000000`/`123456`) được tạo với `mustChangeCredentials: true` → router khoá ở `/setup-account` (`SetupAccountScreen`), phải đổi SĐT đăng nhập + mật khẩu mới vào được app. Đổi SĐT = **tạo account Auth mới + chuyển hồ sơ sang uid mới + xoá account cũ** (`AuthService.changeCredentials`), vì email `<sđt>@bizgo.local` là domain giả nên `verifyBeforeUpdateEmail` vô dụng. `signIn` chặn cửa hậu: số demo chỉ "mọc" ra Chủ khi `users` chưa có Chủ nào khác (`owner-already-exists`).

## Quy ước bắt buộc (đừng phá)

- **Tiền = `int` đồng.** Format bằng `money()` (`lib/core/formatters.dart`). Không float.
- **Khối lượng = `double` kg.** `order.weightKg` LUÔN quy về kg; `order.weightUnit` (`kg`/`tạ`/`tấn`, hệ số ở `weightUnits`) chỉ để hiển thị lại đúng đơn vị đã nhập — dùng `fmtWeight()`. Không lưu số theo đơn vị người dùng chọn.
- **Mã kiện tự sinh.** Đóng hàng xong → `Db.nextPackageCode()` cấp `KIyyMMdd-NNN` (counter `package_yyMMdd`), hiện sẵn read-only trong dialog; người dùng CHỈ nhập khối lượng + đơn vị. `order.packageCount` là **legacy** (số kiện nhập tay trước đây) — chỉ đọc để hiện đơn cũ, không ghi mới.
- **KHÔNG có tầng danh mục.** Cấu trúc là **Sản phẩm → Phân loại (variant) → Quy cách (packaging) → Giá**. Doc `products` cũ còn `categoryId`/`categoryName` thì cứ để, code không đọc tới. Tab ở bước Chọn sản phẩm là **tên sản phẩm**, mỗi tab liệt kê phân loại + quy cách của nó.
- **Sửa giá từng dòng khi tạo đơn.** Bảng giá (`Packaging.price`) chỉ là **giá mặc định**: ở bước Chọn sản phẩm / Giỏ hàng, chạm vào dòng hàng mở sheet `_lineSheet` sửa cả **số lượng** (gõ thẳng, không phải bấm +/- nhiều lần) lẫn **đơn giá**, có nút "Dùng giá bảng" để quay lại. Giá gốc nhớ trong `_listPrice` (packagingId → giá bảng) để còn biết dòng nào đã sửa tay.
- **Phân loại (`variantName`) là thứ phân biệt các dòng hàng.** Cùng sản phẩm + quy cách vẫn có nhiều phân loại giá khác nhau, nên danh sách chọn hàng và giỏ hàng lấy **phân loại làm tiêu đề** (`OrderItem.variantLabel`), sản phẩm + quy cách + giá xuống dòng dưới. Bỏ phân loại đi là mấy dòng trông y hệt nhau.
- **Snapshot:** `order_item.unitPrice`, địa chỉ giao, **nhà xe** và **ghi chú địa chỉ** chốt lúc tạo đơn — sửa bảng giá/địa chỉ/nhà xe sau KHÔNG đổi đơn cũ. Khi thêm field vào `CustomerAddress` mà đơn cần biết, phải sửa **3 chỗ**: `Order` (`delivery*`), màn tạo đơn (`draft`), **và** `Db.createOrder`. Hàm đó dựng `Order` mới từ `draft` chứ không copy cả cục, thiếu một dòng là field im lặng biến mất (đã từng mất `deliveryMapUrl` và `CustomerAddress.note` đúng kiểu này).
- **3 loại ghi chú, đừng lẫn:** `order.deliveryAddressNote` (dặn dò của địa chỉ, **lên phiếu**) · `order.deliveryNote` (ghi chú giao riêng cho đơn, **lên phiếu**) · `order.note` (ghi chú nội bộ, **KHÔNG lên phiếu**, chỉ Chủ đọc ở chi tiết đơn).
- **Payment bất biến:** mỗi lần thu = 1 doc `payments` mới. Hủy đơn có tiền → ghi payment **âm** (hoàn), không sửa/xóa payment cũ (`Db.cancelOrder`).
- **Xoá đơn ≠ hủy đơn.** `Db.deleteOrder` xoá HẲN doc (dùng cho đơn tạo nhầm), chỉ owner và chỉ khi `Db.canDelete(o)` — `NEW` + kho `WAITING` + chưa xếp giao + `paidAmount == 0` + không có doc `payments` nào bám vào. Dùng **trạng thái chứ không phải mốc thời gian**: kho nhanh tay thì 3 phút đã soạn xong hàng, còn phát hiện nhầm sau nửa tiếng mà chưa ai động vào thì xoá vẫn an toàn. Phải gỡ đúng 4 field đã cộng vào `customers` lúc tạo (`orderCount`/`totalPurchased`/`totalPaid`/`debt`) và ghi `audit_logs` kèm **toàn bộ doc đơn** — xoá rồi thì nhật ký là chỗ duy nhất tra lại được. Đơn đã vào quy trình hoặc đã thu tiền → phải `cancelOrder` để còn payment hoàn.
- **`Db.order(id)` trả `Stream<Order?>`** — đừng `data()!`. Đơn bị xoá lúc màn chi tiết đang mở (hoặc mở từ thông báo cũ) sẽ crash null-check; màn chi tiết phân biệt "đang tải" bằng `ConnectionState.waiting`, `null` = đơn không còn.
- **Sửa đơn (`Db.editOrder`)** — chỉ khi đơn **chưa xuất phát** và chưa hủy, chỉ owner (`Perm.editOrder`). Sửa được: mặt hàng / số lượng / giá / phí giao / giảm giá / ghi chú / giờ xuất phát. **KHÔNG** sửa: khách, địa chỉ, `prepaid`, `paidAmount`, `paymentStatus` do người dùng chốt (COD/DEBT/REFUNDED) — tiền đã thu là bất biến. Khi tổng đơn đổi phải chỉnh **đồng thời** `remaining`, `paymentStatus` suy lại, và `customers.totalPurchased`/`debt` theo đúng phần chênh (kẹp 0 như `cancelOrder`) — thiếu một vế là sổ công nợ sai câm. Chạy trong transaction + đọc lại đơn trước khi ghi để không đè lên thay đổi của người khác.
- **Màn tạo đơn kiêm màn sửa đơn.** `CreateOrderScreen(editing: order)` → bỏ 2 bước chọn khách/địa chỉ, vào thẳng bước Sản phẩm với giỏ đổ từ đơn cũ. Đừng viết màn sửa riêng, phần chọn hàng + sửa giá + giỏ hàng y hệt nhau.
- **Chuyển trạng thái** → append timeline + `_audit()` + `_notify()` (xem các method trong `Db`).
- **Thứ tự đi = GẤP trước, rồi tới giờ.** `order.plannedDepartAt` (giờ dự kiến xuất phát, người tạo đơn đặt ở bước Xác nhận) có thể `null`; đừng đọc thẳng nó để sắp xếp mà dùng `order.departAt` (`plannedDepartAt ?? createdAt`) và `Order.byDepartOrder` — MỌI danh sách hàng đợi (kho, giao hàng, tab Đơn hàng) phải xếp bằng đúng comparator này, xếp lệch nhau là kho làm sai thứ tự. Đổi giờ sau khi tạo qua `Db.setPlannedDepart`, chỉ được khi đơn CHƯA đi.
- **Xuất phát ở tầng `Db`.** `Db.departOrder` (1 đơn) / `Db.departOrders` (cả lô, 1 batch) — kiểm `PACKED` + chưa đi + chưa hủy ngay trong `Db`, đừng chỉ chặn ở UI. Bấm lại đơn đã đi thì bỏ qua (không sinh timeline rác). Thao tác UI dùng chung ở `lib/features/delivery/delivery_actions.dart` (`departOrder` / `departAllOrders` / `deliverOrder` / `failOrder`) — sửa nghiệp vụ giao hàng thì sửa ở đó, đừng chép lại vào từng màn.
- **Ảnh lưu local** máy (`ImageService`), Firestore chỉ giữ path. Đổi máy/cài lại = mất ảnh (đúng thiết kế).
- Widget dùng lại: `StatusChip`, `SectionCard`, `KVRow`, `EmptyState`, `Avatar`, `pickImage()`, `confirmDialog()`, `toast()` trong `lib/widgets/common.dart`. Màu ở `AppColors` (`lib/core/theme.dart`).

## Luồng chính

Tạo đơn (owner; bước Xác nhận chọn **giờ xuất phát dự kiến**, để trống thì xếp theo giờ tạo) → notify checker → kho: WAITING→PREPARING→PREPARED→**PACKING**→PACKED → **Xuất phát** (owner/checker, bấm từng đơn hoặc "Xuất phát tất cả" ở tab Kho › Chờ xuất phát hoặc tab Giao hàng › Chờ xuất phát) → `ON_THE_WAY` → **cuối ngày owner đối soát** ở tab Giao hàng › Đang giao: Giao thành công (mở sheet thu tiền, tạo payment) hoặc Không giao được (FAILED/RESCHEDULED/RETURNED; RESCHEDULED quay lại danh sách chờ xuất phát) → công nợ còn lại thu sau (FIFO nhiều đơn qua `Db.collectCustomerDebt`).

Màn `/delivery` (`DeliveryHubScreen`) 3 tab: **Chờ xuất phát** (`Db.ordersWaitingDepart`) · **Đang giao** (`Db.ordersDelivering`, kèm tổng tiền cần thu) · **Xong hôm nay** (`Db.ordersSettledOn`).

## Gotchas

- **Login fail** thường do Firebase **chưa bật Email/Password** hoặc Firestore rules khóa. `AuthProvider.signIn` in `SIGN-IN ERROR:` ra console. `invalid-credential` với account demo → app tự tạo (mật khẩu `123456`).
- **Nút cuối trang bị thanh nav Android che.** `Scaffold` CHỈ tự trừ inset đáy khi có `bottomNavigationBar`; màn nào không có mà lại kết bằng nút thì phải tự cộng `MediaQuery.of(context).padding.bottom` vào padding đáy của `ListView`/`SliverToBoxAdapter` (hoặc bọc `SafeArea`). Không có nó thì cuộn hết cỡ vẫn không bấm được nút — đã dính ở chi tiết sản phẩm, chi tiết phân loại, Lọc nhanh, Cài đặt phiếu, màn phiếu.
- **UI trong ListView:** Row chứa Column dễ crash "unbounded height" — đặt `mainAxisSize: MainAxisSize.min`, tránh `crossAxisAlignment.stretch`.
- **Dropdown trong bottom sheet** hay bung ngược/đè → dùng `_selectField` + `_pickFromList` (bottom sheet chọn) thay `DropdownButtonFormField`.
- **Toast bị modal sheet che** → validate trong sheet bằng banner đỏ inline (`setSheet(() => error = ...)`), không dùng `toast`.
- **Model dùng trong Dropdown** cần override `==`/`hashCode` theo `id` vì stream tạo instance mới.
- **`fl_chart`** cần chiều cao bounded (bọc `SizedBox`).
- **Widget hệ thống ra tiếng Anh** (date/time picker, nút Cancel/OK, menu sao chép-dán) → thiếu `flutter_localizations`. `main.dart` đã khoá `locale: Locale('vi')` + 3 `GlobalXxxLocalizations.delegate`; đừng bỏ. Time picker bị ép 24h qua `MediaQuery(alwaysUse24HourFormat: true)` trong `builder` của `MaterialApp` cho khớp `fmtTime` (`HH:mm`).

## Dung lượng bản build

- **Debug nặng ~150MB là bình thường**, không phải app phình. Bóc APK debug ra: `kernel_blob.bin` (mã Dart dạng JIT) ~84MB + `libflutter.so` bản debug ~36MB + `isolate_snapshot_data` ~10MB + dex chưa qua R8 ~25MB. Assets của app chỉ ~1MB, tối ưu ảnh/font gần như vô nghĩa ở đây.
- **Đã gỡ `libVkLayer_khronos_validation.so`** (15.25MB) trong `android/app/build.gradle.kts` → `packaging.jniLibs.excludes`. **Đo thực tế: file `.apk` KHÔNG nhỏ đi** (165.321.799 → 165.321.707 byte) dù archive mất đúng 15.25MB nội dung — APK debug dư rất nhiều khoảng đệm. Giữ vì bớt mã native vô ích lúc cài, nhưng đừng dùng nó để hy vọng giảm dung lượng.
- **Debug mặc định build CẢ 3 ABI** (~103MB riêng phần native). Test trên máy thật thì thêm `--target-platform android-arm64`. `flutter run` vốn đã chỉ build ABI của máy đang cắm — đừng so dung lượng APK của `flutter run` với `flutter build apk --debug`, hai thứ khác nhau.
- **Giao bản cho người khác dùng thì đừng đưa debug** — `flutter build apk --release --split-per-abi`, bản arm64 nhỏ hơn ~6-7 lần.

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
