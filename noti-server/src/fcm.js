import { FieldValue } from 'firebase-admin/firestore';
import { db, messaging } from './firebase.js';

/**
 * Lấy toàn bộ FCM token của những user có role nằm trong targetRoles.
 * Trả về { tokens: string[], tokenOwner: Map<token, uid> } để dọn token hỏng.
 */
export async function tokensForRoles(targetRoles) {
  const tokenOwner = new Map();
  if (!Array.isArray(targetRoles) || targetRoles.length === 0) {
    return { tokens: [], tokenOwner };
  }
  // Firestore `in` tối đa 30 phần tử — role của ta chỉ có 3 nên an toàn.
  const snap = await db
    .collection('users')
    .where('role', 'in', targetRoles)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data();
    const list = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    for (const t of list) {
      if (typeof t === 'string' && t.length > 0 && !tokenOwner.has(t)) {
        tokenOwner.set(t, doc.id);
      }
    }
  }
  return { tokens: [...tokenOwner.keys()], tokenOwner };
}

/**
 * Gửi push tới nhiều token. Tự dọn các token không còn hợp lệ khỏi user doc.
 * @returns {Promise<{successCount:number, failureCount:number}>}
 */
export async function sendToTokens(tokens, tokenOwner, { title, body, data }) {
  if (tokens.length === 0) return { successCount: 0, failureCount: 0 };

  const message = {
    tokens,
    notification: { title, body },
    // data phải toàn string — app đọc để deep-link tới đúng đối tượng.
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v ?? '')]),
    ),
    android: {
      priority: 'high',
      notification: { sound: 'default' },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  };

  const res = await messaging.sendEachForMulticast(message);

  // Dọn token hỏng (unregistered / invalid).
  const dead = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error?.code || '';
      if (
        code.includes('registration-token-not-registered') ||
        code.includes('invalid-registration-token') ||
        code.includes('invalid-argument')
      ) {
        dead.push(tokens[i]);
      }
    }
  });
  if (dead.length) await removeTokens(dead, tokenOwner);

  return { successCount: res.successCount, failureCount: res.failureCount };
}

async function removeTokens(deadTokens, tokenOwner) {
  // Gom theo uid rồi arrayRemove.
  const byUser = new Map();
  for (const t of deadTokens) {
    const uid = tokenOwner.get(t);
    if (!uid) continue;
    if (!byUser.has(uid)) byUser.set(uid, []);
    byUser.get(uid).push(t);
  }
  const batch = db.batch();
  for (const [uid, toks] of byUser) {
    batch.update(db.collection('users').doc(uid), {
      fcmTokens: FieldValue.arrayRemove(...toks),
    });
  }
  if (byUser.size) {
    await batch.commit();
    console.log(`  🧹 Dọn ${deadTokens.length} token hỏng.`);
  }
}
