/*
 * مولّد ملفات n8n لـ SC-01 / SC-03 / SC-05 / SC-06.
 * يحقن lib/core.js + lib/steps.js حرفيًا داخل عقد Code، فلا يفترق
 * الكود المُختبَر (tests/) عن الكود المُشغَّل (n8n).
 *
 * تشغيل:  node workflows/content-factory/build/build.js
 */

var fs = require('fs');
var path = require('path');
var crypto = require('crypto');

var ROOT = path.join(__dirname, '..');
var OUT = path.join(ROOT, 'n8n');

var SPREADSHEET_ID = '1AsRZO5jZCWlKK1zmCravNEfBDIKnKBzprRI99kFUMk8';
var TZ = 'Asia/Jerusalem';

var SHEET = {
  calendar: 'تقويم النشر — 30 يوم',
  master: 'لوحة الإنتاج اليومية',
  approval: 'سجل الاعتماد',
  packages: 'حزم النشر',
  publishLog: 'سجل النشر',
  queue: 'طابور النشر اليدوي',
  autoLog: 'سجل الأتمتة'
};

// معرّفات تُستبدل بعد الاستيراد (لا يمكن معرفتها قبل إنشاء الـWorkflows في n8n).
var PLACEHOLDER = {
  SC03: 'REPLACE_WITH_SC-03_WORKFLOW_ID',
  SC05: 'REPLACE_WITH_SC-05_WORKFLOW_ID',
  SC06: 'REPLACE_WITH_SC-06_WORKFLOW_ID'
};

/* ---------------- حقن المكتبات ---------------- */

function stripModuleExport(src) {
  // عقدة Code في n8n لا تعرف module — نزيل كتلة التصدير الخاصة بـNode.
  return src.replace(/if \(typeof module !== 'undefined' && module\.exports\) \{[\s\S]*?\n\}\n?$/m, '');
}

function libSource() {
  var core = stripModuleExport(fs.readFileSync(path.join(ROOT, 'lib', 'core.js'), 'utf8'));
  var steps = stripModuleExport(fs.readFileSync(path.join(ROOT, 'lib', 'steps.js'), 'utf8'));
  // داخل n8n لا يوجد require: الدوال معرّفة في نفس النطاق.
  steps = steps.replace(
    /var __core = [\s\S]*?_alert = __core \? __core\.classifyAlertEvent   : classifyAlertEvent;/,
    [
      'var _f = field, _t = text, _u = upper, _find = findById;',
      'var _norm = normalizeCalendarRow, _class = classifyWindow;',
      'var _built = buildNormalized, _guard = runPublishGuard;',
      'var _pubst = isPublishedState, _alert = classifyAlertEvent;'
    ].join('\n')
  );
  return [
    '/* ===== مُحقَن آليًا من workflows/content-factory/lib — لا تحرّره هنا ===== */',
    '/* المصدر: lib/core.js + lib/steps.js | المولّد: build/build.js            */',
    core.trim(),
    steps.trim(),
    '/* ===== نهاية المكتبة المُحقَنة ===== */',
    ''
  ].join('\n\n');
}

var LIB = libSource();

function code(body) { return LIB + '\n' + body.trim() + '\n'; }

/* ---------------- بناة العقد ---------------- */

var idSeed = 0;
function nid(name) {
  idSeed++;
  return crypto.createHash('sha1').update(name + '::' + idSeed).digest('hex').slice(0, 8) +
    '-0000-4000-8000-' + crypto.createHash('sha1').update(name).digest('hex').slice(0, 12);
}

function node(name, type, typeVersion, position, parameters, extra) {
  return Object.assign({
    parameters: parameters || {},
    type: type,
    typeVersion: typeVersion,
    position: position,
    id: nid(name),
    name: name
  }, extra || {});
}

function codeNode(name, position, body, extra) {
  return node(name, 'n8n-nodes-base.code', 2, position,
    { mode: 'runOnceForAllItems', jsCode: code(body) }, extra);
}

function sheetsRead(name, position, sheetName, extra) {
  return node(name, 'n8n-nodes-base.googleSheets', 4.5, position, {
    operation: 'read',
    documentId: { __rl: true, value: SPREADSHEET_ID, mode: 'id' },
    sheetName: { __rl: true, value: sheetName, mode: 'name' },
    options: {}
  }, Object.assign({
    alwaysOutputData: true,
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000,
    notes: 'قراءة فقط. إعادة المحاولة: محاولتان إضافيتان بحد أقصى (§24).'
  }, extra || {}));
}

function sheetsAppend(name, position, sheetName, extra) {
  return node(name, 'n8n-nodes-base.googleSheets', 4.5, position, {
    operation: 'append',
    documentId: { __rl: true, value: SPREADSHEET_ID, mode: 'id' },
    sheetName: { __rl: true, value: sheetName, mode: 'name' },
    columns: { mappingMode: 'autoMapInputData', value: {}, matchingColumns: [], schema: [] },
    options: {}
  }, Object.assign({
    retryOnFail: true,
    maxTries: 3,
    waitBetweenTries: 5000,
    notes: 'إضافة صفوف فقط — لا تعديل ولا حذف لأي صف قائم (§33).'
  }, extra || {}));
}

function ifNode(name, position, leftValue, rightValue, extra) {
  return node(name, 'n8n-nodes-base.if', 2.2, position, {
    conditions: {
      options: { caseSensitive: true, leftValue: '', typeValidation: 'loose', version: 2 },
      conditions: [{
        id: nid(name + ':cond'),
        leftValue: leftValue,
        rightValue: rightValue,
        operator: { type: 'string', operation: 'equals' }
      }],
      combinator: 'and'
    },
    looseTypeValidation: true,
    options: {}
  }, extra);
}

function execWorkflow(name, position, placeholderId, label, extra) {
  return node(name, 'n8n-nodes-base.executeWorkflow', 1.2, position, {
    workflowId: { __rl: true, value: placeholderId, mode: 'id', cachedResultName: label },
    options: { waitForSubWorkflow: true }
  }, Object.assign({
    notes: 'بعد الاستيراد: اختر ' + label + ' من القائمة ليُستبدل ' + placeholderId + '.'
  }, extra || {}));
}

function execTrigger(name, position) {
  return node(name, 'n8n-nodes-base.executeWorkflowTrigger', 1.1, position, { inputSource: 'passthrough' });
}

function noOp(name, position, notes) {
  return node(name, 'n8n-nodes-base.noOp', 1, position, {}, { notes: notes || '' });
}

function sticky(content, position, size, color) {
  return node('Note ' + (++idSeed), 'n8n-nodes-base.stickyNote', 1, position, {
    content: content, height: size[1], width: size[0], color: color || 7
  });
}

function conn(map) {
  var out = {};
  Object.keys(map).forEach(function (from) {
    out[from] = { main: map[from].map(function (targets) {
      return (targets || []).map(function (t) { return { node: t, type: 'main', index: 0 }; });
    }) };
  });
  return out;
}

function workflow(name, nodes, connections, extra) {
  return Object.assign({
    name: name,
    nodes: nodes,
    connections: connections,
    active: false,
    settings: {
      executionOrder: 'v1',
      timezone: TZ,
      saveManualExecutions: true,
      callerPolicy: 'workflowsFromSameOwner'
    },
    pinData: {},
    meta: { instanceId: 'shaghaf-content-factory' },
    tags: []
  }, extra || {});
}

function write(file, obj) {
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, file), JSON.stringify(obj, null, 2) + '\n', 'utf8');
  return file;
}

/* ==================================================================
 * SC-01 | Publishing Queue
 * ================================================================== */

function buildSC01() {
  var n = [];

  n.push(sticky(
    '## SC-01 | Publishing Queue\n\n' +
    'يقرأ **' + SHEET.calendar + '** كل 15 دقيقة، يبني `scheduled_at` بتوقيت **' + TZ + '**،\n' +
    'ويحدّد المستحق. لا يقرر الاعتماد — يحيل كل مرشّح إلى **SC-03 Publish Guard**.\n\n' +
    '⚠️ اضبط `DRY_RUN = false` في عقدة **02 — Config** فقط بعد نجاح الاختبارات.',
    [-660, -280], [620, 220], 4));

  n.push(node('01 — Schedule Every 15m', 'n8n-nodes-base.scheduleTrigger', 1.2, [-660, 0], {
    rule: { interval: [{ field: 'minutes', minutesInterval: 15 }] }
  }, { notes: 'الفاصل الزمني يُعدّل من هنا؛ باقي الإعدادات في 02 — Config.' }));

  n.push(node('01b — Manual Test Trigger', 'n8n-nodes-base.manualTrigger', 1, [-660, 200], {},
    { notes: 'للاختبار اليدوي أثناء DRY_RUN.' }));

  n.push(codeNode('02 — Config', [-420, 100], [
    "// مركز الإعداد الوحيد لـSC-01. لا تضع أي سرّ هنا (§32).",
    "const config = {",
    "  TIMEZONE: '" + TZ + "',",
    "  LEAD_MINUTES: 30,      // كم دقيقة قبل الموعد يُعتبر العنصر مستحقًا",
    "  LOOKBACK_HOURS: 12,    // أقدم موعد نقبل معالجته؛ ما قبله = MISSED_WINDOW",
    "  DRY_RUN: true,         // true = لا كتابة في أي Sheet (§29)",
    "  SPREADSHEET_ID: '" + SPREADSHEET_ID + "'",
    "};",
    "",
    "const now = new Date();",
    "return [{ json: {",
    "  config,",
    "  now_ms: now.getTime(),",
    "  now_iso: formatIsoWithOffset(now, config.TIMEZONE),",
    "  run_id: $execution.id",
    "} }];"
  ].join('\n')));

  n.push(sheetsRead('03 — Read Publishing Calendar', [-200, 100], SHEET.calendar));
  n.push(sheetsRead('04 — Read Manual Queue', [-20, 100], SHEET.queue, { executeOnce: true }));
  n.push(sheetsRead('05 — Read Publish Log', [160, 100], SHEET.publishLog, { executeOnce: true }));
  n.push(sheetsRead('06 — Read Automation Log', [340, 100], SHEET.autoLog, { executeOnce: true }));

  n.push(codeNode('07 — Build Candidates', [540, 100], [
    "// يبني scheduled_at بـ" + TZ + "، وEvent Key، ويصنّف النافذة.",
    "const cfgItem = $('02 — Config').first().json;",
    "const cfg = cfgItem.config;",
    "",
    "const rows = (name) => { try { return $(name).all().map(i => i.json); } catch (e) { return []; } };",
    "",
    "const candidates = sc01BuildCandidates({",
    "  calendarRows:   rows('03 — Read Publishing Calendar'),",
    "  queueRows:      rows('04 — Read Manual Queue'),",
    "  publishLogRows: rows('05 — Read Publish Log'),",
    "  autoLogRows:    rows('06 — Read Automation Log'),",
    "  config: cfg,",
    "  nowMs: cfgItem.now_ms",
    "});",
    "",
    "return candidates.map(c => ({ json: Object.assign({}, c, {",
    "  dry_run: cfg.DRY_RUN,",
    "  run_id: cfgItem.run_id,",
    "  now_iso: cfgItem.now_iso,",
    "  timezone: cfg.TIMEZONE,",
    "  source_workflow: 'SC-01'",
    "}) }));"
  ].join('\n')));

  n.push(ifNode('08 — Is DUE?', [760, 100], '={{ $json.route }}', 'DUE'));

  n.push(codeNode('09 — Build CANDIDATE Log Row', [980, 0], [
    "return $input.all().map(i => ({ json: buildLogRow({",
    "  timestamp: i.json.now_iso, workflow: 'SC-01',",
    "  event_key: i.json.event_key, content_id: i.json.content_id,",
    "  state: 'CANDIDATE', reason: '', run_id: i.json.run_id,",
    "  details: { scheduled_at: i.json.scheduled_at, platform: i.json.platform, post_type: i.json.post_type }",
    "}) }));"
  ].join('\n')));

  n.push(ifNode('10 — Write Enabled?', [1180, 0], '={{ $(\'02 — Config\').first().json.config.DRY_RUN }}', 'false'));
  n.push(sheetsAppend('11 — Log CANDIDATE', [1380, -100], SHEET.autoLog));
  n.push(noOp('12 — DRY RUN (No Write)', [1380, 100], 'DRY_RUN = true: لا كتابة. غيّره من 02 — Config.'));

  n.push(execWorkflow('13 — Execute SC-03 Guard', [1600, 0], PLACEHOLDER.SC03, 'SC-03 | Publish Guard'));

  n.push(ifNode('14 — Is MISSED_WINDOW?', [980, 260], '={{ $json.route }}', 'MISSED_WINDOW'));
  n.push(codeNode('15 — Build MISSED_WINDOW Event', [1180, 200], [
    "// §34 — لا نشر تلقائي لما فات موعده؛ تنبيه واحد فقط لكل Event Key.",
    "return $input.all().map(i => ({ json: Object.assign({}, i.json, {",
    "  state: 'MISSED_WINDOW',",
    "  block_reasons: ['MISSED_WINDOW'],",
    "  source_workflow: 'SC-01'",
    "}) }));"
  ].join('\n')));
  n.push(execWorkflow('16 — Execute SC-05 Alerts', [1380, 200], PLACEHOLDER.SC05, 'SC-05 | Alerts & Recovery'));
  n.push(noOp('17 — No Action', [1180, 360], 'SKIP / NOT_DUE — مسجَّل في مخرجات 07 للمراجعة.'));

  var c = conn({
    '01 — Schedule Every 15m': [['02 — Config']],
    '01b — Manual Test Trigger': [['02 — Config']],
    '02 — Config': [['03 — Read Publishing Calendar']],
    '03 — Read Publishing Calendar': [['04 — Read Manual Queue']],
    '04 — Read Manual Queue': [['05 — Read Publish Log']],
    '05 — Read Publish Log': [['06 — Read Automation Log']],
    '06 — Read Automation Log': [['07 — Build Candidates']],
    '07 — Build Candidates': [['08 — Is DUE?']],
    '08 — Is DUE?': [['09 — Build CANDIDATE Log Row'], ['14 — Is MISSED_WINDOW?']],
    '09 — Build CANDIDATE Log Row': [['10 — Write Enabled?']],
    '10 — Write Enabled?': [['11 — Log CANDIDATE'], ['12 — DRY RUN (No Write)']],
    '11 — Log CANDIDATE': [['13 — Execute SC-03 Guard']],
    '12 — DRY RUN (No Write)': [['13 — Execute SC-03 Guard']],
    '14 — Is MISSED_WINDOW?': [['15 — Build MISSED_WINDOW Event'], ['17 — No Action']],
    '15 — Build MISSED_WINDOW Event': [['16 — Execute SC-05 Alerts']]
  });

  return write('SC-01-publishing-queue.json', workflow('SC-01 | Publishing Queue', n, c));
}

/* ==================================================================
 * SC-03 | Publish Guard
 * ================================================================== */

function buildSC03() {
  var n = [];

  n.push(sticky(
    '## SC-03 | Publish Guard — أهم Workflow في النظام\n\n' +
    '`NO APPROVAL = NO PUBLISH`. يجمع الحقائق من 5 تبويبات ويصدر **PASS** أو **BLOCKED**\n' +
    'مع `block_reasons` صريحة (§35). لا يكتب محتوى، ولا يعدّل caption، ولا يخفف شرطًا.\n\n' +
    '⚠️ **حالة الإنتاج في التقويم لا تُعتمد كمصدر حقيقة** — المصدر هو لوحة الإنتاج اليومية + سجل الاعتماد.',
    [-660, -300], [700, 240], 3));

  n.push(execTrigger('01 — Receive Content', [-660, 20]));

  n.push(sheetsRead('02 — Lookup Master Record', [-420, 20], SHEET.master, { executeOnce: true }));
  n.push(sheetsRead('03 — Lookup Approval Record', [-220, 20], SHEET.approval, { executeOnce: true }));
  n.push(sheetsRead('04 — Lookup Publish Package', [-20, 20], SHEET.packages, {
    executeOnce: true,
    onError: 'continueRegularOutput',
    notes: 'إن لم يوجد تبويب «' + SHEET.packages + '» بعد، تُعامل النتيجة كحزمة مفقودة -> BLOCKED، ولا يتوقف السير.'
  }));
  n.push(sheetsRead('05 — Lookup Publish Log', [180, 20], SHEET.publishLog, { executeOnce: true }));

  n.push(codeNode('06 — Normalize Data', [400, 20], [
    "// كائن موحّد واحد لكل مرشّح (§17). القراءة بأسماء الأعمدة لا بأرقامها.",
    "const rows = (name) => { try { return $(name).all().map(i => i.json); } catch (e) { return []; } };",
    "",
    "const master     = rows('02 — Lookup Master Record');",
    "const approval   = rows('03 — Lookup Approval Record');",
    "const packages   = rows('04 — Lookup Publish Package');",
    "const publishLog = rows('05 — Lookup Publish Log');",
    "",
    "return $('01 — Receive Content').all().map(item => {",
    "  const c = item.json;",
    "  const normalized = sc03Normalize({",
    "    candidate: c, masterRows: master, approvalRows: approval,",
    "    packageRows: packages, publishLogRows: publishLog",
    "  });",
    "  return { json: Object.assign({}, normalized, {",
    "    dry_run: c.dry_run, run_id: c.run_id, now_iso: c.now_iso,",
    "    timezone: c.timezone, source_workflow: 'SC-03'",
    "  }) };",
    "});"
  ].join('\n')));

  n.push(codeNode('07 — Run Publish Guard', [620, 20], [
    "// القرار. لا يمر شيء إلا باستيفاء كل الشروط (§16).",
    "return $input.all().map(i => ({ json: sc03RunGuard(i.json) }));"
  ].join('\n')));

  n.push(ifNode('08 — PASS?', [840, 20], '={{ $json.guard_status }}', 'PASS'));

  n.push(execWorkflow('09A — Execute SC-06 Manual Bridge', [1060, -80], PLACEHOLDER.SC06, 'SC-06 | Manual Publish Bridge'));
  n.push(execWorkflow('09B — Execute SC-05 Alerts', [1060, 140], PLACEHOLDER.SC05, 'SC-05 | Alerts & Recovery'));

  n.push(sticky(
    '### لماذا لا توجد عقدة نشر هنا؟\n\n' +
    'SC-02 (Social Publisher) **BLOCKED — META DEV LOOP**.\n' +
    'المسار الوحيد للنشر حاليًا: SC-06 -> طابور يدوي -> Meta Business Suite بيد المشغّل.',
    [1060, 320], [420, 160], 2));

  var c = conn({
    '01 — Receive Content': [['02 — Lookup Master Record']],
    '02 — Lookup Master Record': [['03 — Lookup Approval Record']],
    '03 — Lookup Approval Record': [['04 — Lookup Publish Package']],
    '04 — Lookup Publish Package': [['05 — Lookup Publish Log']],
    '05 — Lookup Publish Log': [['06 — Normalize Data']],
    '06 — Normalize Data': [['07 — Run Publish Guard']],
    '07 — Run Publish Guard': [['08 — PASS?']],
    '08 — PASS?': [['09A — Execute SC-06 Manual Bridge'], ['09B — Execute SC-05 Alerts']]
  });

  return write('SC-03-publish-guard.json', workflow('SC-03 | Publish Guard', n, c));
}

/* ==================================================================
 * SC-06 | Manual Publish Bridge
 * ================================================================== */

function buildSC06() {
  var n = [];

  n.push(sticky(
    '## SC-06 | Manual Publish Bridge\n\n' +
    'يستقبل **PASS** من SC-03 وينشئ صفًا واحدًا في **' + SHEET.queue + '**\n' +
    'بحالة `READY_FOR_MANUAL_PUBLISH`. **لا ينشر على Instagram بنفسه** (§22).\n\n' +
    'المسار الثاني (أسفل) يزامن الصفوف التي صارت PUBLISHED إلى **' + SHEET.publishLog + '** مرة واحدة (§26).',
    [-680, -300], [700, 240], 5));

  n.push(execTrigger('01 — Receive PASS Payload', [-680, 20]));
  n.push(sheetsRead('02 — Read Manual Queue', [-460, 20], SHEET.queue, { executeOnce: true }));

  n.push(codeNode('03 — Idempotency Check', [-240, 20], [
    "// §11 — Event Key واحد = صف واحد. لا نسخة ثانية أبدًا.",
    "const existing = {};",
    "try {",
    "  $('02 — Read Manual Queue').all().forEach(i => {",
    "    const k = text(field(i.json, ['Event Key']));",
    "    if (k) existing[k] = upper(field(i.json, ['State']));",
    "  });",
    "} catch (e) {}",
    "",
    "const seenThisRun = {};",
    "return $('01 — Receive PASS Payload').all().map(item => {",
    "  const d = item.json;",
    "  const dup = !!existing[d.event_key] || !!seenThisRun[d.event_key];",
    "  seenThisRun[d.event_key] = true;",
    "  return { json: Object.assign({}, d, {",
    "    queue_action: dup ? 'SKIP_EXISTS' : 'CREATE',",
    "    existing_state: existing[d.event_key] || ''",
    "  }) };",
    "});"
  ].join('\n')));

  n.push(ifNode('04 — Should Create?', [-20, 20], '={{ $json.queue_action }}', 'CREATE'));

  n.push(codeNode('05 — Build Queue Row', [200, -100], [
    "// نسخ حرفي من حزمة النشر المعتمدة. ممنوع توليد أو تعديل أي نص (§3).",
    "return $input.all().map(i => ({ json: Object.assign(",
    "  sc06BuildQueueRow(i.json, i.json.now_iso),",
    "  { __dry_run: i.json.dry_run, __run_id: i.json.run_id }",
    ") }));"
  ].join('\n')));

  n.push(ifNode('06 — Write Enabled?', [420, -100], '={{ $json.__dry_run }}', 'false'));

  n.push(codeNode('07 — Strip Internal Fields', [640, -180], [
    "// إزالة الحقول الداخلية قبل الكتابة حتى لا تُنشأ أعمدة دخيلة في الشيت.",
    "return $input.all().map(i => {",
    "  const row = Object.assign({}, i.json);",
    "  delete row.__dry_run; delete row.__run_id;",
    "  return { json: row };",
    "});"
  ].join('\n')));

  n.push(sheetsAppend('08 — Append Manual Queue Row', [860, -180], SHEET.queue));
  n.push(noOp('09 — DRY RUN (No Write)', [640, -20], 'DRY_RUN = true: لا كتابة في الطابور.'));

  n.push(codeNode('10 — Build READY Log Row', [1080, -180], [
    "return $input.all().map(i => ({ json: buildLogRow({",
    "  timestamp: i.json['Created At'], workflow: 'SC-06',",
    "  event_key: i.json['Event Key'], content_id: i.json['ID'],",
    "  state: 'READY_FOR_MANUAL_PUBLISH', reason: '',",
    "  details: { scheduled_at: i.json['Scheduled At'], platform: i.json['Platform'], format: i.json['Format'] }",
    "}) }));"
  ].join('\n')));

  n.push(sheetsAppend('11 — Log READY_FOR_MANUAL_PUBLISH', [1300, -180], SHEET.autoLog));

  n.push(codeNode('12 — Build Owner Notification', [1520, -180], [
    "// §23 — لم يُنشأ أي تكامل تنبيه جديد. النص جاهز؛ اربطه بعقدة تنبيه",
    "// قائمة لديك (Telegram / Gmail / Slack) إن أردت، دون إنشاء اعتماد جديد.",
    "return $input.all().map(i => {",
    "  const d = JSON.parse(i.json.Details || '{}');",
    "  return { json: { notification_text: [",
    "    i.json.ID + ' جاهز للنشر اليدوي.',",
    "    'الموعد: ' + (d.scheduled_at || ''),",
    "    'المنصة: ' + (d.platform || ''),",
    "    'الصيغة: ' + (d.format || ''),",
    "    'حالة QA: PASS',",
    "    'يرجى النشر من Meta Business Suite.'",
    "  ].join('\\n') } };",
    "});"
  ].join('\n')));

  n.push(noOp('13 — Notify Owner (Not Wired)', [1740, -180],
    'غير موصول عمدًا: لم يُنشأ اعتماد تنبيه جديد (§23). النص جاهز في العقدة السابقة.'));

  n.push(codeNode('14 — Skip (Already Queued)', [200, 160], [
    "return $input.all().map(i => ({ json: buildLogRow({",
    "  timestamp: i.json.now_iso, workflow: 'SC-06',",
    "  event_key: i.json.event_key, content_id: i.json.content_id,",
    "  state: 'SKIPPED_ALREADY_QUEUED',",
    "  reason: 'Event Key موجود بحالة ' + i.json.existing_state,",
    "  run_id: i.json.run_id, details: {}",
    "}) }));"
  ].join('\n')));

  // --- مسار المزامنة (§26) ---
  n.push(sticky('### مسار المزامنة — PUBLISHED إلى ' + SHEET.publishLog,
    [-680, 380], [520, 120], 6));

  n.push(node('20 — Schedule Sync Every 15m', 'n8n-nodes-base.scheduleTrigger', 1.2, [-680, 520], {
    rule: { interval: [{ field: 'minutes', minutesInterval: 15 }] }
  }));
  n.push(sheetsRead('21 — Read Manual Queue (Sync)', [-460, 520], SHEET.queue));
  n.push(sheetsRead('22 — Read Publish Log (Sync)', [-240, 520], SHEET.publishLog, { executeOnce: true }));

  n.push(codeNode('23 — Find Unsynced PUBLISHED', [-20, 520], [
    "// يضيف فقط ما لم يُسجَّل من قبل — لا Duplicate ولا تعديل صف قائم.",
    "const rows = (name) => { try { return $(name).all().map(i => i.json); } catch (e) { return []; } };",
    "const pending = sc06FindUnsyncedPublished(",
    "  rows('21 — Read Manual Queue (Sync)'),",
    "  rows('22 — Read Publish Log (Sync)')",
    ");",
    "return pending.map(r => ({ json: r }));"
  ].join('\n')));

  n.push(sheetsAppend('24 — Append To Publish Log', [200, 520], SHEET.publishLog));

  n.push(codeNode('25 — Build PUBLISHED Log Row', [420, 520], [
    "return $input.all().map(i => ({ json: buildLogRow({",
    "  timestamp: new Date().toISOString(), workflow: 'SC-06',",
    "  event_key: '', content_id: i.json.ID, state: 'PUBLISHED',",
    "  reason: 'مزامنة من طابور النشر اليدوي',",
    "  details: { url: i.json['رابط المنشور'], platform: i.json['المنصة'] }",
    "}) }));"
  ].join('\n')));

  n.push(sheetsAppend('26 — Log PUBLISHED', [640, 520], SHEET.autoLog));

  var c = conn({
    '01 — Receive PASS Payload': [['02 — Read Manual Queue']],
    '02 — Read Manual Queue': [['03 — Idempotency Check']],
    '03 — Idempotency Check': [['04 — Should Create?']],
    '04 — Should Create?': [['05 — Build Queue Row'], ['14 — Skip (Already Queued)']],
    '05 — Build Queue Row': [['06 — Write Enabled?']],
    '06 — Write Enabled?': [['07 — Strip Internal Fields'], ['09 — DRY RUN (No Write)']],
    '07 — Strip Internal Fields': [['08 — Append Manual Queue Row']],
    '08 — Append Manual Queue Row': [['10 — Build READY Log Row']],
    '10 — Build READY Log Row': [['11 — Log READY_FOR_MANUAL_PUBLISH']],
    '11 — Log READY_FOR_MANUAL_PUBLISH': [['12 — Build Owner Notification']],
    '12 — Build Owner Notification': [['13 — Notify Owner (Not Wired)']],
    '20 — Schedule Sync Every 15m': [['21 — Read Manual Queue (Sync)']],
    '21 — Read Manual Queue (Sync)': [['22 — Read Publish Log (Sync)']],
    '22 — Read Publish Log (Sync)': [['23 — Find Unsynced PUBLISHED']],
    '23 — Find Unsynced PUBLISHED': [['24 — Append To Publish Log']],
    '24 — Append To Publish Log': [['25 — Build PUBLISHED Log Row']],
    '25 — Build PUBLISHED Log Row': [['26 — Log PUBLISHED']]
  });

  return write('SC-06-manual-publish-bridge.json', workflow('SC-06 | Manual Publish Bridge', n, c));
}

/* ==================================================================
 * SC-05 | Alerts & Recovery
 * ================================================================== */

function buildSC05() {
  var n = [];

  n.push(sticky(
    '## SC-05 | Alerts & Recovery\n\n' +
    'يستقبل `BLOCKED` / `MISSED_WINDOW` من SC-01/SC-03، ويلتقط أخطاء التنفيذ عبر **Error Trigger**.\n\n' +
    '**سياسة إعادة المحاولة (§24):** الأخطاء التقنية المؤقتة فقط، محاولتان إضافيتان بحد أقصى —\n' +
    'وهي مضبوطة على عقد Google Sheets نفسها (`retryOnFail`, `maxTries: 3`) فلا يمكن حدوث Infinite Retry.\n' +
    'أسباب حظر قواعد العمل (QA_VISUAL_NOT_PASS…) **لا يُعاد تنفيذها أبدًا** — تنتظر تعديل البيانات.',
    [-680, -320], [760, 260], 1));

  n.push(execTrigger('01 — Receive Event', [-680, 40]));

  n.push(node('01b — Error Trigger', 'n8n-nodes-base.errorTrigger', 1, [-680, 260], {}, {
    notes: 'اضبط هذا السير كـError Workflow في إعدادات SC-01 / SC-03 / SC-06.'
  }));

  n.push(codeNode('02 — Normalize Error Event', [-460, 260], [
    "// يحوّل خطأ التنفيذ إلى نفس شكل الحدث القادم من SC-01/SC-03.",
    "return $input.all().map(i => {",
    "  const e = i.json || {};",
    "  const wf = (e.workflow && e.workflow.name) || 'UNKNOWN';",
    "  const msg = (e.execution && e.execution.error && e.execution.error.message) || 'Unknown execution error';",
    "  const nodeName = (e.execution && e.execution.lastNodeExecuted) || '';",
    "  return { json: {",
    "    state: 'ERROR', event_key: '', content_id: '',",
    "    block_reasons: ['EXECUTION_ERROR'],",
    "    source_workflow: wf, error_message: msg, error_node: nodeName,",
    "    run_id: (e.execution && e.execution.id) || '',",
    "    now_iso: formatIsoWithOffset(new Date(), '" + TZ + "')",
    "  } };",
    "});"
  ].join('\n')));

  n.push(sheetsRead('03 — Read Automation Log', [-240, 140], SHEET.autoLog, { executeOnce: true }));

  n.push(codeNode('04 — Classify & Dedupe', [-20, 140], [
    "// يصنّف الحدث ويمنع تكرار التنبيه لنفس Event Key بنفس الحالة (§34).",
    "let logRows = [];",
    "try { logRows = $('03 — Read Automation Log').all().map(i => i.json); } catch (e) {}",
    "",
    "const seen = [];",
    "return $input.all().map(item => {",
    "  const evt = item.json;",
    "  const d = sc05Decide(evt, logRows.concat(seen));",
    "  const row = buildLogRow({",
    "    timestamp: evt.now_iso || formatIsoWithOffset(new Date(), '" + TZ + "'),",
    "    workflow: 'SC-05',",
    "    event_key: evt.event_key, content_id: evt.content_id,",
    "    state: evt.state,",
    "    reason: evt.block_reasons || evt.error_message || '',",
    "    run_id: evt.run_id,",
    "    details: {",
    "      category: d.category,",
    "      retry_allowed: d.retry_allowed,",
    "      max_additional_retries: d.max_additional_retries,",
    "      source_workflow: evt.source_workflow || '',",
    "      error_node: evt.error_node || '',",
    "      scheduled_at: evt.scheduled_at || ''",
    "    }",
    "  });",
    "  if (d.should_log) seen.push(row);",
    "  return { json: Object.assign({}, row, {",
    "    __should_log: d.should_log && evt.dry_run !== true,",
    "    __category: d.category,",
    "    __retry_allowed: d.retry_allowed",
    "  }) };",
    "});"
  ].join('\n')));

  n.push(ifNode('05 — Should Log?', [200, 140], '={{ $json.__should_log }}', 'true'));

  n.push(codeNode('06 — Strip Internal Fields', [420, 40], [
    "return $input.all().map(i => {",
    "  const row = Object.assign({}, i.json);",
    "  Object.keys(row).forEach(k => { if (k.indexOf('__') === 0) delete row[k]; });",
    "  return { json: row };",
    "});"
  ].join('\n')));

  n.push(sheetsAppend('07 — Append Automation Log', [640, 40], SHEET.autoLog));

  n.push(noOp('08 — Already Reported (Suppress)', [420, 260],
    'تنبيه مكرر لنفس Event Key والحالة — مكتوم عمدًا لمنع إغراق السجل كل 15 دقيقة.'));

  n.push(codeNode('09 — Build Owner Notification', [860, 40], [
    "// §23 — نص جاهز فقط. لم يُنشأ أي تكامل تنبيه جديد.",
    "return $input.all().map(i => ({ json: { notification_text: [",
    "  '[' + i.json.State + '] ' + (i.json.ID || i.json.Workflow),",
    "  'السبب: ' + (i.json.Reason || '—'),",
    "  'الوقت: ' + i.json.Timestamp,",
    "  i.json.State === 'BLOCKED' ? 'لا نشر. عدّل البيانات في Master Control ثم انتظر الدورة التالية.' : ''",
    "].filter(Boolean).join('\\n') } }));"
  ].join('\n')));

  n.push(noOp('10 — Notify Owner (Not Wired)', [1080, 40],
    'غير موصول عمدًا (§23). اربطه باعتماد تنبيه قائم لديك إن أردت.'));

  var c = conn({
    '01 — Receive Event': [['03 — Read Automation Log']],
    '01b — Error Trigger': [['02 — Normalize Error Event']],
    '02 — Normalize Error Event': [['03 — Read Automation Log']],
    '03 — Read Automation Log': [['04 — Classify & Dedupe']],
    '04 — Classify & Dedupe': [['05 — Should Log?']],
    '05 — Should Log?': [['06 — Strip Internal Fields'], ['08 — Already Reported (Suppress)']],
    '06 — Strip Internal Fields': [['07 — Append Automation Log']],
    '07 — Append Automation Log': [['09 — Build Owner Notification']],
    '09 — Build Owner Notification': [['10 — Notify Owner (Not Wired)']]
  });

  return write('SC-05-alerts-recovery.json', workflow('SC-05 | Alerts & Recovery', n, c));
}

/* ================================================================== */

var files = [buildSC01(), buildSC03(), buildSC05(), buildSC06()];
files.forEach(function (f) {
  var wf = JSON.parse(fs.readFileSync(path.join(OUT, f), 'utf8'));
  console.log('  ' + f + '  —  ' + wf.nodes.length + ' عقدة، timezone=' + wf.settings.timezone + ', active=' + wf.active);
});
console.log('\nتم توليد ' + files.length + ' ملفات في ' + path.relative(process.cwd(), OUT));
