/*
 * محاكاة السلسلة SC-01 -> SC-03 -> SC-06 / SC-05 في الذاكرة.
 * الغرض: تنفيذ Test Matrix على نفس دوال lib/ التي تُشغَّل داخل n8n،
 * مع استبدال Google Sheets بكائن في الذاكرة بدل الكتابة في الملف الحقيقي.
 */

var core = require('../lib/core.js');
var steps = require('../lib/steps.js');

var DEFAULT_CONFIG = {
  TIMEZONE: 'Asia/Jerusalem',
  LEAD_MINUTES: 30,
  LOOKBACK_HOURS: 12,
  DRY_RUN: false
};

function tabs(sheets) {
  return {
    calendar: sheets['تقويم النشر — 30 يوم'] || [],
    master: sheets['لوحة الإنتاج اليومية'] || [],
    approval: sheets['سجل الاعتماد'] || [],
    packages: sheets['حزم النشر'] || [],
    publishLog: sheets['سجل النشر'] || [],
    queue: sheets['طابور النشر اليدوي'] || [],
    autoLog: sheets['سجل الأتمتة'] || []
  };
}

function runGuard(contentId, sheets, tz, nowIso) {
  var t = tabs(sheets);
  var row = t.calendar.filter(function (r) {
    return core.text(core.field(r, ['ID'])) === core.text(contentId);
  })[0];

  var candidate = row
    ? core.normalizeCalendarRow(row, tz)
    : { content_id: contentId, topic: '', platform: '', post_type: '', format: '', cta: '', scheduled_at: nowIso, calendar_status: '', event_key: core.buildEventKey(contentId, nowIso, '', '') };

  var normalized = steps.sc03Normalize({
    candidate: candidate,
    masterRows: t.master,
    approvalRows: t.approval,
    packageRows: t.packages,
    publishLogRows: t.publishLog
  });

  return steps.sc03RunGuard(normalized);
}

/** دورة SC-01 كاملة: مرشحون -> حارس -> جسر/تنبيه -> سجل. */
function runCycle(sheets, tz, nowIso, overrides) {
  var cfg = Object.assign({}, DEFAULT_CONFIG, { TIMEZONE: tz }, overrides || {});
  var t = tabs(sheets);
  var nowMs = new Date(nowIso).getTime();
  var runId = 'TEST-RUN-' + nowMs;

  sheets['طابور النشر اليدوي'] = t.queue;
  sheets['سجل الأتمتة'] = t.autoLog;
  sheets['سجل النشر'] = t.publishLog;

  function log(entry) {
    if (cfg.DRY_RUN) return;
    t.autoLog.push(steps.buildLogRow(Object.assign({ timestamp: nowIso, run_id: runId }, entry)));
  }

  var candidates = steps.sc01BuildCandidates({
    calendarRows: t.calendar,
    queueRows: t.queue,
    publishLogRows: t.publishLog,
    autoLogRows: t.autoLog,
    config: cfg,
    nowMs: nowMs
  });

  var decisions = [];

  candidates.forEach(function (c) {
    if (c.route === 'SKIP' || c.route === 'INVALID_SCHEDULE') {
      decisions.push({ content_id: c.content_id, event_key: c.event_key, state: c.state, reasons: [] });
      log({ workflow: 'SC-01', event_key: c.event_key, content_id: c.content_id, state: c.state, reason: c.reason });
      return;
    }

    if (c.route === 'MISSED_WINDOW') {
      var d5 = steps.sc05Decide({ state: 'MISSED_WINDOW', event_key: c.event_key }, t.autoLog);
      decisions.push({ content_id: c.content_id, event_key: c.event_key, state: 'MISSED_WINDOW', reasons: [], alerted: d5.should_notify });
      if (d5.should_log) {
        log({ workflow: 'SC-05', event_key: c.event_key, content_id: c.content_id, state: 'MISSED_WINDOW', reason: c.reason });
      }
      return;
    }

    // route === 'DUE'
    log({ workflow: 'SC-01', event_key: c.event_key, content_id: c.content_id, state: 'CANDIDATE', reason: '' });

    var verdict = steps.sc03RunGuard(steps.sc03Normalize({
      candidate: c,
      masterRows: t.master,
      approvalRows: t.approval,
      packageRows: t.packages,
      publishLogRows: t.publishLog
    }));

    if (verdict.guard_status === 'BLOCKED') {
      decisions.push({ content_id: c.content_id, event_key: c.event_key, state: 'BLOCKED', reasons: verdict.block_reasons });
      var d5b = steps.sc05Decide({ state: 'BLOCKED', event_key: c.event_key }, t.autoLog);
      if (d5b.should_log) {
        log({ workflow: 'SC-05', event_key: c.event_key, content_id: c.content_id, state: 'BLOCKED', reason: verdict.block_reasons });
      }
      return;
    }

    // PASS -> SC-06
    decisions.push({ content_id: c.content_id, event_key: c.event_key, state: 'PASS', reasons: [] });
    log({ workflow: 'SC-03', event_key: c.event_key, content_id: c.content_id, state: 'PASS', reason: '' });

    var exists = t.queue.some(function (r) {
      return core.text(core.field(r, ['Event Key'])) === c.event_key;
    });
    if (exists) {
      log({ workflow: 'SC-06', event_key: c.event_key, content_id: c.content_id, state: 'SKIPPED_ALREADY_QUEUED', reason: '' });
      return;
    }

    if (!cfg.DRY_RUN) t.queue.push(steps.sc06BuildQueueRow(verdict, nowIso));
    log({ workflow: 'SC-06', event_key: c.event_key, content_id: c.content_id, state: 'READY_FOR_MANUAL_PUBLISH', reason: '' });
  });

  return { decisions: decisions, config: cfg };
}

/** §26 — مزامنة PUBLISHED من الطابور إلى سجل النشر مرة واحدة. */
function syncPublished(sheets) {
  var t = tabs(sheets);
  sheets['سجل النشر'] = t.publishLog;
  var pending = steps.sc06FindUnsyncedPublished(t.queue, t.publishLog);
  pending.forEach(function (row) { t.publishLog.push(row); });
  return pending.length;
}

module.exports = { runGuard: runGuard, runCycle: runCycle, syncPublished: syncPublished, DEFAULT_CONFIG: DEFAULT_CONFIG };
