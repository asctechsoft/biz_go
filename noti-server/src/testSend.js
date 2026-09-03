import { db, projectId } from './firebase.js';

/**
 * Tạo 1 notification thử để kiểm tra pipeline.
 * Dùng: node src/testSend.js <role> "Tiêu đề" "Nội dung"
 * role: owner | checker | shipper
 */
const [, , role = 'owner', title = 'Thử BizGo', body = 'Push hoạt động 🎉'] =
  process.argv;

const doc = {
  title,
  body,
  refType: 'order',
  refId: 'test',
  targetRoles: [role],
  at: Date.now(),
  read: false,
  icon: 'bell',
  pushSent: false,
};

const ref = await db.collection('notifications').add(doc);
console.log(`✅ Đã tạo notif ${ref.id} cho role "${role}" (project ${projectId}).`);
console.log('   Nếu noti-server đang chạy, push sẽ được gửi ngay.');
process.exit(0);
