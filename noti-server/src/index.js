import { FieldValue } from 'firebase-admin/firestore';
import { db, projectId } from './firebase.js';
import { tokensForRoles, sendToTokens } from './fcm.js';
import 'dotenv/config';

const ONLY_NEW = (process.env.ONLY_NEW ?? 'true') !== 'false';
const START_AT = Date.now();

console.log('🚀 BizGo noti-server');
console.log(`   project: ${projectId}`);
console.log(`   mode   : ${ONLY_NEW ? 'chỉ push doc mới' : 'push cả doc chưa gửi'}`);
console.log('   Lắng nghe collection `notifications`...\n');

/**
 * Xử lý 1 notification doc: tra role → token → gửi FCM → đánh dấu pushSent.
 * Idempotent: doc đã pushSent thì bỏ qua.
 */
async function handleNotif(doc) {
  const n = doc.data();
  if (n.pushSent === true) return;

  const ref = doc.ref;
  const title = n.title || 'BizGo';
  const body = n.body || '';
  const roles = Array.isArray(n.targetRoles) ? n.targetRoles : [];

  try {
    const { tokens, tokenOwner } = await tokensForRoles(roles);
    if (tokens.length === 0) {
      await ref.update({ pushSent: true, pushedAt: Date.now(), pushCount: 0 });
      console.log(`• ${title} → [${roles.join(',')}] : không có token`);
      return;
    }

    const { successCount, failureCount } = await sendToTokens(
      tokens,
      tokenOwner,
      {
        title,
        body,
        data: {
          notifId: doc.id,
          refType: n.refType || '',
          refId: n.refId || '',
          icon: n.icon || 'bell',
        },
      },
    );

    await ref.update({
      pushSent: true,
      pushedAt: Date.now(),
      pushCount: successCount,
    });
    console.log(
      `• ${title} → [${roles.join(',')}] : gửi ${successCount}/${tokens.length}` +
        (failureCount ? ` (lỗi ${failureCount})` : ''),
    );
  } catch (e) {
    console.error(`✗ Lỗi xử lý notif ${doc.id}:`, e.message);
  }
}

// Lắng nghe 50 notif mới nhất; xử lý các doc vừa thêm.
db.collection('notifications')
  .orderBy('at', 'desc')
  .limit(50)
  .onSnapshot(
    (snap) => {
      for (const change of snap.docChanges()) {
        if (change.type !== 'added') continue;
        const n = change.doc.data();
        // Bỏ qua doc cũ khi mới khởi động để tránh spam lịch sử.
        if (ONLY_NEW && (n.at ?? 0) < START_AT) {
          if (n.pushSent !== true) {
            change.doc.ref.update({ pushSent: true }).catch(() => {});
          }
          continue;
        }
        handleNotif(change.doc);
      }
    },
    (err) => {
      console.error('✗ Lỗi listener Firestore:', err.message);
      process.exit(1);
    },
  );

process.on('SIGINT', () => {
  console.log('\n👋 Dừng noti-server.');
  process.exit(0);
});
