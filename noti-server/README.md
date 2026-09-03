# BizGo Noti Server

Worker Node.js: lắng nghe collection `notifications` trên Firestore → gửi **push FCM** tới đúng người theo **vai trò** (owner / checker / shipper).

App BizGo đã ghi notification kèm `targetRoles` mỗi khi có sự kiện (đơn mới, đóng hàng xong, gán chuyến, giao hàng, công nợ...). Server này biến các doc đó thành push thật.

## Luồng

```
App ghi doc notifications { title, body, targetRoles:[...], refType, refId }
        ↓ (onSnapshot realtime)
noti-server: role → tìm users có role đó → gom fcmTokens → gửi FCM
        ↓
Điện thoại nhận push, bấm vào → app deep-link tới refType/refId
```

## Cài đặt

```bash
cd noti-server
cp .env.example .env      # sửa đường dẫn service account nếu cần
npm install
npm start
```

- `npm run dev` — tự reload khi sửa code.
- `npm run test-send owner "Tiêu đề" "Nội dung"` — tạo 1 notif thử (server đang chạy sẽ push ngay).

## Cấu hình `.env`

| Biến | Mặc định | Ý nghĩa |
|------|----------|---------|
| `SERVICE_ACCOUNT_PATH` | `../bizgo-877df-firebase-adminsdk-...json` | File Admin SDK |
| `ONLY_NEW` | `true` | `true` = chỉ push doc tạo sau khi server start (tránh spam lịch sử) |

## Điều kiện phía APP (bắt buộc để có token)

Server chỉ gửi được nếu mỗi user có `fcmTokens` trong `users/{uid}`. App phải:

1. Xin quyền + lấy FCM token (`firebase_messaging`).
2. Lưu vào `users/{uid}.fcmTokens` (arrayUnion) khi đăng nhập.
3. Xoá token khi đăng xuất.

> Phần này nằm ở app Flutter (`lib/services/push_service.dart`). Nếu chưa có, báo để thêm.

## Dữ liệu 1 doc `notifications`

```jsonc
{
  "title": "Đơn mới DH260903-001",
  "body": "Khoai lang mật 1kg",
  "targetRoles": ["checker"],   // owner | checker | shipper
  "refType": "order",            // order | trip | customer | debt
  "refId": "<doc id>",
  "at": 1725360000000,
  "read": false,
  "icon": "new",
  "pushSent": false              // server set true sau khi gửi (idempotent)
}
```

## Chạy nền / deploy

- Máy chủ luôn bật: dùng `pm2 start src/index.js --name bizgo-noti`.
- Hoặc chuyển logic sang **Cloud Functions** (trigger `onCreate` collection `notifications`) nếu không muốn nuôi server riêng.
