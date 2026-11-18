# حصيلة فحص n8n — 2026-09-28

فحص فعلي عبر موصل n8n أثناء فترة اتصاله. الموصل انقطع بعد الفحص ويطلب
تفويضًا من جديد، فهذه الحقائق مثبّتة هنا حتى لا يُعاد استخراجها.

> كل ما في هذا الملف **معرّفات وأسماء، لا أسرار**. أداة `list_credentials`
> لا تُرجع بيانات سرية إطلاقًا، والمعرّف وحده بلا قيمة دون وصول إلى n8n.

---

## 1. الموصل كامل الصلاحيات

الصلاحيات المتاحة على كل Workflow:

```
workflow:create · update · publish · unpublish · execute
workflow:export · import · delete · share · move · read · list
execution:reveal
```

أي أن الإنشاء والتعديل والتفعيل والتشغيل كلها ممكنة برمجيًا.

## 2. قيد جوهري: الإنشاء من كود SDK لا من JSON

الموصل **لا يستورد JSON**. مساره الإلزامي:

```
get_sdk_reference → get_suggested_nodes → search_nodes → get_node_types
→ كتابة كود @n8n/workflow-sdk → validate_node_config → validate_workflow
→ create_workflow_from_code
```

**تمييز مهم:** هذا قيد على الإنشاء البرمجي فقط. ملفات `n8n/*.json` في هذا
المجلد **ما زالت صالحة تمامًا** للاستيراد اليدوي من واجهة n8n
(`Workflows > Import from File`). دليل الاستيراد في `README.md` لم يتأثر.

عند إعادة البناء عبر الـSDK: منطق `lib/core.js` و`lib/steps.js` ينتقل
حرفيًا داخل عقد Code (مُختبَر 25/25). المُعاد كتابته هو توصيل الرسم فقط.

## 3. الاعتمادات الموجودة — لا حاجة لإنشاء أي شيء

| الاسم | النوع | المعرّف |
|---|---|---|
| **Google Sheets account** | `googleSheetsOAuth2Api` | `iBpuwxBvaElSkrED` |
| Google Sheets Trigger account | `googleSheetsTriggerOAuth2Api` | `fmsWgxBjyA2mjboi` |
| Google Drive account | `googleDriveOAuth2Api` | `IZKJj0WrHxDUAIcV` |
| Google Service Account account | `googleApi` | `lraxDYRruYbI7oVS` |
| Google Gemini(PaLM) Api account | `googlePalmApi` | `f7m8ADfAo4EFnwIX` |
| Telegram account | `telegramApi` | `VfVA0cmPJfwJgCmW` |
| Telegram account 2 / 3 | `telegramApi` | `FgKgy8sx7FqPP3rr` / `OI9WNwcZr6Okvoul` |
| Google Docs account / 2 | `googleDocsOAuth2Api` | `14aBU2TJ1QA3pzqi` / `ECKyHo1Has35RQm0` |
| Bearer / Header / Query Auth | `httpBearerAuth` / `httpHeaderAuth` / `httpQueryAuth` | — |

**`Google Sheets account` هو المطلوب** لكل عقد Google Sheets في SC-01/03/05/06.

**لا يوجد أي اعتماد Meta / Facebook / Instagram** — متسق مع §2.
لا تنشئ واحدًا دون إذن صريح جديد.

## 4. المشروع

مشروع شخصي واحد: `JXlkBmtm85xSqqTu`
(`Zakaria zakaria.alabsi@gmail.com`). كل Workflow جديد يهبط فيه.

## 5. لا تكرار

**لا يوجد SC-01 / SC-03 / SC-05 / SC-06** في الحساب (30 سير عمل، فُحصت كلها).

`Shaghaf | Content Design Queue` (`ogREZ4oTcekgc5LU`، معطّل منذ 2026-05-30،
بلا Trigger) تعذّرت قراءته: «Workflow is not available in MCP».
**المالك أكّد أنه مهجور — يُتجاهل.**

## 6. نسخة n8n

الموصل لا يكشفها نصًّا. **مستنتجة** من نسخ العقد في مرجع الـSDK:

```
scheduleTrigger 1.3 · if 2.2 · set 3.4 · merge 3.2
switch 3.2 · splitInBatches 3 · agent 3.1 · httpRequest 4.3–4.4
```

نسخة حديثة. لاحظ أن `scheduleTrigger` هنا **1.3** بينما ملفات JSON تستخدم
1.2 — فارق غير ضار عند الاستيراد اليدوي، لكن استخدم 1.3 في كود الـSDK.

---

## الخطوات المتفق عليها مع المالك

1. **SC-00 | Setup** — سير لمرة واحدة ينشئ التبويبات الثلاثة في Master Control
   عبر اعتماد `Google Sheets account`، لأن جلسة Claude تملك قراءة Drive فقط.
   إضافة فقط: لا يمس أي تبويب قائم. يراجعه المالك قبل تشغيله ويحذفه بعده.
   التبويبات: `حزم النشر` · `طابور النشر اليدوي` · `سجل الأتمتة`
   (الرؤوس والبذرة في `sheets/*.csv`).
2. تجاهل `Shaghaf | Content Design Queue`.
3. ثم بناء SC-01 / SC-03 / SC-05 / SC-06 عبر الـSDK بـ`DRY_RUN = true`.

## عقبتان قائمتان لا يرفعهما الكود

- **موعد FOUNDATION-001 فات.** التقويم يحمل `2026-09-02 20:00`، وقد مضى.
  مع `LOOKBACK_HOURS = 12` يصنّفه SC-01 `MISSED_WINDOW` لا `DUE`.
  يلزم **موعد جديد في تقويم النشر** وإلا لن يصبح مستحقًا أبدًا.
- **FOUNDATION-001 ما زال محظورًا.** Master Control لم يتغيّر منذ
  2026-09-02 (تحقق بـ`modifiedTime`): `QA بصري = NEEDS REVIEW`،
  `حالة الاعتماد = NEEDS REVIEW`، `رابط الملف المعتمد` فارغ،
  `نسخة V2 = V2-V2 — PENDING FINAL FIX`.
  رفع الحظر بتعديل البيانات لا بتعديل الكود.

---

## قيود محلّل الـSDK — مكتشفة بالتجربة لا بالافتراض

ثلاث محاولات تحقق فاشلة كشفت ما لا تذكره الوثائق:

1. **لا يقبل تعليقات أنواع TypeScript** رغم أن وصف الأداة يقول
   «TypeScript/JavaScript». `function f(x: string)` يفشل بخطأ نحوي.
2. **لا يقبل تعريف الدوال إطلاقًا** — `FunctionDeclaration ... is not
   allowed in SDK code`. كل عقدة تُكتب صراحةً، ولا دوال مساعدة.
   لذلك ملفات الـSDK مُسهَبة عمدًا.
3. **`newCredential('Name', 'id')` لا يربط الاعتماد.** الصيغة ذات
   الوسيطين تُقبل في التحقق ثم **تُسقَط بصمت** عند الإنشاء — نتج سير
   بلا أي اعتماد على عقد Google Sheets الستة.
   الربط الصحيح: `update_workflow` بعملية `setNodeCredential`
   (`credentialKey` + `credentialId` + `credentialName`) بعد الإنشاء.
   المؤشر على الفشل: `autoAssignedCredentials: []` في نتيجة الإنشاء.

**`columns.schema` اختياري** مع `autoMapInputData` — العقدة تقرأ رؤوس
الشيت وقت التشغيل. `schema: []` يكفي ويقصّر الكود كثيرًا.

## نسخ العقد الفعلية (مقابل ما في ملفات JSON)

| العقدة | الفعلي | في JSON |
|---|---|---|
| googleSheets | **4.7** | 4.5 |
| if | **2.3** | 2.2 |
| scheduleTrigger | **1.3** | 1.2 |
| executeWorkflow | **1.3** | 1.2 |
| executeWorkflowTrigger | **1.2** | 1.1 |
| switch | **3.4** | — |
| code · noOp · errorTrigger · manualTrigger | 2 · 1 · 1 · 1 | مطابق |

## ما أُنشئ فعلًا

| السير | المعرّف | الحالة |
|---|---|---|
| SC-00 \| Setup — Master Control Tabs | `xF648xJtJ8YlPuPb` | 11 عقدة، غير مُفعّل، يشير إلى جدول اختبار |

جدول الاختبار المؤقت: `1Hz1MJv5nkQsB40OSVH3HP8B-R0d784xgABtc_F8TZEk`
(«ZZ TEMP — SC-00 Tab Creation Test») — يُحذف بعد التحقق.
السبب: التحقق من هبوط الرؤوس صحيحةً قبل لمس Master Control.

---

## SC-00 — نُفِّذ وتُحقِّق منه (2026-11-18)

**المنهج:** شُغّل أولًا على جدول اختبار مؤقت، لا على Master Control.
السبب: `autoMapInputData` على تبويب فارغ سلوك غير موثّق، وإنشاء تبويب
خاطئ في الملف الرئيسي أصعب في التراجع من إنشائه. بعد نجاح الاختبار
حُوّل `documentId` إلى Master Control عبر `setNodeParameter`.

**نتيجة الاختبار (التشغيل 2025، ناجح):**
- الرؤوس هبطت في الصف 1 بالترتيب الصحيح.
- **الـCaption هبط كنص متعدد الأسطر حقيقي** — الأسطر محفوظة، لا `\n`
  حرفية. كان هذا الخطر الأكبر وقد زال.
- التبويبان الفارغان حصلا على رؤوس **بلا صف بيانات** (`A1:P1` و`A1:H1`):
  الصف الفارغ لم يُنشئ صفًا، وهو أفضل من المتوقع.

**نتيجة Master Control (التشغيل 2026، ناجح):**

| التبويب | النطاق | المحتوى |
|---|---|---|
| حزم النشر | `A1:J2` | 10 رؤوس + بذرة FOUNDATION-001 (`PUB-V1`, `APPROVED`) |
| طابور النشر اليدوي | `A1:P1` | 16 رأسًا، بلا صفوف |
| سجل الأتمتة | `A1:H1` | 8 رؤوس، بلا صفوف |

**تحقق السلامة — التبويبات السبعة الأصلية بأكملها سليمة بلا تغيير:**

| التبويب | النطاق |
|---|---|
| لوحة الإنتاج اليومية | `A1:V7` |
| طابور التصميم | `A1:P7` |
| سجل الاعتماد | `A1:I7` |
| سجل النشر | `A1:G1` |
| القواميس والحالات | `A1:D14` |
| تقويم النشر — 30 يوم | `A1:S31` |
| n8n — Automation Control | `A1:N7` |

جدول الاختبار المؤقت `1Hz1MJv5...` نُقل إلى سلة المحذوفات بعد التحقق.

**لم يتغيّر أي بيان علمي ولا أي حالة اعتماد.** FOUNDATION-001 ما زال
`QA بصري = NEEDS REVIEW` و`حالة الاعتماد = NEEDS REVIEW` و«رابط الملف
المعتمد» فارغًا — كما كان.

### الخطوة التالية

بناء SC-01 / SC-03 / SC-05 / SC-06 بالـSDK بـ`DRY_RUN = true`، مع الانتباه
إلى أن ربط الاعتماد يحتاج `setNodeCredential` بعد الإنشاء (القيد 3 أعلاه).
