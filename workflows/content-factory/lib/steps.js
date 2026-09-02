/*
 * Shaghaf Content Factory — Step Logic
 * ------------------------------------------------------------------
 * منطق كل عقدة Code في SC-01 / SC-03 / SC-05 / SC-06، كدوال نقية.
 * يعتمد على lib/core.js. يُحقن حرفيًا داخل n8n، ويُختبر كما هو.
 */

/* eslint-disable no-undef */
var __core = (typeof module !== 'undefined' && module.exports) ? require('./core.js') : null;
var _f     = __core ? __core.field                : field;
var _t     = __core ? __core.text                 : text;
var _u     = __core ? __core.upper                : upper;
var _find  = __core ? __core.findById             : findById;
var _norm  = __core ? __core.normalizeCalendarRow : normalizeCalendarRow;
var _class = __core ? __core.classifyWindow       : classifyWindow;
var _built = __core ? __core.buildNormalized      : buildNormalized;
var _guard = __core ? __core.runPublishGuard      : runPublishGuard;
var _pubst = __core ? __core.isPublishedState     : isPublishedState;
var _alert = __core ? __core.classifyAlertEvent   : classifyAlertEvent;

/* ==================================================================
 * SC-01 — بناء المرشحين
 * ================================================================== */

var QUEUE_ACTIVE_STATES = ['READY_FOR_MANUAL_PUBLISH', 'PUBLISHED'];

function sc01BuildCandidates(input) {
  var cfg = input.config;
  var tz = cfg.TIMEZONE;
  var nowMs = input.nowMs;
  var out = [];

  var queueIndex = {};
  (input.queueRows || []).forEach(function (r) {
    var k = _t(_f(r, ['Event Key']));
    if (!k) return;
    var st = _u(_f(r, ['State']));
    if (QUEUE_ACTIVE_STATES.indexOf(st) !== -1) queueIndex[k] = st;
  });

  var publishedIds = {};
  (input.publishLogRows || []).forEach(function (r) {
    if (_pubst(_f(r, ['حالة النشر']))) publishedIds[_t(_f(r, ['ID']))] = true;
  });

  var alertedMissed = {};
  (input.autoLogRows || []).forEach(function (r) {
    if (_u(_f(r, ['State'])) === 'MISSED_WINDOW') alertedMissed[_t(_f(r, ['Event Key']))] = true;
  });

  (input.calendarRows || []).forEach(function (row) {
    var c = _norm(row, tz);
    if (!c.content_id) return;

    if (!c.event_key) {
      out.push(Object.assign({}, c, {
        route: 'INVALID_SCHEDULE', state: 'ERROR',
        reason: 'INVALID_SCHEDULE — تعذّر بناء scheduled_at من التاريخ/الوقت'
      }));
      return;
    }

    var win = _class(c, nowMs, cfg.LEAD_MINUTES, cfg.LOOKBACK_HOURS);
    if (win === 'NOT_DUE') return;

    if (publishedIds[c.content_id]) {
      out.push(Object.assign({}, c, {
        route: 'SKIP', state: 'SKIPPED_ALREADY_PUBLISHED',
        reason: 'العنصر مسجَّل PUBLISHED في سجل النشر'
      }));
      return;
    }

    if (queueIndex[c.event_key]) {
      out.push(Object.assign({}, c, {
        route: 'SKIP', state: 'SKIPPED_ALREADY_QUEUED',
        reason: 'Event Key موجود في طابور النشر اليدوي بحالة ' + queueIndex[c.event_key]
      }));
      return;
    }

    if (win === 'MISSED_WINDOW') {
      out.push(Object.assign({}, c, {
        route: alertedMissed[c.event_key] ? 'SKIP' : 'MISSED_WINDOW',
        state: alertedMissed[c.event_key] ? 'MISSED_WINDOW_ALREADY_ALERTED' : 'MISSED_WINDOW',
        reason: 'فات موعد النشر بأكثر من LOOKBACK_HOURS ولم يُنشر — تنبيه فقط، بلا نشر تلقائي'
      }));
      return;
    }

    out.push(Object.assign({}, c, { route: 'DUE', state: 'CANDIDATE', reason: '' }));
  });

  return out;
}

/* ==================================================================
 * SC-03 — التطبيع ثم الحارس
 * ================================================================== */

function sc03Normalize(input) {
  var c = input.candidate;
  return _built(
    c,
    _find(input.masterRows, c.content_id),
    _find(input.approvalRows, c.content_id),
    _find(input.packageRows, c.content_id),
    input.publishLogRows
  );
}

function sc03RunGuard(normalized) {
  var verdict = _guard(normalized);
  return Object.assign({}, normalized, {
    guard_status: verdict.guard_status,
    block_reasons: verdict.block_reasons,
    state: verdict.guard_status === 'PASS' ? 'PASS' : 'BLOCKED'
  });
}

/* ==================================================================
 * SC-06 — صف طابور النشر اليدوي
 * ================================================================== */

var QUEUE_HEADERS = [
  'Event Key', 'ID', 'Scheduled At', 'Platform', 'Format', 'Topic', 'CTA',
  'Approved Asset URL', 'Caption', 'Alt Text', 'Pinned Comment',
  'State', 'Created At', 'Published At', 'Published URL', 'Operator Note'
];

function sc06BuildQueueRow(d, createdAtIso) {
  return {
    'Event Key': d.event_key,
    'ID': d.content_id,
    'Scheduled At': d.scheduled_at,
    'Platform': d.platform,
    'Format': d.format || d.post_type,
    'Topic': d.topic,
    'CTA': d.cta || '',
    'Approved Asset URL': d.approved_asset_url,
    'Caption': d.caption,
    'Alt Text': d.alt_text,
    'Pinned Comment': d.pinned_comment,
    'State': 'READY_FOR_MANUAL_PUBLISH',
    'Created At': createdAtIso,
    'Published At': '',
    'Published URL': '',
    'Operator Note': 'انشر يدويًا من Meta Business Suite ثم حدّث State إلى PUBLISHED وأضف Published URL.'
  };
}

function sc06FindUnsyncedPublished(queueRows, publishLogRows) {
  var seen = {};
  (publishLogRows || []).forEach(function (r) {
    seen[_t(_f(r, ['ID'])) + '|' + _t(_f(r, ['رابط المنشور']))] = true;
  });

  var pending = [];
  (queueRows || []).forEach(function (r) {
    if (_u(_f(r, ['State'])) !== 'PUBLISHED') return;
    var url = _t(_f(r, ['Published URL']));
    var id = _t(_f(r, ['ID']));
    if (!url || !id) return;
    if (seen[id + '|' + url]) return;
    seen[id + '|' + url] = true;
    pending.push({
      'ID': id,
      'المنصة': _t(_f(r, ['Platform'])),
      'صيغة النشر': _t(_f(r, ['Format'])),
      'تاريخ النشر': _t(_f(r, ['Published At'])) || _t(_f(r, ['Scheduled At'])),
      'رابط المنشور': url,
      'حالة النشر': 'PUBLISHED',
      'ملاحظات الأداء': ''
    });
  });
  return pending;
}

/* ==================================================================
 * SC-05 — قرار التنبيه والتسجيل
 * ================================================================== */

function sc05Decide(evt, autoLogRows) {
  var cls = _alert(evt);
  var key = _t(evt.event_key);
  var already = false;
  (autoLogRows || []).forEach(function (r) {
    if (_t(_f(r, ['Event Key'])) === key && _u(_f(r, ['State'])) === _u(evt.state)) already = true;
  });

  return Object.assign({}, cls, {
    event_key: key,
    already_reported: already,
    should_log: !already,
    should_notify: !already
  });
}

/* ==================================================================
 * سجل الأتمتة
 * ================================================================== */

var LOG_HEADERS = ['Timestamp', 'Workflow', 'Event Key', 'ID', 'State', 'Reason', 'Run ID', 'Details'];

function buildLogRow(o) {
  return {
    'Timestamp': o.timestamp,
    'Workflow': o.workflow,
    'Event Key': o.event_key || '',
    'ID': o.content_id || '',
    'State': o.state,
    'Reason': Array.isArray(o.reason) ? o.reason.join(', ') : (o.reason || ''),
    'Run ID': o.run_id || '',
    'Details': typeof o.details === 'string' ? o.details : JSON.stringify(o.details || {})
  };
}

/* ================================================================== */

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    QUEUE_HEADERS: QUEUE_HEADERS,
    LOG_HEADERS: LOG_HEADERS,
    QUEUE_ACTIVE_STATES: QUEUE_ACTIVE_STATES,
    sc01BuildCandidates: sc01BuildCandidates,
    sc03Normalize: sc03Normalize,
    sc03RunGuard: sc03RunGuard,
    sc06BuildQueueRow: sc06BuildQueueRow,
    sc06FindUnsyncedPublished: sc06FindUnsyncedPublished,
    sc05Decide: sc05Decide,
    buildLogRow: buildLogRow
  };
}
