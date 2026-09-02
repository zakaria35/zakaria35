/*
 * Shaghaf Content Factory — Automation Core
 * ------------------------------------------------------------------
 * المصدر الوحيد لمنطق: التوقيت، تطبيع الصفوف، Event Key، وPublish Guard.
 * هذا الملف يُحقن حرفيًا داخل عقد Code في n8n بواسطة build/build.js،
 * ونفس الملف تختبره tests/run-tests.js — فلا يمكن أن يفترق المُختبَر عن المُشغَّل.
 *
 * قاعدة حاكمة: هذا الكود منفّذ لا مُقرِّر. لا يكتب محتوى علميًا، ولا يعيد صياغة
 * caption، ولا يخفف أي شرط اعتماد. كل ما يفعله: يقرأ الحقائق ويصدر PASS/BLOCKED.
 */

var SC_TIMEZONE_DEFAULT = 'Asia/Jerusalem';

/* ==================================================================
 * 1) التوقيت — Asia/Jerusalem صراحةً
 * ================================================================== */

/** إزاحة المنطقة الزمنية بالدقائق عند لحظة UTC معيّنة (تراعي التوقيت الصيفي). */
function tzOffsetMinutes(utcDate, tz) {
  var dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour12: false,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  });
  var parts = {};
  var list = dtf.formatToParts(utcDate);
  for (var i = 0; i < list.length; i++) parts[list[i].type] = list[i].value;
  var hour = parts.hour === '24' ? '00' : parts.hour;
  var asUTC = Date.UTC(
    Number(parts.year), Number(parts.month) - 1, Number(parts.day),
    Number(hour), Number(parts.minute), Number(parts.second)
  );
  return (asUTC - utcDate.getTime()) / 60000;
}

/**
 * يحوّل تاريخًا/وقتًا "محليًا في tz" إلى لحظة UTC حقيقية.
 * 2026-09-02 20:00 + Asia/Jerusalem  ->  2026-09-02T17:00:00Z
 * التمريرة الثانية تصحّح الحالة الحدّية عند تبديل التوقيت الصيفي.
 */
function zonedToUtc(y, mo, d, hh, mm, tz) {
  var naive = Date.UTC(y, mo - 1, d, hh, mm, 0, 0);
  var off = tzOffsetMinutes(new Date(naive), tz);
  var ts = naive - off * 60000;
  off = tzOffsetMinutes(new Date(ts), tz);
  ts = naive - off * 60000;
  return new Date(ts);
}

function pad2(n) { return (n < 10 ? '0' : '') + n; }

/** ISO-8601 بإزاحة المنطقة الظاهرة: 2026-09-02T20:00:00+03:00 */
function formatIsoWithOffset(utcDate, tz) {
  var off = tzOffsetMinutes(utcDate, tz);
  var local = new Date(utcDate.getTime() + off * 60000);
  var sign = off >= 0 ? '+' : '-';
  var abs = Math.abs(off);
  return local.getUTCFullYear() + '-' + pad2(local.getUTCMonth() + 1) + '-' + pad2(local.getUTCDate()) +
    'T' + pad2(local.getUTCHours()) + ':' + pad2(local.getUTCMinutes()) + ':' + pad2(local.getUTCSeconds()) +
    sign + pad2(Math.floor(abs / 60)) + ':' + pad2(abs % 60);
}

/** يقرأ خانة تاريخ من Sheets: نص ISO، أو d/m/Y، أو كائن Date. */
function parseSheetDate(value) {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date && !isNaN(value.getTime())) {
    return { y: value.getUTCFullYear(), mo: value.getUTCMonth() + 1, d: value.getUTCDate() };
  }
  var s = String(value).trim();
  var m = s.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
  if (m) return { y: Number(m[1]), mo: Number(m[2]), d: Number(m[3]) };
  m = s.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
  if (m) return { y: Number(m[3]), mo: Number(m[2]), d: Number(m[1]) };
  return null;
}

/** يقرأ خانة وقت من Sheets: "20:00"، "20:00:00"، كائن Date، أو كسر تسلسلي. */
function parseSheetTime(value) {
  if (value === null || value === undefined || value === '') return null;
  if (value instanceof Date && !isNaN(value.getTime())) {
    return { hh: value.getUTCHours(), mm: value.getUTCMinutes() };
  }
  if (typeof value === 'number' && isFinite(value)) {
    var frac = value - Math.floor(value);
    var mins = Math.round(frac * 24 * 60);
    return { hh: Math.floor(mins / 60) % 24, mm: mins % 60 };
  }
  var s = String(value).trim();
  var m = s.match(/(\d{1,2}):(\d{2})/);
  if (!m) return null;
  var hh = Number(m[1]);
  var mm = Number(m[2]);
  if (/pm/i.test(s) && hh < 12) hh += 12;
  if (/am/i.test(s) && hh === 12) hh = 0;
  if (hh > 23 || mm > 59) return null;
  return { hh: hh, mm: mm };
}

/** يبني scheduled_at من (التاريخ + الوقت) مفسَّرين صراحةً في tz. */
function buildScheduledAt(dateValue, timeValue, tz) {
  var d = parseSheetDate(dateValue);
  var t = parseSheetTime(timeValue);
  if (!d || !t) return null;
  var utc = zonedToUtc(d.y, d.mo, d.d, t.hh, t.mm, tz);
  return { utc: utc, iso: formatIsoWithOffset(utc, tz) };
}

/* ==================================================================
 * 2) قراءة الأعمدة بالاسم لا بالرقم
 * ================================================================== */

/** توحيد اسم العمود: مسافات، تطويل، محارف اتجاهية، أشكال يونيكود. */
function normHeader(name) {
  return String(name === null || name === undefined ? '' : name)
    .normalize('NFKC')
    .replace(/[ـ‎‏‪-‮⁦-⁩]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

/** يجلب قيمة عمود من صف عبر اسمه أو أي اسم بديل. لا يعتمد على ترتيب الأعمدة. */
function field(row, names) {
  if (!row) return '';
  var wanted = Array.isArray(names) ? names : [names];
  var index = {};
  var keys = Object.keys(row);
  for (var i = 0; i < keys.length; i++) index[normHeader(keys[i])] = row[keys[i]];
  for (var j = 0; j < wanted.length; j++) {
    var k = normHeader(wanted[j]);
    if (Object.prototype.hasOwnProperty.call(index, k)) {
      var v = index[k];
      return v === null || v === undefined ? '' : v;
    }
  }
  return '';
}

/** نص مُشذّب للمقارنة الحرفية. */
function text(value) {
  return String(value === null || value === undefined ? '' : value)
    .normalize('NFKC')
    .replace(/[ـ‎‏‪-‮⁦-⁩]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function upper(value) { return text(value).toUpperCase(); }

/** بحث عن صف بالـID داخل مصفوفة صفوف. */
function findById(rows, id, idNames) {
  var target = text(id);
  if (!target) return null;
  var names = idNames || ['ID'];
  for (var i = 0; i < (rows || []).length; i++) {
    if (text(field(rows[i], names)) === target) return rows[i];
  }
  return null;
}

/* ==================================================================
 * 3) Event Key — منع التكرار
 * ================================================================== */

/** content_id | scheduled_at | channel | post_type */
function buildEventKey(contentId, scheduledAtIso, channel, postType) {
  return [text(contentId), text(scheduledAtIso), text(channel), text(postType)].join('|');
}

/* ==================================================================
 * 4) تطبيع صف التقويم -> مرشّح
 * ================================================================== */

var CAL = {
  id: ['ID'],
  date: ['التاريخ'],
  time: ['الوقت'],
  topic: ['الموضوع'],
  postType: ['نوع المنشور'],
  channel: ['القناة'],
  prodStatus: ['حالة الإنتاج'],
  sciStatus: ['الحالة العلمية'],
  cta: ['CTA']
};

function normalizeCalendarRow(row, tz) {
  var id = text(field(row, CAL.id));
  var built = buildScheduledAt(field(row, CAL.date), field(row, CAL.time), tz);
  var channel = text(field(row, CAL.channel));
  var postType = text(field(row, CAL.postType));
  return {
    content_id: id,
    topic: text(field(row, CAL.topic)),
    platform: channel,
    channel: channel,
    post_type: postType,
    format: postType,
    cta: text(field(row, CAL.cta)),
    calendar_status: text(field(row, CAL.prodStatus)),
    calendar_science_status: text(field(row, CAL.sciStatus)),
    scheduled_at: built ? built.iso : '',
    scheduled_at_ms: built ? built.utc.getTime() : null,
    event_key: built ? buildEventKey(id, built.iso, channel, postType) : ''
  };
}

/* ==================================================================
 * 5) نافذة الاستحقاق
 * ================================================================== */

/**
 * DUE            : now - LOOKBACK_HOURS <= scheduled_at <= now + LEAD_MINUTES
 * MISSED_WINDOW  : scheduled_at أقدم من نافذة الاسترجاع ولم يُنشر  -> تنبيه فقط، بلا طابور
 * NOT_DUE        : لم يحن بعد
 * INVALID_SCHEDULE : تعذّر بناء scheduled_at
 */
function classifyWindow(candidate, nowMs, leadMinutes, lookbackHours) {
  if (candidate.scheduled_at_ms === null) return 'INVALID_SCHEDULE';
  var upperBound = nowMs + leadMinutes * 60000;
  var lowerBound = nowMs - lookbackHours * 3600000;
  if (candidate.scheduled_at_ms > upperBound) return 'NOT_DUE';
  if (candidate.scheduled_at_ms < lowerBound) return 'MISSED_WINDOW';
  return 'DUE';
}

/* ==================================================================
 * 6) تطبيع بيانات Publish Guard
 * ================================================================== */

var MASTER = {
  id: ['ID'],
  science: ['حالة التدقيق العلمي'],
  production: ['حالة الإنتاج'],
  approvedAsset: ['رابط الملف المعتمد'],
  v2: ['نسخة V2'],
  topic: ['الموضوع']
};

var APPROVAL = {
  id: ['ID'],
  science: ['QA علمي'],
  language: ['QA لغوي'],
  pedagogy: ['QA تربوي'],
  visual: ['QA بصري'],
  status: ['حالة الاعتماد'],
  reason: ['سبب الرفض/المراجعة', 'سبب الرفض / المراجعة']
};

var PACKAGE = {
  id: ['ID'],
  version: ['Version'],
  status: ['Status'],
  caption: ['Caption'],
  altText: ['Alt Text'],
  pinned: ['Pinned Comment'],
  storyBefore: ['Story Before'],
  storyAfter: ['Story After'],
  hashtags: ['Hashtags']
};

var PUBLOG = {
  id: ['ID'],
  platform: ['المنصة'],
  format: ['صيغة النشر'],
  date: ['تاريخ النشر'],
  url: ['رابط المنشور'],
  status: ['حالة النشر']
};

/** هل السجل في سجل النشر يعني "منشور فعلًا"؟ */
function isPublishedState(value) {
  var v = upper(value);
  return v.indexOf('PUBLISHED') !== -1 || text(value).indexOf('منشور') !== -1;
}

/**
 * يبني الكائن الموحّد الذي يستهلكه Publish Guard.
 * masterRow / approvalRow / packageRow قد تكون null — الحارس يتعامل مع ذلك.
 */
function buildNormalized(candidate, masterRow, approvalRow, packageRow, publishLogRows) {
  var alreadyPublished = false;
  var rows = publishLogRows || [];
  for (var i = 0; i < rows.length; i++) {
    if (text(field(rows[i], PUBLOG.id)) === text(candidate.content_id) &&
        isPublishedState(field(rows[i], PUBLOG.status))) {
      alreadyPublished = true;
      break;
    }
  }

  return {
    event_key: candidate.event_key,
    content_id: candidate.content_id,
    topic: candidate.topic || text(field(masterRow, MASTER.topic)),
    platform: candidate.platform,
    post_type: candidate.post_type,
    format: candidate.format || candidate.post_type,
    cta: candidate.cta || '',
    scheduled_at: candidate.scheduled_at,
    calendar_status: candidate.calendar_status,

    master_record_found: !!masterRow,
    science_status: text(field(masterRow, MASTER.science)),
    production_status: text(field(masterRow, MASTER.production)),
    approved_asset_url: text(field(masterRow, MASTER.approvedAsset)),
    v2_version: text(field(masterRow, MASTER.v2)),

    approval_record_found: !!approvalRow,
    qa_science: text(field(approvalRow, APPROVAL.science)),
    qa_language: text(field(approvalRow, APPROVAL.language)),
    qa_pedagogy: text(field(approvalRow, APPROVAL.pedagogy)),
    qa_visual: text(field(approvalRow, APPROVAL.visual)),
    approval_status: text(field(approvalRow, APPROVAL.status)),
    approval_reason: text(field(approvalRow, APPROVAL.reason)),

    package_found: !!packageRow,
    package_version: text(field(packageRow, PACKAGE.version)),
    package_status: text(field(packageRow, PACKAGE.status)),
    caption: String(field(packageRow, PACKAGE.caption) || ''),
    alt_text: String(field(packageRow, PACKAGE.altText) || ''),
    pinned_comment: String(field(packageRow, PACKAGE.pinned) || ''),
    story_before: String(field(packageRow, PACKAGE.storyBefore) || ''),
    story_after: String(field(packageRow, PACKAGE.storyAfter) || ''),
    hashtags: String(field(packageRow, PACKAGE.hashtags) || ''),

    already_published: alreadyPublished
  };
}

/* ==================================================================
 * 7) Publish Guard — القرار
 * ================================================================== */

var SCIENCE_APPROVED_LITERAL = 'مدققة علميًا وجاهزة للإنتاج';

/** قيم تنقض أي ادعاء اعتماد حتى لو ظهرت كلمة APPROVED في النص. */
var NEGATING_TOKENS = ['NEEDS REVIEW', 'PENDING', 'DRAFT', 'BLOCKED', 'REJECT', 'HOLD', 'REQUIRES', 'AWAITING'];

function hasNegatingToken(value) {
  var v = upper(value);
  for (var i = 0; i < NEGATING_TOKENS.length; i++) {
    if (v.indexOf(NEGATING_TOKENS[i]) !== -1) return true;
  }
  return false;
}

/**
 * لا يمر شيء إلا باستيفاء كل الشروط. الترتيب مقصود: أسباب الحظر تُجمع كلها
 * ولا نتوقف عند أول سبب — لأن §35 يطلب صورة كاملة لسبب الحظر.
 */
function runPublishGuard(d) {
  var reasons = [];

  if (!d.master_record_found) reasons.push('MASTER_RECORD_MISSING');
  if (!d.approval_record_found) reasons.push('APPROVAL_RECORD_MISSING');

  if (text(d.science_status) !== SCIENCE_APPROVED_LITERAL) reasons.push('SCIENCE_NOT_APPROVED');

  if (upper(d.qa_science) !== 'PASS') reasons.push('QA_SCIENCE_NOT_PASS');
  if (upper(d.qa_language) !== 'PASS') reasons.push('QA_LANGUAGE_NOT_PASS');
  if (upper(d.qa_pedagogy) !== 'PASS') reasons.push('QA_PEDAGOGY_NOT_PASS');
  if (upper(d.qa_visual) !== 'PASS') reasons.push('QA_VISUAL_NOT_PASS');

  if (upper(d.approval_status) !== 'APPROVED') reasons.push('FINAL_APPROVAL_MISSING');

  // §16.7 — حالة الإنتاج يجب أن تدل بوضوح على APPROVED / READY TO PUBLISH.
  // تشديد مقصود: "APPROVED — PENDING FIX" لا يُعتبر اعتمادًا.
  if (!d.production_status || upper(d.production_status).indexOf('APPROVED') === -1) {
    reasons.push('PRODUCTION_NOT_APPROVED');
  } else if (hasNegatingToken(d.production_status)) {
    reasons.push('PRODUCTION_APPROVAL_CONDITIONAL');
  }

  if (!text(d.approved_asset_url)) reasons.push('APPROVED_ASSET_MISSING');

  if (!text(d.v2_version)) reasons.push('V2_VERSION_MISSING');
  else if (hasNegatingToken(d.v2_version)) reasons.push('V2_VERSION_PENDING');

  if (!d.package_found) reasons.push('PUBLISH_PACKAGE_NOT_FOUND');
  if (upper(d.package_status) !== 'APPROVED') reasons.push('PUBLISH_PACKAGE_NOT_APPROVED');

  if (!text(d.caption)) reasons.push('CAPTION_MISSING');

  if (d.already_published === true) reasons.push('ALREADY_PUBLISHED');

  var unique = [];
  for (var i = 0; i < reasons.length; i++) {
    if (unique.indexOf(reasons[i]) === -1) unique.push(reasons[i]);
  }

  return {
    guard_status: unique.length === 0 ? 'PASS' : 'BLOCKED',
    block_reasons: unique
  };
}

/* ==================================================================
 * 8) تصنيف أحداث SC-05 — أي خطأ يستحق إعادة المحاولة؟
 * ================================================================== */

/** أسباب حظر ناتجة عن قواعد العمل: لا إعادة محاولة إطلاقًا، ننتظر تعديل البيانات. */
var BUSINESS_BLOCK_REASONS = [
  'MASTER_RECORD_MISSING', 'APPROVAL_RECORD_MISSING', 'SCIENCE_NOT_APPROVED',
  'QA_SCIENCE_NOT_PASS', 'QA_LANGUAGE_NOT_PASS', 'QA_PEDAGOGY_NOT_PASS', 'QA_VISUAL_NOT_PASS',
  'FINAL_APPROVAL_MISSING', 'PRODUCTION_NOT_APPROVED', 'PRODUCTION_APPROVAL_CONDITIONAL',
  'APPROVED_ASSET_MISSING', 'V2_VERSION_MISSING', 'V2_VERSION_PENDING',
  'PUBLISH_PACKAGE_NOT_FOUND', 'PUBLISH_PACKAGE_NOT_APPROVED', 'CAPTION_MISSING',
  'ALREADY_PUBLISHED'
];

function classifyAlertEvent(evt) {
  var state = upper(evt && evt.state);
  if (state === 'ERROR') {
    return { category: 'TECHNICAL_ERROR', retry_allowed: true, max_additional_retries: 2 };
  }
  if (state === 'MISSED_WINDOW') {
    return { category: 'MISSED_WINDOW', retry_allowed: false, max_additional_retries: 0 };
  }
  return { category: 'BUSINESS_BLOCK', retry_allowed: false, max_additional_retries: 0 };
}

/* ================================================================== */

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    SC_TIMEZONE_DEFAULT: SC_TIMEZONE_DEFAULT,
    SCIENCE_APPROVED_LITERAL: SCIENCE_APPROVED_LITERAL,
    BUSINESS_BLOCK_REASONS: BUSINESS_BLOCK_REASONS,
    tzOffsetMinutes: tzOffsetMinutes,
    zonedToUtc: zonedToUtc,
    formatIsoWithOffset: formatIsoWithOffset,
    parseSheetDate: parseSheetDate,
    parseSheetTime: parseSheetTime,
    buildScheduledAt: buildScheduledAt,
    normHeader: normHeader,
    field: field,
    text: text,
    upper: upper,
    findById: findById,
    buildEventKey: buildEventKey,
    normalizeCalendarRow: normalizeCalendarRow,
    classifyWindow: classifyWindow,
    isPublishedState: isPublishedState,
    buildNormalized: buildNormalized,
    hasNegatingToken: hasNegatingToken,
    runPublishGuard: runPublishGuard,
    classifyAlertEvent: classifyAlertEvent
  };
}
