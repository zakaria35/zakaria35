/*
 * Test Matrix — Shaghaf Content Factory (§28)
 * يشغّل نفس الكود المحقون في عقد n8n (lib/core.js) على لقطة حقيقية من Master Control.
 * تشغيل:  node workflows/content-factory/tests/run-tests.js
 */

var core = require('../lib/core.js');
var pipeline = require('./pipeline.js');
var DATA = require('./fixtures/master-control.json');

var TZ = 'Asia/Jerusalem';
var results = [];
var failures = 0;

function clone(v) { return JSON.parse(JSON.stringify(v)); }

function record(id, title, expected, actual, ok, detail) {
  results.push({ id: id, title: title, expected: expected, actual: actual, ok: ok, detail: detail || '' });
  if (!ok) failures++;
}

function assertEq(id, title, expected, actual, detail) {
  record(id, title, String(expected), String(actual), String(expected) === String(actual), detail);
}

function sameSet(a, b) {
  var x = (a || []).slice().sort();
  var y = (b || []).slice().sort();
  return x.length === y.length && x.every(function (v, i) { return v === y[i]; });
}

/* ---------------- helpers ---------------- */

function guardFor(contentId, sheets, nowIso) {
  return pipeline.runGuard(contentId, sheets, TZ, nowIso);
}

function freshSheets() { return clone(DATA); }

/* =================================================================
 * TEST 6 (يُنفَّذ أولًا لأنه أساس كل ما بعده) — التوقيت
 * ================================================================= */

var built = core.buildScheduledAt('2026-09-02', '20:00', TZ);
assertEq('TEST 6a', '20:00 يوم 2026-09-02 تُفسَّر Asia/Jerusalem لا UTC',
  '2026-09-02T20:00:00+03:00', built.iso);
assertEq('TEST 6b', 'نفس اللحظة بالـUTC الحقيقي (UTC+3 صيفًا)',
  '2026-09-02T17:00:00.000Z', built.utc.toISOString());

var winter = core.buildScheduledAt('2026-01-15', '20:00', TZ);
assertEq('TEST 6c', 'التوقيت الشتوي يُحسب UTC+2 تلقائيًا (لا إزاحة ثابتة مزروعة)',
  '2026-01-15T18:00:00.000Z', winter.utc.toISOString());

assertEq('TEST 6d', 'تجاهل Etc/GMT الظاهر في ميتاداتا الملف — الفارق 3 ساعات',
  180, core.tzOffsetMinutes(built.utc, TZ));

/* =================================================================
 * TEST 1A — FOUNDATION-001 بالبيانات الحقيقية كما هي اليوم
 * ================================================================= */

var t1a = guardFor('FOUNDATION-001', freshSheets(), '2026-09-02T19:50:00+03:00');
var expected1a = [
  'QA_VISUAL_NOT_PASS',
  'FINAL_APPROVAL_MISSING',
  'PRODUCTION_NOT_APPROVED',
  'APPROVED_ASSET_MISSING',
  'V2_VERSION_PENDING',
  'PUBLISH_PACKAGE_NOT_FOUND',
  'PUBLISH_PACKAGE_NOT_APPROVED',
  'CAPTION_MISSING'
];
record('TEST 1A', 'FOUNDATION-001 بالبيانات الحقيقية الحالية',
  'BLOCKED + ' + expected1a.length + ' أسباب',
  t1a.guard_status + ' + ' + t1a.block_reasons.length + ' أسباب',
  t1a.guard_status === 'BLOCKED' && sameSet(expected1a, t1a.block_reasons),
  t1a.block_reasons.join(', '));

/* =================================================================
 * TEST 1B — نفس العنصر بعد إتمام الإصلاح البصري وحزمة النشر
 * (سيناريو تحقُّقي — لا يُكتب في الملف الحقيقي)
 * ================================================================= */

var s1b = freshSheets();
var m = core.findById(s1b['لوحة الإنتاج اليومية'], 'FOUNDATION-001');
m['حالة الإنتاج'] = 'APPROVED — READY TO PUBLISH';
m['رابط الملف المعتمد'] = 'https://drive.google.com/file/d/PLACEHOLDER_FINAL_ASSET/view';
m['نسخة V2'] = 'V2-V2';
var a = core.findById(s1b['سجل الاعتماد'], 'FOUNDATION-001');
a['QA بصري'] = 'PASS';
a['حالة الاعتماد'] = 'APPROVED';
s1b['حزم النشر'] = [require('./fixtures/package-foundation-001.json')];

var t1b = guardFor('FOUNDATION-001', s1b, '2026-09-02T19:50:00+03:00');
record('TEST 1B', 'FOUNDATION-001 بعد رفع النسخة المعدّلة + اعتماد QA البصري + حزمة نشر',
  'PASS', t1b.guard_status + (t1b.block_reasons.length ? ' (' + t1b.block_reasons.join(', ') + ')' : ''),
  t1b.guard_status === 'PASS', 'يثبت أن السلسلة كاملة تعمل دون تزوير أي بيانات');

/* =================================================================
 * TEST 2 — QA بصري = PENDING
 * ================================================================= */

var s2 = clone(s1b);
core.findById(s2['سجل الاعتماد'], 'FOUNDATION-001')['QA بصري'] = 'PENDING';
var t2 = guardFor('FOUNDATION-001', s2, '2026-09-02T19:50:00+03:00');
record('TEST 2', 'QA بصري = PENDING',
  'BLOCKED / QA_VISUAL_NOT_PASS',
  t2.guard_status + ' / ' + t2.block_reasons.join(','),
  t2.guard_status === 'BLOCKED' && t2.block_reasons.indexOf('QA_VISUAL_NOT_PASS') !== -1);

/* =================================================================
 * TEST 3 — رابط الملف المعتمد فارغ
 * ================================================================= */

var s3 = clone(s1b);
core.findById(s3['لوحة الإنتاج اليومية'], 'FOUNDATION-001')['رابط الملف المعتمد'] = '';
var t3 = guardFor('FOUNDATION-001', s3, '2026-09-02T19:50:00+03:00');
record('TEST 3', 'رابط الملف المعتمد فارغ',
  'BLOCKED / APPROVED_ASSET_MISSING',
  t3.guard_status + ' / ' + t3.block_reasons.join(','),
  t3.guard_status === 'BLOCKED' && t3.block_reasons.indexOf('APPROVED_ASSET_MISSING') !== -1);

/* =================================================================
 * TEST 4 — عنصر منشور مسبقًا -> SKIP بلا طابور جديد
 * ================================================================= */

var s4 = clone(s1b);
s4['سجل النشر'] = [{
  'ID': 'FOUNDATION-001', 'المنصة': 'Instagram', 'صيغة النشر': 'Carousel',
  'تاريخ النشر': '2026-09-02', 'رابط المنشور': 'https://www.instagram.com/p/EXAMPLE/',
  'حالة النشر': 'PUBLISHED', 'ملاحظات الأداء': ''
}];
var run4 = pipeline.runCycle(s4, TZ, '2026-09-02T19:50:00+03:00');
var f4 = run4.decisions.filter(function (x) { return x.content_id === 'FOUNDATION-001'; })[0];
record('TEST 4', 'عنصر مسجَّل PUBLISHED مسبقًا',
  'SKIPPED_ALREADY_PUBLISHED + 0 صفوف طابور',
  (f4 ? f4.state : 'لا قرار') + ' + ' + s4['طابور النشر اليدوي'].length + ' صفوف طابور',
  !!f4 && f4.state === 'SKIPPED_ALREADY_PUBLISHED' && s4['طابور النشر اليدوي'].length === 0);

/* =================================================================
 * TEST 5 — تشغيل SC-01 مرتين لنفس العنصر
 * ================================================================= */

var s5 = clone(s1b);
pipeline.runCycle(s5, TZ, '2026-09-02T19:50:00+03:00');
var queueAfterFirst = s5['طابور النشر اليدوي'].length;
var run5b = pipeline.runCycle(s5, TZ, '2026-09-02T19:55:00+03:00');
var queueAfterSecond = s5['طابور النشر اليدوي'].length;
record('TEST 5', 'تشغيلان متتاليان لنفس العنصر (Idempotency)',
  'صف واحد فقط بعد التشغيلين',
  queueAfterFirst + ' ثم ' + queueAfterSecond + ' صف',
  queueAfterFirst === 1 && queueAfterSecond === 1,
  'القرار في الدورة الثانية: ' + (run5b.decisions.map(function (d) { return d.state; }).join(',') || 'لا شيء'));

var keys = s5['طابور النشر اليدوي'].map(function (r) { return r['Event Key']; });
record('TEST 5b', 'Event Key المولّد',
  'FOUNDATION-001|2026-09-02T20:00:00+03:00|Instagram|Carousel',
  keys[0] || '(فارغ)',
  keys[0] === 'FOUNDATION-001|2026-09-02T20:00:00+03:00|Instagram|Carousel');

record('TEST 5c', 'حالة الصف المُنشأ',
  'READY_FOR_MANUAL_PUBLISH',
  (s5['طابور النشر اليدوي'][0] || {})['State'] || '(لا صف)',
  (s5['طابور النشر اليدوي'][0] || {})['State'] === 'READY_FOR_MANUAL_PUBLISH');

record('TEST 5d', 'الـCaption في الطابور منسوخ حرفيًا من حزمة النشر — لا توليد',
  'مطابق حرفيًا',
  (s5['طابور النشر اليدوي'][0] || {})['Caption'] === require('./fixtures/package-foundation-001.json').Caption ? 'مطابق حرفيًا' : 'مختلف',
  (s5['طابور النشر اليدوي'][0] || {})['Caption'] === require('./fixtures/package-foundation-001.json').Caption);

/* =================================================================
 * TEST 7 — عنصر غير موجود في لوحة الإنتاج اليومية
 * ================================================================= */

var s7 = clone(s1b);
var t7 = guardFor('FOUNDATION-002', s7, '2026-09-09T19:50:00+03:00');
record('TEST 7', 'عنصر غير موجود في لوحة الإنتاج اليومية',
  'BLOCKED / MASTER_RECORD_MISSING',
  t7.guard_status + ' / ' + t7.block_reasons.slice(0, 3).join(','),
  t7.guard_status === 'BLOCKED' && t7.block_reasons.indexOf('MASTER_RECORD_MISSING') !== -1);

/* =================================================================
 * TEST 8 — لا توجد حزمة نشر
 * ================================================================= */

var s8 = clone(s1b);
s8['حزم النشر'] = [];
var t8 = guardFor('FOUNDATION-001', s8, '2026-09-02T19:50:00+03:00');
record('TEST 8', 'حزمة النشر غير موجودة',
  'BLOCKED / PUBLISH_PACKAGE_NOT_APPROVED',
  t8.guard_status + ' / ' + t8.block_reasons.join(','),
  t8.guard_status === 'BLOCKED' &&
  t8.block_reasons.indexOf('PUBLISH_PACKAGE_NOT_APPROVED') !== -1 &&
  t8.block_reasons.indexOf('PUBLISH_PACKAGE_NOT_FOUND') !== -1);

var s8b = clone(s1b);
s8b['حزم النشر'][0].Status = 'DRAFT';
var t8b = guardFor('FOUNDATION-001', s8b, '2026-09-02T19:50:00+03:00');
record('TEST 8b', 'حزمة نشر بحالة DRAFT',
  'BLOCKED / PUBLISH_PACKAGE_NOT_APPROVED',
  t8b.guard_status + ' / ' + t8b.block_reasons.join(','),
  t8b.guard_status === 'BLOCKED' && t8b.block_reasons.indexOf('PUBLISH_PACKAGE_NOT_APPROVED') !== -1);

/* =================================================================
 * TEST 9 — نافذة الاستحقاق و MISSED_WINDOW
 * ================================================================= */

var s9 = clone(s1b);
var run9 = pipeline.runCycle(s9, TZ, '2026-09-04T10:00:00+03:00'); // بعد 38 ساعة
var d9 = run9.decisions.filter(function (x) { return x.content_id === 'FOUNDATION-001'; })[0];
record('TEST 9', 'موعد أقدم من LOOKBACK_HOURS (12 ساعة) ولم يُنشر',
  'MISSED_WINDOW + 0 صفوف طابور',
  (d9 ? d9.state : 'لا قرار') + ' + ' + s9['طابور النشر اليدوي'].length + ' صفوف طابور',
  !!d9 && d9.state === 'MISSED_WINDOW' && s9['طابور النشر اليدوي'].length === 0);

function missedAlerts(sheets, contentId) {
  return sheets['سجل الأتمتة'].filter(function (r) {
    return r.State === 'MISSED_WINDOW' && (!contentId || r.ID === contentId);
  });
}
var alertsAfterFirst = missedAlerts(s9).length;
var f001AfterFirst = missedAlerts(s9, 'FOUNDATION-001').length;
pipeline.runCycle(s9, TZ, '2026-09-04T10:15:00+03:00');
var alertsAfterSecond = missedAlerts(s9).length;
record('TEST 9b', 'تنبيه MISSED_WINDOW مرة واحدة فقط لكل Event Key',
  'تنبيه واحد لـFOUNDATION-001، والدورة الثانية لا تضيف شيئًا',
  f001AfterFirst + ' تنبيه للعنصر، الإجمالي ' + alertsAfterFirst + ' ثم ' + alertsAfterSecond,
  f001AfterFirst === 1 && alertsAfterFirst === alertsAfterSecond,
  'التقويم يحوي 3 عناصر فات موعدها (PRE03, FOUNDATION-001, R01) — تنبيه واحد لكل منها');

var s9c = clone(s1b);
var run9c = pipeline.runCycle(s9c, TZ, '2026-09-02T18:00:00+03:00'); // قبل الموعد بساعتين
var d9c = run9c.decisions.filter(function (x) { return x.content_id === 'FOUNDATION-001'; });
record('TEST 9c', 'قبل موعد FOUNDATION-001 بساعتين (LEAD_MINUTES = 30)',
  'FOUNDATION-001 ليس مرشحًا ولا صف طابور',
  d9c.length + ' قرار له / ' + s9c['طابور النشر اليدوي'].length + ' صف طابور',
  d9c.length === 0 && s9c['طابور النشر اليدوي'].length === 0);

var s9d = clone(s1b);
pipeline.runCycle(s9d, TZ, '2026-09-02T19:35:00+03:00'); // ضمن نافذة الـ30 دقيقة
record('TEST 9d', 'قبل الموعد بـ25 دقيقة (داخل LEAD_MINUTES)',
  '1 صف طابور', s9d['طابور النشر اليدوي'].length + ' صف',
  s9d['طابور النشر اليدوي'].length === 1);

/* =================================================================
 * TEST 10 — DRY_RUN لا يكتب شيئًا
 * ================================================================= */

var s10 = clone(s1b);
pipeline.runCycle(s10, TZ, '2026-09-02T19:50:00+03:00', { DRY_RUN: true });
record('TEST 10', 'DRY_RUN = true لا يكتب أي صف',
  '0 طابور / 0 سجل أتمتة',
  s10['طابور النشر اليدوي'].length + ' طابور / ' + s10['سجل الأتمتة'].length + ' سجل',
  s10['طابور النشر اليدوي'].length === 0 && s10['سجل الأتمتة'].length === 0);

/* =================================================================
 * TEST 11 — مزامنة PUBLISHED إلى سجل النشر مرة واحدة (§26)
 * ================================================================= */

var s11 = clone(s1b);
pipeline.runCycle(s11, TZ, '2026-09-02T19:50:00+03:00');
s11['طابور النشر اليدوي'][0]['State'] = 'PUBLISHED';
s11['طابور النشر اليدوي'][0]['Published URL'] = 'https://www.instagram.com/p/EXAMPLE/';
s11['طابور النشر اليدوي'][0]['Published At'] = '2026-09-02T20:07:00+03:00';
pipeline.syncPublished(s11);
var firstSync = s11['سجل النشر'].length;
pipeline.syncPublished(s11);
record('TEST 11', 'مزامنة PUBLISHED -> سجل النشر مرة واحدة فقط',
  '1 صف بعد مزامنتين',
  firstSync + ' ثم ' + s11['سجل النشر'].length + ' صف',
  firstSync === 1 && s11['سجل النشر'].length === 1);

/* =================================================================
 * TEST 12 — سياسة إعادة المحاولة (§24)
 * ================================================================= */

var c1 = core.classifyAlertEvent({ state: 'BLOCKED', block_reasons: ['QA_VISUAL_NOT_PASS'] });
record('TEST 12a', 'حظر قواعد عمل لا يُعاد تلقائيًا',
  'BUSINESS_BLOCK / retry=false', c1.category + ' / retry=' + c1.retry_allowed,
  c1.category === 'BUSINESS_BLOCK' && c1.retry_allowed === false);

var c2 = core.classifyAlertEvent({ state: 'ERROR', reason: 'Google Sheets 503' });
record('TEST 12b', 'خطأ تقني مؤقت: محاولتان إضافيتان بحد أقصى',
  'TECHNICAL_ERROR / 2', c2.category + ' / ' + c2.max_additional_retries,
  c2.category === 'TECHNICAL_ERROR' && c2.max_additional_retries === 2);

/* =================================================================
 * TEST 13 — القراءة بالاسم لا بترتيب الأعمدة
 * ================================================================= */

var shuffled = { 'نسخة V2': 'V2-X', 'ID': 'X-1', 'حالة الإنتاج': 'APPROVED', 'حالة  التدقيق   العلمي': 'مدققة علميًا وجاهزة للإنتاج' };
record('TEST 13', 'قراءة الأعمدة بالاسم مع اختلاف الترتيب والمسافات',
  'مدققة علميًا وجاهزة للإنتاج',
  core.field(shuffled, ['حالة التدقيق العلمي']),
  core.field(shuffled, ['حالة التدقيق العلمي']) === 'مدققة علميًا وجاهزة للإنتاج');

/* =================================================================
 * التقرير
 * ================================================================= */

var W = 74;
console.log('\n' + '='.repeat(W));
console.log('  Test Matrix — Shaghaf Content Factory | SC-01 / SC-03 / SC-05 / SC-06');
console.log('  Timezone: ' + TZ + '   |   بيانات حقيقية من Master Control');
console.log('='.repeat(W));

results.forEach(function (r) {
  console.log('\n' + (r.ok ? '  PASS  ' : '  FAIL  ') + r.id + ' — ' + r.title);
  console.log('        المتوقع : ' + r.expected);
  console.log('        الفعلي  : ' + r.actual);
  if (r.detail) console.log('        تفصيل   : ' + r.detail);
});

console.log('\n' + '='.repeat(W));
console.log('  النتيجة: ' + (results.length - failures) + '/' + results.length + ' ناجح، ' + failures + ' فاشل');
console.log('='.repeat(W) + '\n');

process.exit(failures === 0 ? 0 : 1);
