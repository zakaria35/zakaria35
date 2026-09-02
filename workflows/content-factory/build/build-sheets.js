/*
 * يولّد قوالب CSV للتبويبات الثلاثة الجديدة في Master Control.
 * السبب: هذه الجلسة تملك قراءة Google Drive فقط — لا كتابة في Sheets.
 * الاستيراد: ملف > استيراد > رفع > «إدراج ورقة/أوراق جديدة» ثم أعد تسمية الورقة بالاسم المذكور.
 * تحذير: لا تختر «استبدال جدول البيانات» — سيمسح التبويبات القائمة.
 */

var fs = require('fs');
var path = require('path');
var steps = require('../lib/steps.js');

var OUT = path.join(__dirname, '..', 'sheets');
fs.mkdirSync(OUT, { recursive: true });

function csvCell(v) {
  var s = String(v === null || v === undefined ? '' : v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
}

function csv(headers, rows) {
  var lines = [headers.map(csvCell).join(',')];
  (rows || []).forEach(function (r) {
    lines.push(headers.map(function (h) { return csvCell(r[h]); }).join(','));
  });
  return '﻿' + lines.join('\r\n') + '\r\n'; // BOM ليقرأ Google Sheets العربية صحيحًا
}

function write(file, content) {
  fs.writeFileSync(path.join(OUT, file), content, 'utf8');
  console.log('  ' + file + '  (' + content.length + ' بايت)');
}

/* 1) حزم النشر — مع بذرة FOUNDATION-001 (§19، §20) */
var PACKAGE_HEADERS = ['ID', 'Version', 'Status', 'Caption', 'Alt Text', 'Pinned Comment', 'Story Before', 'Story After', 'Hashtags', 'Last Update'];
var seed = require('../tests/fixtures/package-foundation-001.json');
write('حزم-النشر.csv', csv(PACKAGE_HEADERS, [seed]));

/* 2) طابور النشر اليدوي — رؤوس فقط (§21) */
write('طابور-النشر-اليدوي.csv', csv(steps.QUEUE_HEADERS, []));

/* 3) سجل الأتمتة — رؤوس فقط (§25) */
write('سجل-الأتمتة.csv', csv(steps.LOG_HEADERS, []));

/* 4) تحديث تبويب n8n — Automation Control (§31): الأعمدة الجديدة إضافية فقط */
write('n8n-automation-control-تحديث.csv', csv(
  ['Workflow ID', 'الحالة', 'آخر تحديث', 'n8n Workflow ID', 'n8n Workflow URL', 'ملاحظات'],
  [
    { 'Workflow ID': 'SC-01', 'الحالة': 'IMPORT READY — AWAITING CREDENTIAL BINDING', 'آخر تحديث': '2026-09-02', 'n8n Workflow ID': '(يُملأ بعد الاستيراد)', 'n8n Workflow URL': '(يُملأ بعد الاستيراد)', 'ملاحظات': 'ملف جاهز: workflows/content-factory/n8n/SC-01-publishing-queue.json — DRY_RUN=true' },
    { 'Workflow ID': 'SC-02', 'الحالة': 'BLOCKED — META DEV LOOP', 'آخر تحديث': '2026-09-02', 'n8n Workflow ID': '—', 'n8n Workflow URL': '—', 'ملاحظات': 'لم يُبنَ ولم يُنشأ له اعتماد. لا نشر تلقائي إلى Meta.' },
    { 'Workflow ID': 'SC-03', 'الحالة': 'IMPORT READY — AWAITING CREDENTIAL BINDING', 'آخر تحديث': '2026-09-02', 'n8n Workflow ID': '(يُملأ بعد الاستيراد)', 'n8n Workflow URL': '(يُملأ بعد الاستيراد)', 'ملاحظات': 'ملف جاهز: SC-03-publish-guard.json — 25/25 اختبار ناجح' },
    { 'Workflow ID': 'SC-05', 'الحالة': 'IMPORT READY — AWAITING CREDENTIAL BINDING', 'آخر تحديث': '2026-09-02', 'n8n Workflow ID': '(يُملأ بعد الاستيراد)', 'n8n Workflow URL': '(يُملأ بعد الاستيراد)', 'ملاحظات': 'ملف جاهز: SC-05-alerts-recovery.json' },
    { 'Workflow ID': 'SC-06', 'الحالة': 'IMPORT READY — AWAITING CREDENTIAL BINDING', 'آخر تحديث': '2026-09-02', 'n8n Workflow ID': '(يُملأ بعد الاستيراد)', 'n8n Workflow URL': '(يُملأ بعد الاستيراد)', 'ملاحظات': 'ملف جاهز: SC-06-manual-publish-bridge.json' }
  ]
));

console.log('\nملاحظة: هذه قوالب. لم يُكتب أي شيء في Master Control — الجلسة تملك قراءة فقط.');
