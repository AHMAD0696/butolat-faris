# بطولات فارس — النشر (GitHub + Supabase + Netlify)

التطبيق مربوط بـ Supabase ويعمل سحابياً. الملفات:
- `index.html` — التطبيق (مربوط بالقاعدة عبر config.js).
- `config.js` — رابط ومفتاح Supabase (anon public — آمن للنشر).
- `supabase_schema.sql` — السكيمة الكاملة (لمشروع جديد).
- `supabase_patch.sql` — تحديث بسيط تشغّله على مشروعك الحالي (يضيف fa_signup و fa_update_profile).
- `netlify.toml` — إعداد Netlify.
- `config.example.js`, `.gitignore`.

## ١) خطوة ناقصة على القاعدة
Supabase ▸ SQL Editor ▸ New query ▸ الصق محتوى `supabase_patch.sql` ▸ Run.
(يضيف دالتَي التسجيل الذاتي وتحديث البيانات — بقية الدوال موجودة.)

## ٢) النشر على Netlify — طريقتان

### الطريقة الأسهل (سحب وإفلات، بدون GitHub)
1. ادخل https://app.netlify.com ▸ **Add new site** ▸ **Deploy manually**.
2. اسحب **كل ملفات هذه الحزمة** (المجلد كامل: index.html + config.js + netlify.toml …) إلى المربع.
3. ينشر فوراً ويعطيك رابطاً مثل `https://your-site.netlify.app`.

### الطريقة عبر GitHub (تحديث تلقائي عند كل رفع)
1. ارفع ملفات الحزمة إلى مستودع GitHub.
2. Netlify ▸ Add new site ▸ **Import from Git** ▸ اختر المستودع.
3. Build command: **اتركه فارغاً**. Publish directory: **`.`** (نقطة). ▸ Deploy.

> ملاحظة: `config.js` يُرفع لأن مفتاح anon عام وآمن (محمي بـ RLS).

## ٣) بعد النشر
افتح رابط Netlify وجرّب الدخول: **عبدالحميد الوابل / 1425**.

## كيف يعمل الربط
- **الدخول:** عبر `fa_login` — الأرقام السرية مجزّأة (bcrypt) في جدول محمي لا يُقرأ من المتصفح.
- **الحفظ:** بيانات البطولات في `fa_state` (بدون أي أرقام سرية). قراءة عامة، وكتابة فقط بتوكن صالح.
- **الحسابات:** تتزامن مع الخادم عبر fa_upsert_user / fa_update_profile / fa_delete_user / fa_signup.
- **بدون config:** يعمل محلياً (localStorage) دون كسر.
