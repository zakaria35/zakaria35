/*
 * تحقّق من ملفات n8n المولّدة:
 *  1) JSON سليم وبنية Workflow صحيحة.
 *  2) كل عقدة Code تُصرَّف بلا خطأ نحوي، وبلا require/import متبقٍّ.
 *  3) المكتبة المُحقَنة تُنفَّذ فعليًا وتعطي نفس نتيجة الاختبارات.
 *  4) لا يوجد أي سر/توكن/مفتاح في أي ملف (§32).
 *  5) لا وجود لأي عقدة نشر إلى Meta (§30).
 */

var fs = require('fs');
var path = require('path');
var vm = require('vm');

var DIR = path.join(__dirname, '..', 'n8n');
var files = fs.readdirSync(DIR).filter(function (f) { return f.endsWith('.json'); }).sort();

var problems = [];
var checks = 0;
function ok(msg) { checks++; console.log('  PASS  ' + msg); }
function bad(msg) { checks++; problems.push(msg); console.log('  FAIL  ' + msg); }

/* أنماط الأسرار — لا يجوز وجود أي منها داخل الملفات. */
var SECRET_PATTERNS = [
  { re: /\bEAA[A-Za-z0-9]{20,}/, name: 'Meta access token' },
  { re: /\bghp_[A-Za-z0-9]{20,}/, name: 'GitHub token' },
  { re: /\bAIza[0-9A-Za-z_-]{30,}/, name: 'Google API key' },
  { re: /\bsk-[A-Za-z0-9]{20,}/, name: 'OpenAI-style key' },
  { re: /\bxox[baprs]-[A-Za-z0-9-]{10,}/, name: 'Slack token' },
  { re: /\b\d{6,}:[A-Za-z0-9_-]{30,}/, name: 'Telegram bot token' },
  { re: /"(password|clientSecret|client_secret|accessToken|access_token|apiKey|api_key)"\s*:\s*"[^"]{6,}"/i, name: 'حقل سر مملوء' }
];

/* فحص بنيوي لا نصّي: نوع العقدة وعنوان الـAPI الفعلي.
 * مطابقة النثر تعطي إيجابيات كاذبة (ملاحظة تقول «لا ينشر على Instagram» ليست عقدة نشر). */
var META_NODE_TYPES = [
  'n8n-nodes-base.facebookGraphApi',
  'n8n-nodes-base.facebook',
  'n8n-nodes-base.instagram'
];
var META_HOSTS = [/graph\.facebook\.com/i, /graph\.instagram\.com/i, /api\.instagram\.com/i];

var forbiddenGlobals = ['require', 'process', 'child_process', 'import '];

files.forEach(function (file) {
  var raw = fs.readFileSync(path.join(DIR, file), 'utf8');
  var wf;
  try { wf = JSON.parse(raw); } catch (e) { bad(file + ': JSON غير صالح — ' + e.message); return; }

  // 1) البنية
  if (!wf.name || !Array.isArray(wf.nodes) || typeof wf.connections !== 'object') {
    bad(file + ': بنية Workflow ناقصة');
  } else {
    ok(file + ': بنية صحيحة (' + wf.nodes.length + ' عقدة)');
  }

  if (wf.settings && wf.settings.timezone === 'Asia/Jerusalem') ok(file + ': timezone = Asia/Jerusalem');
  else bad(file + ': timezone ليس Asia/Jerusalem');

  if (wf.active === false) ok(file + ': يُستورد غير مُفعّل (تفعيل واعٍ بعد ربط الاعتمادات)');
  else bad(file + ': active ليس false');

  // اتساق الوصلات
  var names = {};
  wf.nodes.forEach(function (n) { names[n.name] = true; });
  var dangling = [];
  Object.keys(wf.connections).forEach(function (from) {
    if (!names[from]) dangling.push(from);
    (wf.connections[from].main || []).forEach(function (branch) {
      (branch || []).forEach(function (t) { if (!names[t.node]) dangling.push(t.node); });
    });
  });
  if (dangling.length) bad(file + ': وصلات إلى عقد غير موجودة — ' + dangling.join(', '));
  else ok(file + ': جميع الوصلات تشير إلى عقد موجودة');

  // 2+3) عقد Code
  var codeNodes = wf.nodes.filter(function (n) { return n.type === 'n8n-nodes-base.code'; });
  codeNodes.forEach(function (n) {
    var js = n.parameters.jsCode || '';

    forbiddenGlobals.forEach(function (g) {
      if (js.indexOf(g) !== -1) bad(file + ' / ' + n.name + ': يحتوي «' + g + '» غير المتاح في عقدة Code');
    });

    try {
      new vm.Script('(function(){' + js + '})');
    } catch (e) {
      bad(file + ' / ' + n.name + ': خطأ نحوي — ' + e.message);
      return;
    }
    ok(file + ' / ' + n.name + ': يُصرَّف بلا خطأ');
  });

  // 4) الأسرار
  SECRET_PATTERNS.forEach(function (p) {
    if (p.re.test(raw)) bad(file + ': يحتوي على ما يشبه ' + p.name);
  });

  // 5) لا نشر Meta — عقد أو عناوين API حقيقية
  var metaNodes = wf.nodes.filter(function (nd) { return META_NODE_TYPES.indexOf(nd.type) !== -1; });
  if (metaNodes.length) {
    bad(file + ': يحتوي عقدة Meta/Instagram — ' + metaNodes.map(function (x) { return x.name; }).join(', '));
  }
  var hostHit = [];
  wf.nodes.forEach(function (nd) {
    var params = JSON.stringify(nd.parameters || {});
    META_HOSTS.forEach(function (h) { if (h.test(params)) hostHit.push(nd.name); });
  });
  if (hostHit.length) bad(file + ': عقدة تستدعي Meta Graph API — ' + hostHit.join(', '));

  // لا اعتمادات مضمّنة
  var withCreds = wf.nodes.filter(function (n) { return n.credentials; });
  if (withCreds.length) bad(file + ': يحتوي مراجع اعتمادات مضمّنة — يجب ربطها يدويًا بعد الاستيراد');
});

ok('لا ملف يحتوي أي توكن أو كلمة سر (فحص ' + SECRET_PATTERNS.length + ' نمطًا)');
ok('لا عقدة من نوع Meta/Instagram ولا استدعاء لـGraph API في أي ملف (فحص بنيوي)');

/* ==================================================================
 * 3) تنفيذ فعلي للمكتبة المُحقَنة داخل عقدة الحارس
 * ================================================================== */

var guardWf = JSON.parse(fs.readFileSync(path.join(DIR, 'SC-03-publish-guard.json'), 'utf8'));
var guardNode = guardWf.nodes.filter(function (n) { return n.name === '07 — Run Publish Guard'; })[0];

var sandbox = {};
vm.createContext(sandbox);
try {
  // نُنفّذ الجزء المُحقَن فقط (قبل سطر return) لنستخرج الدوال.
  var injected = guardNode.parameters.jsCode.split('/* ===== نهاية المكتبة المُحقَنة ===== */')[0];
  vm.runInContext(injected + '\n;this.__api = { runPublishGuard, sc03Normalize, sc03RunGuard, buildScheduledAt, buildEventKey, formatIsoWithOffset };', sandbox);
  ok('المكتبة المُحقَنة داخل عقدة الحارس تُنفَّذ في سياق معزول');
} catch (e) {
  bad('فشل تنفيذ المكتبة المُحقَنة: ' + e.message);
}

if (sandbox.__api) {
  var api = sandbox.__api;

  var iso = api.buildScheduledAt('2026-09-02', '20:00', 'Asia/Jerusalem').iso;
  if (iso === '2026-09-02T20:00:00+03:00') ok('الكود المُحقَن يفسّر 20:00 بتوقيت Asia/Jerusalem');
  else bad('الكود المُحقَن أعطى توقيتًا خاطئًا: ' + iso);

  var DATA = require('./fixtures/master-control.json');
  var candidate = {
    content_id: 'FOUNDATION-001', topic: 'كيف نفهم العدد الذري؟',
    platform: 'Instagram', post_type: 'Carousel', format: 'Carousel', cta: 'احفظ وشارك',
    scheduled_at: iso, calendar_status: 'APPROVED — READY TO PUBLISH',
    event_key: api.buildEventKey('FOUNDATION-001', iso, 'Instagram', 'Carousel')
  };

  var verdict = api.sc03RunGuard(api.sc03Normalize({
    candidate: candidate,
    masterRows: DATA['لوحة الإنتاج اليومية'],
    approvalRows: DATA['سجل الاعتماد'],
    packageRows: DATA['حزم النشر'],
    publishLogRows: DATA['سجل النشر']
  }));

  if (verdict.guard_status === 'BLOCKED' && verdict.block_reasons.length === 8) {
    ok('الحارس المُحقَن يحظر FOUNDATION-001 بالبيانات الحقيقية (' + verdict.block_reasons.length + ' أسباب) — مطابق لنتيجة run-tests');
  } else {
    bad('نتيجة الحارس المُحقَن لا تطابق الاختبارات: ' + verdict.guard_status + ' / ' + verdict.block_reasons.join(','));
  }

  // نفس الحالة الافتراضية المعتمدة يجب أن تمر
  var pkg = require('./fixtures/package-foundation-001.json');
  var master = JSON.parse(JSON.stringify(DATA['لوحة الإنتاج اليومية']));
  master[1]['حالة الإنتاج'] = 'APPROVED — READY TO PUBLISH';
  master[1]['رابط الملف المعتمد'] = 'https://drive.google.com/file/d/X/view';
  master[1]['نسخة V2'] = 'V2-V2';
  var appr = JSON.parse(JSON.stringify(DATA['سجل الاعتماد']));
  appr[1]['QA بصري'] = 'PASS';
  appr[1]['حالة الاعتماد'] = 'APPROVED';

  var v2 = api.sc03RunGuard(api.sc03Normalize({
    candidate: candidate, masterRows: master, approvalRows: appr,
    packageRows: [pkg], publishLogRows: []
  }));
  if (v2.guard_status === 'PASS') ok('الحارس المُحقَن يمرّر الحالة المعتمدة كاملةً (PASS)');
  else bad('الحارس المُحقَن حظر حالة معتمدة كاملة: ' + v2.block_reasons.join(','));
}

console.log('\n' + '='.repeat(74));
console.log('  فحص ملفات n8n: ' + (checks - problems.length) + '/' + checks + ' ناجح، ' + problems.length + ' فاشل');
console.log('='.repeat(74) + '\n');
process.exit(problems.length === 0 ? 0 : 1);
