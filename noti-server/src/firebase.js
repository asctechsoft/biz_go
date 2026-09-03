import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';
import 'dotenv/config';

const __dirname = dirname(fileURLToPath(import.meta.url));

const keyPath = resolve(
  __dirname,
  '..',
  process.env.SERVICE_ACCOUNT_PATH ||
    '../bizgo-877df-firebase-adminsdk-fbsvc-e6eb395320.json',
);

let serviceAccount;
try {
  serviceAccount = JSON.parse(readFileSync(keyPath, 'utf8'));
} catch (e) {
  console.error(`❌ Không đọc được service account: ${keyPath}`);
  console.error('   Sửa SERVICE_ACCOUNT_PATH trong .env cho đúng.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

export const db = admin.firestore();
export const messaging = admin.messaging();
export const projectId = serviceAccount.project_id;
