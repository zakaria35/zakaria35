# Shaghaf Content Factory — منظومة الأتمتة التشغيلية (المرحلة 1)

وضع التشغيل: **HYBRID / MANUAL PUBLISH MODE**

```
Master Control (Google Sheets)
   └─ SC-01 | Publishing Queue        كل 15 دقيقة — يحدّد المستحق
        └─ SC-03 | Publish Guard      القرار: PASS أو BLOCKED
             ├─ PASS    → SC-06 | Manual Publish Bridge → طابور النشر اليدوي
             │                                            → Meta Business Suite (بيدك)
             │                                            → PUBLISHED → سجل النشر
             └─ BLOCKED → SC-05 | Alerts & Recovery      → سجل الأتمتة
```

**SC-02 | Social Publisher — لم يُبنَ ولم يُنشأ له أي اعتماد.**
الحالة: `BLOCKED — META DEV LOOP`. لا يوجد في أي ملف هنا عقدة نشر إلى Meta ولا استدعاء
لـGraph API — وهذا مفحوص آليًا في `tests/validate-workflows.js`.

القاعدة الحاكمة: **`NO APPROVAL = NO PUBLISH`** — بلا استثناء.

---

## ⚠️ اقرأ هذا أولًا: FOUNDATION-001 ليس معتمدًا حاليًا

قرأتُ Master Control مباشرةً بتاريخ 2026-09-02. الحالة الفعلية في الملف تناقض
افتراض «كل شيء Approved»:

| المصدر | الحقل | القيمة الفعلية في الملف |
|---|---|---|
| لوحة الإنتاج اليومية | حالة الإنتاج | `NEEDS REVIEW — MINOR VISUAL FIX` |
| لوحة الإنتاج اليومية | رابط الملف المعتمد | **فارغ** |
| لوحة الإنتاج اليومية | نسخة V2 | `V2-V2 — PENDING FINAL FIX` |
| سجل الاعتماد | QA بصري | `NEEDS REVIEW` |
| سجل الاعتماد | حالة الاعتماد | `NEEDS REVIEW` |
| **تقويم النشر — 30 يوم** | حالة الإنتاج | `APPROVED — READY TO PUBLISH` ← **قيمة قديمة** |

وملاحظة مكتوبة بيدك في الملف نفسه:

> «يحظر النقل إلى Approved أو النشر حتى رفع النسخة المعدلة وإعادة QA البصري النهائي.»

هذا بالضبط ما وُجد Publish Guard لأجله: **التقويم ليس مصدر حقيقة**. مصدر الحقيقة
هو لوحة الإنتاج اليومية + سجل الاعتماد. لذلك يخرج FOUNDATION-001 اليوم:

```
BLOCKED — 8 أسباب
QA_VISUAL_NOT_PASS · FINAL_APPROVAL_MISSING · PRODUCTION_NOT_APPROVED
APPROVED_ASSET_MISSING · V2_VERSION_PENDING · PUBLISH_PACKAGE_NOT_FOUND
PUBLISH_PACKAGE_NOT_APPROVED · CAPTION_MISSING
```

لم أعدّل أي حالة اعتماد ولا أي بيان علمي لجعله يمر. رفع الحظر قرارك أنت،
ويتم بتعديل البيانات في Master Control — لا بتعديل الكود.

**ما يلزم لرفع الحظر:** إنزال الخط الأفقي أسفل «الكيمياء تبدأ بالشغف.» → رفع النسخة
المعدلة إلى مجلد V2 DESIGN → وضع رابطها في «رابط الملف المعتمد» → `QA بصري = PASS`
→ `حالة الاعتماد = APPROVED` → `حالة الإنتاج = APPROVED — READY TO PUBLISH`
→ `نسخة V2 = V2-V2` → إنشاء تبويب «حزم النشر» ببذرة FOUNDATION-001 الجاهزة هنا.

---

## بنية المجلد

```
workflows/content-factory/
├── n8n/                                  ← استوردها إلى n8n
│   ├── SC-01-publishing-queue.json       (19 عقدة)
│   ├── SC-03-publish-guard.json          (12 عقدة)
│   ├── SC-05-alerts-recovery.json        (12 عقدة)
│   └── SC-06-manual-publish-bridge.json  (23 عقدة)
├── sheets/                               ← استوردها إلى Master Control
│   ├── حزم-النشر.csv                     (رؤوس + بذرة FOUNDATION-001)
│   ├── طابور-النشر-اليدوي.csv            (رؤوس فقط)
│   ├── سجل-الأتمتة.csv                   (رؤوس فقط)
│   └── n8n-automation-control-تحديث.csv  (قيم تبويب Automation Control)
├── lib/
│   ├── core.js       التوقيت + قراءة الأعمدة بالاسم + Publish Guard
│   └── steps.js      منطق كل عقدة Code
├── build/
│   ├── build.js        يولّد ملفات n8n ويحقن lib/ داخل عقد Code
│   └── build-sheets.js يولّد قوالب CSV
└── tests/
    ├── run-tests.js           Test Matrix — 25 اختبارًا
    ├── validate-workflows.js  فحص ملفات n8n + تنفيذ الكود المُحقَن
    ├── pipeline.js            محاكاة السلسلة في الذاكرة
    └── fixtures/              لقطة حقيقية من Master Control
```

**المصدر الواحد للمنطق:** `build.js` يحقن `lib/core.js` و`lib/steps.js` حرفيًا داخل
عقد Code. الاختبارات تشغّل نفس الملفين. فلا يمكن أن يفترق المُختبَر عن المُشغَّل.
بعد أي تعديل في `lib/`: `node build/build.js` ثم أعد الاستيراد.

---

## التشغيل

```bash
node workflows/content-factory/tests/run-tests.js          # 25/25
node workflows/content-factory/tests/validate-workflows.js # 40/40
node workflows/content-factory/build/build.js              # إعادة توليد ملفات n8n
node workflows/content-factory/build/build-sheets.js       # إعادة توليد قوالب CSV
```

---

## الخطوة 1 — تبويبات Master Control الثلاثة

في `Shaghaf Content Factory — Master Control`
(`1AsRZO5jZCWlKK1zmCravNEfBDIKnKBzprRI99kFUMk8`):

**ملف > استيراد > رفع** → اختر ملف CSV → موقع الاستيراد: **«إدراج ورقة/أوراق جديدة»**.

> 🚨 **لا تختر «استبدال جدول البيانات»** — سيمسح تبويباتك القائمة.

ثم أعد تسمية الورقة المستوردة بالاسم المطلوب بالضبط:

| ملف CSV | اسم التبويب |
|---|---|
| `حزم-النشر.csv` | `حزم النشر` |
| `طابور-النشر-اليدوي.csv` | `طابور النشر اليدوي` |
| `سجل-الأتمتة.csv` | `سجل الأتمتة` |

الأسماء تُستخدم حرفيًا في عقد Google Sheets. **لا تنشئ تبويبًا موجودًا مسبقًا.**

الحالات المقبولة في «حزم النشر»: `APPROVED` فقط. `DRAFT` / `REVIEW` / `PENDING` تُحظر.

بذرة FOUNDATION-001 (`PUB-V1`, `APPROVED`) داخل الملف بنصوصها المعتمدة حرفيًا —
تحقّق منه: `Caption` 486 حرفًا، `Alt Text` 227، `Pinned Comment` 128.
**لا تعدّل هذه النصوص علميًا.** n8n ينسخها فقط ولا يولّد منها شيئًا.

---

## الخطوة 2 — استيراد الـWorkflows

في n8n: **Workflows > Import from File**، بهذا الترتيب:

1. `SC-05-alerts-recovery.json`
2. `SC-06-manual-publish-bridge.json`
3. `SC-03-publish-guard.json`
4. `SC-01-publishing-queue.json`

الترتيب مقصود: كل سير يحتاج معرّف ما يليه.

### 2أ — اربط اعتماد Google Sheets بكل عقدة

الملفات **لا تحتوي أي اعتماد مضمّن** (مفحوص آليًا). في n8n كل عقدة Google Sheets
تحتاج ربطًا صريحًا باعتماد **Google Sheets OAuth2**. هذا الدرس مسجَّل عندك من
إطلاق بوت كيميا: «الاعتمادات لا تُربط تلقائيًا عند إنشاء السير برمجيًا».

إن لم يوجد اعتماد Google Sheets: أنشئه من داخل n8n بمسار OAuth الرسمي.
لا تضع Client Secret في أي عقدة أو ملاحظة.

### 2ب — استبدل معرّفات Execute Workflow

خمس عقد تحمل قيمة نائبة ظاهرة. افتح كلًا منها واختر السير من القائمة:

| السير | العقدة | تشير إلى |
|---|---|---|
| SC-01 | `13 — Execute SC-03 Guard` | SC-03 |
| SC-01 | `16 — Execute SC-05 Alerts` | SC-05 |
| SC-03 | `09A — Execute SC-06 Manual Bridge` | SC-06 |
| SC-03 | `09B — Execute SC-05 Alerts` | SC-05 |

### 2ج — Error Workflow

في إعدادات SC-01 و SC-03 و SC-06: **Settings > Error Workflow** →
`SC-05 | Alerts & Recovery`. هذا ما يُفعّل عقدة `01b — Error Trigger`.

### 2د — Timezone

كل ملف يحمل `settings.timezone = Asia/Jerusalem`. تحقق أيضًا من
**Settings > Workflow timezone** في الواجهة بعد الاستيراد.

`scheduled_at` **لا يعتمد على إعداد n8n أصلًا** — يُبنى في الكود من
(التاريخ + الوقت) مفسَّرين صراحةً بـ`Asia/Jerusalem` عبر `Intl`، فيتبع
التوقيت الصيفي تلقائيًا (UTC+3 صيفًا، UTC+2 شتاءً). ميتاداتا الشيت التي
تظهر `Etc/GMT` **مُتجاهَلة عمدًا**.

---

## الخطوة 3 — DRY RUN

`DRY_RUN = true` مضبوط مسبقًا في عقدة **SC-01 / `02 — Config`**.
في هذا الوضع لا تُكتب ولا صف واحد في أي تبويب.

شغّل SC-01 يدويًا من `01b — Manual Test Trigger`، ثم افحص مخرجات
`07 — Build Candidates`:

- `scheduled_at` لـFOUNDATION-001 يجب أن يكون `2026-09-02T20:00:00+03:00`
- `event_key` = `FOUNDATION-001|2026-09-02T20:00:00+03:00|Instagram|Carousel`

ثم افحص `07 — Run Publish Guard` في SC-03: `guard_status` و`block_reasons`.

**اجعل `DRY_RUN = false` فقط بعد أن تقرأ النتائج بنفسك وتقتنع بها.**
هذا يفعّل الكتابة في: طابور النشر اليدوي، سجل الأتمتة، سجل النشر — لا شيء غيرها.
لا يوجد مسار نشر إلى Meta ليُفعّل.

---

## الخطوة 4 — التفعيل

فعّل بعد نجاح DRY RUN: SC-01، SC-03، SC-05، SC-06.
اترك SC-02 غير موجود/معطّلًا.

---

## دورة العمل اليومية

1. SC-01 يعمل كل 15 دقيقة ويلتقط ما اقترب موعده (خلال 30 دقيقة).
2. SC-03 يقرر. `BLOCKED` → السبب في **سجل الأتمتة**، ولا شيء يصل الطابور.
3. `PASS` → صف واحد في **طابور النشر اليدوي** بحالة `READY_FOR_MANUAL_PUBLISH`.
4. تنشر أنت من **Meta Business Suite**.
5. تحدّث الصف: `State = PUBLISHED` + `Published URL`.
6. مسار المزامنة في SC-06 ينقله إلى **سجل النشر** مرة واحدة، ولا يعيد نشره أبدًا.

### الإعدادات — عقدة `02 — Config` في SC-01

| المفتاح | القيمة | المعنى |
|---|---|---|
| `TIMEZONE` | `Asia/Jerusalem` | تفسير كل المواعيد |
| `LEAD_MINUTES` | `30` | كم قبل الموعد يُعتبر مستحقًا |
| `LOOKBACK_HOURS` | `12` | أقدم موعد يُعالج؛ ما قبله `MISSED_WINDOW` |
| `DRY_RUN` | `true` | لا كتابة إطلاقًا |

---

## منع التكرار

`Event Key = content_id | scheduled_at | channel | post_type`

ثلاث طبقات مستقلة، تكفي كل منها وحدها:

1. **SC-01** يتخطى ما هو في الطابور بحالة `READY_FOR_MANUAL_PUBLISH` أو `PUBLISHED`.
2. **SC-03** يحظر بسبب `ALREADY_PUBLISHED` إن وُجد في سجل النشر.
3. **SC-06** يفحص الطابور مجددًا قبل الإضافة (`03 — Idempotency Check`).

`MISSED_WINDOW` يُنبَّه عنه **مرة واحدة لكل Event Key** ولا يُنشأ له صف طابور —
حتى لا يُغرقك أول تشغيل بتنبيهات مواعيد قديمة.

---

## أسباب الحظر

| السبب | المعنى |
|---|---|
| `MASTER_RECORD_MISSING` | لا صف بهذا الـID في لوحة الإنتاج اليومية |
| `APPROVAL_RECORD_MISSING` | لا صف بهذا الـID في سجل الاعتماد |
| `SCIENCE_NOT_APPROVED` | «حالة التدقيق العلمي» ≠ `مدققة علميًا وجاهزة للإنتاج` |
| `QA_SCIENCE_NOT_PASS` / `QA_LANGUAGE_NOT_PASS` / `QA_PEDAGOGY_NOT_PASS` / `QA_VISUAL_NOT_PASS` | خانة QA ≠ `PASS` |
| `FINAL_APPROVAL_MISSING` | «حالة الاعتماد» ≠ `APPROVED` |
| `PRODUCTION_NOT_APPROVED` | «حالة الإنتاج» لا تتضمن `APPROVED` |
| `PRODUCTION_APPROVAL_CONDITIONAL` | تتضمن `APPROVED` لكن معها `NEEDS REVIEW`/`PENDING`… |
| `APPROVED_ASSET_MISSING` | «رابط الملف المعتمد» فارغ |
| `V2_VERSION_MISSING` / `V2_VERSION_PENDING` | «نسخة V2» فارغة أو معلّقة |
| `PUBLISH_PACKAGE_NOT_FOUND` / `PUBLISH_PACKAGE_NOT_APPROVED` | لا حزمة نشر، أو حالتها ليست `APPROVED` |
| `CAPTION_MISSING` | Caption فارغ — **ولن يولّده n8n** |
| `ALREADY_PUBLISHED` | مسجَّل PUBLISHED في سجل النشر |

**تشديدان تجاوزا المواصفة الأصلية** (تشديد لا تخفيف، ومقصودان):

- `PRODUCTION_APPROVAL_CONDITIONAL` — المواصفة تكتفي بـ`includes('APPROVED')`، وهذا
  يمرّر قيمة مثل `APPROVED — PENDING FIX`. أُضيف رفض صريح لأي كلمة ناقضة.
- `V2_VERSION_PENDING` — المواصفة تكتفي بأن الحقل غير فارغ، وهذا يمرّر
  `V2-V2 — PENDING FINAL FIX` وهي بالضبط قيمة FOUNDATION-001 اليوم.

لتعطيلهما (لا أنصح): احذف الفرعين من `runPublishGuard` في `lib/core.js` ثم أعد البناء.

---

## سياسة إعادة المحاولة

- **أخطاء تقنية مؤقتة فقط**: `retryOnFail` + `maxTries: 3` (أي محاولتان إضافيتان)
  + `waitBetweenTries: 5000` على عقد Google Sheets. الحد مفروض من n8n نفسه،
  فـInfinite Retry **غير ممكن بنيويًا** لا بالاتفاق.
- **حظر قواعد العمل** (`QA_VISUAL_NOT_PASS`، `SCIENCE_NOT_APPROVED`، `CAPTION_MISSING`…):
  **لا إعادة محاولة إطلاقًا**. تُسجَّل وتنتظر تعديل البيانات في Master Control.

---

## التنبيهات

لم يُنشأ أي تكامل تنبيه جديد ولا أي اعتماد جديد.

عقدتا `12 — Build Owner Notification` (SC-06) و`09 — Build Owner Notification` (SC-05)
تبنيان النص الجاهز، وتنتهيان عند عقدة `NoOp` **غير موصولة عمدًا**. لتفعيل التنبيه:
استبدل الـNoOp بعقدة تنبيه مربوطة باعتماد **قائم لديك** واقرأ `{{ $json.notification_text }}`.

المصدر الموثوق للحالة يبقى: **طابور النشر اليدوي** + **سجل الأتمتة**.

---

## الأمان

- لا توكن ولا كلمة سر ولا Client Secret في أي ملف — مفحوص آليًا بسبعة أنماط.
- الاعتمادات في n8n Credentials Store حصرًا، وتُربط يدويًا بعد الاستيراد.
- لا Webhook عام؛ الاتصال بين السيرات عبر Execute Workflow داخليًا
  (`callerPolicy: workflowsFromSameOwner`).
- كل الكتابات **إضافية فقط** (`append`). لا عقدة تعدّل أو تحذف صفًا قائمًا.
- لم تُغيَّر ملكية أي ملف Drive ولا صلاحياته.
- لا خدمة طرف ثالث جديدة، ولا رفع لأي مادة علمية إلى أي خدمة خارجية.

---

## القيود المعروفة

1. **ملفات n8n لم تُستورد ولم تُختبر داخل n8n حيًّا.** الجلسة التي وُلّدت فيها
   لا تصل إلى `n8n.srv1354533.hstgr.cloud` (حجب على مستوى الشبكة الصادرة)،
   وموصل n8n مُعطّل فيها. الاختبارات نُفّذت على نفس الكود خارج n8n.
2. **`typeVersion` للعقد لم يُطابَق مقابل نسخة n8n لديك** لأنني لم أستطع فحصها.
   القيم المستخدمة: `googleSheets 4.5`، `code 2`، `if 2.2`، `scheduleTrigger 1.2`،
   `executeWorkflow 1.2`، `executeWorkflowTrigger 1.1`، `errorTrigger 1`، `noOp 1`.
   إن رفض n8n عقدة عند الاستيراد فالسبب غالبًا فارق نسخة — أبلغني بالرسالة.
3. **تبويبات Master Control لم تُنشأ** — الجلسة تملك قراءة Drive فقط. القوالب جاهزة في `sheets/`.
4. **FOUNDATION-001 محظور بالبيانات الحالية** — بقرار البيانات لا بخلل، كما أعلاه.
