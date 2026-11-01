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
