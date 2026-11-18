/*
 * SC-00 | Setup — Master Control Tabs
 * ------------------------------------------------------------------
 * سير لمرة واحدة ينشئ التبويبات الثلاثة الناقصة ويكتب رؤوسها:
 *   حزم النشر · طابور النشر اليدوي · سجل الأتمتة
 *
 * إضافة فقط. لا يحذف ولا يعيد تسمية ولا يعدّل أي تبويب قائم (§33).
 *
 * قيود محلّل الـSDK (مكتشفة بالتجربة، لا بالافتراض):
 *   - لا يقبل تعليقات أنواع TypeScript رغم وصف الأداة.
 *   - لا يقبل تعريف دوال إطلاقًا — كل عقدة تُكتب صراحةً.
 * لذلك هذا الملف مُسهَب عمدًا.
 *
 * DOCUMENT_ID يشير إلى جدول اختبار مؤقت؛ يُستبدل بـMaster Control
 * بعد التحقق من أن الرؤوس تهبط صحيحة.
 */

import { workflow, node, trigger, sticky, newCredential } from '@n8n/workflow-sdk';

const DOCUMENT_ID = '1Hz1MJv5nkQsB40OSVH3HP8B-R0d784xgABtc_F8TZEk';
const SHEETS_CRED = newCredential('Google Sheets account', 'iBpuwxBvaElSkrED');

const start = trigger({
  type: 'n8n-nodes-base.manualTrigger',
  version: 1,
  config: { name: '01 — Run Setup Once' }
});

const createPackages = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '02 — Create Tab: حزم النشر',
    parameters: {
      resource: 'sheet',
      operation: 'create',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      title: 'حزم النشر',
      options: { rightToLeft: true }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000,
    notes: 'ينشئ تبويبًا جديدًا فقط. لا يمس أي تبويب قائم.'
  }
});

const seedPackage = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: '03 — Seed FOUNDATION-001 Package',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `// النصوص المعتمدة حرفيًا من حزمة النشر. ممنوع تعديلها علميًا.
const NL = String.fromCharCode(10);

const caption = [
  '🧪 كيف نفهم العدد الذري؟', '',
  'لكل عنصر عدد ذري خاص به يميزه عن العناصر الأخرى.', '',
  'العدد الذري يساوي عدد البروتونات الموجودة في نواة العنصر.', '',
  'وفي الذرة المتعادلة فقط يساوي عدد الإلكترونات عدد البروتونات.', '',
  'لذلك إذا كان العدد الذري للصوديوم Na = 11:', '',
  'عدد البروتونات = 11', '',
  'وفي الذرة المتعادلة: عدد الإلكترونات = 11', '',
  '✨ الخلاصة:',
  'اعرف عدد البروتونات تعرف العدد الذري.', '',
  'احفظ المنشور للرجوع إليه أثناء المراجعة، وشاركه مع زميل يحتاج تثبيت الأساسيات قبل البناء الإلكتروني.', '',
  '#شغف_الكيمياء #كيمياء #توجيهي'
].join(NL);

const pinned = [
  '🧠 اختبار سريع:', '',
  'إذا كان العدد الذري للصوديوم 11:', '',
  'كم عدد البروتونات؟', '',
  'وكم عدد الإلكترونات إذا كانت الذرة متعادلة؟', '',
  'اكتب إجابتك 👇'
].join(NL);

const altText = 'كاروسيل تعليمي من شغف الكيمياء بعنوان «كيف نفهم العدد الذري؟». يوضح أن العدد الذري يساوي عدد البروتونات الموجودة في نواة العنصر، وأنه في الذرة المتعادلة فقط يساوي أيضًا عدد الإلكترونات. ويعرض مثال الصوديوم Na ذي العدد الذري 11.';

return [{ json: {
  'ID': 'FOUNDATION-001',
  'Version': 'PUB-V1',
  'Status': 'APPROVED',
  'Caption': caption,
  'Alt Text': altText,
  'Pinned Comment': pinned,
  'Story Before': '',
  'Story After': '',
  'Hashtags': '#شغف_الكيمياء #كيمياء #توجيهي',
  'Last Update': $now.setZone('Asia/Jerusalem').toISODate()
} }];`
    }
  }
});

const appendPackages = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '04 — Write Package Headers + Seed',
    parameters: {
      resource: 'sheet',
      operation: 'append',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      sheetName: { __rl: true, mode: 'name', value: 'حزم النشر' },
      columns: { mappingMode: 'autoMapInputData', value: {}, schema: [] },
      options: { cellFormat: 'USER_ENTERED', handlingExtraData: 'insertInNewColumn' }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000
  }
});

const createQueue = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '05 — Create Tab: طابور النشر اليدوي',
    parameters: {
      resource: 'sheet',
      operation: 'create',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      title: 'طابور النشر اليدوي',
      options: { rightToLeft: true }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000
  }
});

const blankQueue = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: '06 — Build Queue Headers',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `// صف واحد فارغ لإنشاء الأعمدة. منطق SC-01/SC-06 يتخطى الصفوف الفارغة.
const headers = ['Event Key','ID','Scheduled At','Platform','Format','Topic','CTA','Approved Asset URL','Caption','Alt Text','Pinned Comment','State','Created At','Published At','Published URL','Operator Note'];
const row = {};
headers.forEach(function (h) { row[h] = ''; });
return [{ json: row }];`
    }
  }
});

const appendQueue = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '07 — Write Queue Headers',
    parameters: {
      resource: 'sheet',
      operation: 'append',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      sheetName: { __rl: true, mode: 'name', value: 'طابور النشر اليدوي' },
      columns: { mappingMode: 'autoMapInputData', value: {}, schema: [] },
      options: { cellFormat: 'USER_ENTERED', handlingExtraData: 'insertInNewColumn' }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000
  }
});

const createLog = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '08 — Create Tab: سجل الأتمتة',
    parameters: {
      resource: 'sheet',
      operation: 'create',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      title: 'سجل الأتمتة',
      options: { rightToLeft: true }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000
  }
});

const blankLog = node({
  type: 'n8n-nodes-base.code',
  version: 2,
  config: {
    name: '09 — Build Log Headers',
    parameters: {
      mode: 'runOnceForAllItems',
      language: 'javaScript',
      jsCode: `const headers = ['Timestamp','Workflow','Event Key','ID','State','Reason','Run ID','Details'];
const row = {};
headers.forEach(function (h) { row[h] = ''; });
return [{ json: row }];`
    }
  }
});

const appendLog = node({
  type: 'n8n-nodes-base.googleSheets',
  version: 4.7,
  config: {
    name: '10 — Write Log Headers',
    parameters: {
      resource: 'sheet',
      operation: 'append',
      authentication: 'oAuth2',
      documentId: { __rl: true, mode: 'id', value: DOCUMENT_ID },
      sheetName: { __rl: true, mode: 'name', value: 'سجل الأتمتة' },
      columns: { mappingMode: 'autoMapInputData', value: {}, schema: [] },
      options: { cellFormat: 'USER_ENTERED', handlingExtraData: 'insertInNewColumn' }
    },
    credentials: { googleSheetsOAuth2Api: SHEETS_CRED },
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000
  }
});

const note = sticky(
  '## SC-00 | Setup — تشغيل لمرة واحدة\n\nينشئ التبويبات الثلاثة الناقصة ويكتب رؤوسها، ويضع بذرة FOUNDATION-001 في «حزم النشر» بنصوصها المعتمدة حرفيًا.\n\n**إضافة فقط** — لا يحذف ولا يعيد تسمية ولا يعدّل أي تبويب قائم.\n\n⚠️ شغّله **مرة واحدة**. التشغيل الثاني يفشل عند إنشاء تبويب موجود.\nاحذف هذا السير بعد نجاحه.',
  [start, createPackages],
  { color: 4 }
);

export default workflow('sc-00-setup', 'SC-00 | Setup — Master Control Tabs')
  .add(start)
  .to(createPackages)
  .to(seedPackage)
  .to(appendPackages)
  .to(createQueue)
  .to(blankQueue)
  .to(appendQueue)
  .to(createLog)
  .to(blankLog)
  .to(appendLog)
  .add(note);
