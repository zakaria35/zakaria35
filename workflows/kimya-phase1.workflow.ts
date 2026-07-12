/**
 * كيميا — المرحلة 1: معلّم الكيمياء على تيليجرام
 *
 * سير عمل n8n (بلغة الـSDK) لبوت تيليجرام يعلّم الكيمياء لطلبة التوجيهي الفلسطيني
 * بشخصية «كيميا»، مع ذاكرة محادثة منفصلة لكل طالب (مفتاحها معرّف المحادثة).
 *
 * معرّف الـWorkflow في n8n: nSx6rKHG4e4cUO0Z
 * المحرّك: Google Gemini (models/gemini-2.5-flash) — قابل للتبديل بـ Claude لاحقاً.
 *
 * هذا الملف نسخة موثّقة للمراجعة والنسخ الاحتياطي. المصدر الحيّ في n8n.
 */
import { workflow, node, trigger, languageModel, memory, newCredential, nodeJson, sticky, expr } from '@n8n/workflow-sdk';

const kimyaSystem = "أنتَ «كيميا» 🧪 — صديقٌ ومعلّمٌ شخصيّ متخصّص في الكيمياء لطلبة الثانوية العامة (التوجيهي) في المنهاج الفلسطيني، الفرع العلمي، استعداداً للامتحانات الوزارية.\n\nنبرتك: بالعربية دائماً، بلغةٍ واضحة دافئة قريبة من الطالب الفلسطيني — فصحى مبسّطة مع لمسة ودّ. مشجّع دائماً؛ التوجيهي مرهق فذكّر الطالب أن الصعوبة طبيعية وأنه قادر، ولا تُشعره بالغباء أبداً. مختصر وواضح: أجب على قدر السؤال.\n\nكيف تُعلّم: افهم السؤال أولاً وإن كان غامضاً اسأل سؤالاً توضيحياً واحداً. ابدأ بالفكرة الكبيرة ثم التفصيل: اللماذا قبل الكيف قبل الحفظ. قسّم الصعب إلى خطوات. اربط المجرّد بأمثلة من الحياة اليومية (الصابون، صدأ الحديد، البطاريات، تحلية الماء). في المسائل الحسابية اكتب: المعطيات، القانون، التعويض، الناتج بوحداته. بعد الشرح اطرح سؤالاً بسيطاً ليتأكد أنه فهم.\n\nنطاق المنهاج: بنية الذرّة والجدول الدوري، الروابط، الحسابات الكيميائية والمول، المحاليل والتراكيز، الكيمياء الحرارية، سرعة التفاعل، الاتزان الكيميائي، الأحماض والقواعد وpH، الأكسدة والاختزال والخلايا الكهروكيميائية، ومقدّمة الكيمياء العضوية. إن سأل عن موضوع خارج المنهاج نبّهه بلطف أنه إثراء خارج المقرّر.\n\nالمصداقية العلمية قاعدة غير قابلة للكسر: لا تُخمّن الأرقام والمعادلات. وازِن معادلاتك وتحقّق منها قبل عرضها. إن لم تكن متأكداً 100% قل بوضوح دعني أتأكد أو لا أعرف — الصدق أهم من إجابةٍ سريعة خاطئة قد تُفشل الطالب في الامتحان.\n\nالذاكرة: أنتَ صديقٌ مواكب. تذكّر اسم الطالب والموضوعات التي يجدها صعبة وتقدّمه، وابنِ على ما شرحته سابقاً بدل التكرار، واحتفِ بتقدّمه.\n\nالأخلاق والسلامة: لا تحلّ الواجب أو الامتحان نيابةً عنه دون أن يتعلّم — ساعده ليفهم ويحلّ بنفسه. لا تُشجّع الغش. عند الحديث عن التجارب نبّه لمخاطرها ولا تُرشد لأي تحضيرٍ خطِر.\n\nالتنسيق: اكتب بنصٍّ بسيط وواضح ومنظّم بنقاط عند الحاجة، وتجنّب رموز التنسيق الثقيلة.";

const kimyaTrigger = trigger({
  type: 'n8n-nodes-base.telegramTrigger',
  version: 1.3,
  config: {
    name: 'استقبال رسالة الطالب',
    parameters: { updates: ['message'] },
    credentials: { telegramApi: newCredential('Telegram account', 'VfVA0cmPJfwJgCmW') },
    position: [240, 320]
  },
  output: [{ message: { text: 'ما الفرق بين الحمض والقاعدة؟', chat: { id: 123456789 } } }]
});

const geminiModel = languageModel({
  type: '@n8n/n8n-nodes-langchain.lmChatGoogleGemini',
  version: 1.1,
  config: {
    name: 'محرّك كيميا (Gemini)',
    parameters: { modelName: 'models/gemini-2.5-flash' },
    credentials: { googlePalmApi: newCredential('Google Gemini(PaLM) Api account', 'f7m8ADfAo4EFnwIX') },
    position: [360, 540]
  }
});

const kimyaMemory = memory({
  type: '@n8n/n8n-nodes-langchain.memoryBufferWindow',
  version: 1.4,
  config: {
    name: 'ذاكرة المحادثة',
    parameters: {
      sessionIdType: 'customKey',
      sessionKey: nodeJson(kimyaTrigger, 'message.chat.id'),
      contextWindowLength: 12
    },
    position: [560, 540]
  }
});

const kimyaAgent = node({
  type: '@n8n/n8n-nodes-langchain.agent',
  version: 3.1,
  config: {
    name: 'عقل كيميا',
    parameters: {
      promptType: 'define',
      text: expr('{{ $json.message.text }}'),
      options: { systemMessage: kimyaSystem }
    },
    subnodes: { model: geminiModel, memory: kimyaMemory },
    position: [560, 320]
  },
  output: [{ output: 'الحمض يمنح أيون هيدروجين، والقاعدة تستقبله. هل تحب مثالاً من الحياة؟' }]
});

const kimyaReply = node({
  type: 'n8n-nodes-base.telegram',
  version: 1.2,
  config: {
    name: 'إرسال ردّ كيميا',
    parameters: {
      resource: 'message',
      operation: 'sendMessage',
      chatId: nodeJson(kimyaTrigger, 'message.chat.id'),
      text: expr('{{ $json.output }}'),
      additionalFields: { appendAttribution: false }
    },
    credentials: { telegramApi: newCredential('Telegram account', 'VfVA0cmPJfwJgCmW') },
    position: [860, 320]
  },
  output: [{ ok: true }]
});

const setupNote = sticky(
  "## كيميا 🧪 — المرحلة الأولى\nبوت تيليجرام يعلّم الكيمياء لطالب التوجيهي الفلسطيني ويتذكّر سياق المحادثة.\n\nقبل التشغيل: تأكّد أن حساب تيليجرام ومفتاح Gemini مربوطان، ثم فعّل الـWorkflow.\n\nالذاكرة مفتاحها معرّف المحادثة، فكل طالب له سياقه الخاص.",
  [kimyaTrigger, kimyaAgent, kimyaReply],
  { color: 4 }
);

export default workflow('kimya-phase1', 'كيميا — معلّم الكيمياء (المرحلة 1)')
  .add(kimyaTrigger)
  .to(kimyaAgent)
  .to(kimyaReply)
  .add(setupNote);
