# 📦 Installation Guide

Complete step-by-step setup for the Algeria E-Commerce Platform.

## Prerequisites

- [ ] GitHub account
- [ ] Supabase account (free tier works)
- [ ] Cloudflare account (free tier + Images subscription)
- [ ] Meta Business account (for Facebook Pixel)
- [ ] Google Analytics 4 property

---

## Step 1: Supabase Setup

### 1.1 Create Project

1. Go to [supabase.com](https://supabase.com)
2. Create a new project
3. Choose a region close to Algeria (e.g., Frankfurt)
4. Note your project URL and keys

### 1.2 Run Database Migration

1. Go to **SQL Editor** in Supabase Dashboard
2. Copy the entire content of `database.sql`
3. Run the SQL script
4. Verify tables are created in **Table Editor**

### 1.3 Create Admin User

1. Go to **Authentication** → **Users**
2. Click **Add User** → **Create New User**
3. Enter admin email and password
4. Copy the User ID from the created user
5. Run this SQL to grant admin role:

```sql
INSERT INTO admin_roles (user_id, role) 
VALUES ('YOUR_USER_ID_HERE', 'admin');
```

### 1.4 Configure Edge Functions

1. Install Supabase CLI:
```bash
npm install -g supabase
```

2. Login and link project:
```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

3. Set secrets:
```bash
supabase secrets set TURNSTILE_SECRET_KEY=your_turnstile_secret
supabase secrets set META_PIXEL_ID=your_pixel_id
supabase secrets set META_ACCESS_TOKEN=your_access_token
supabase secrets set CLOUDFLARE_ACCOUNT_ID=your_cf_account
supabase secrets set CLOUDFLARE_IMAGES_API_TOKEN=your_cf_token
```

4. Deploy functions:
```bash
supabase functions deploy create-order
supabase functions deploy meta-server-events
supabase functions deploy cloudflare-images-upload
```

> ملاحظة: إذا واجهت 401 على `cloudflare-images-upload` رغم إرسال `authorization` و`apikey`، تأكد أنك نشرت الدالة بعد إضافة الملف:
> `supabase/functions/cloudflare-images-upload/config.toml` (فيه `verify_jwt = false`).

### 1.5 Enable Realtime (Optional)

1. Go to **Database** → **Replication**
2. Enable realtime for `orders` table if you want live updates

---

## Step 2: Cloudflare Setup

### 2.1 Cloudflare Images

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **Images**
3. Subscribe to Cloudflare Images ($5/month for 100k images)
4. Note your **Account ID** (in the URL or sidebar)
5. Create an **API Token**:
   - Go to **My Profile** → **API Tokens**
   - Create Token with **Cloudflare Images** permissions
   - Copy the token

### 2.2 Configure Image Variants

1. In **Images** → **Variants**
2. Create these variants:
   - `public` - Fit: scale-down, Width: 800
   - `thumbnail` - Fit: cover, Width: 200, Height: 200

### 2.3 Cloudflare Turnstile

1. Go to **Turnstile** in Cloudflare Dashboard
2. Add a new site
3. Choose **Managed** challenge type
4. Add your domain (or localhost for testing)
5. Copy **Site Key** (public) and **Secret Key** (private)

### 2.4 Cloudflare Pages

1. Go to **Pages** in Cloudflare Dashboard
2. Connect your GitHub repository
3. Configure build settings:
   - Build command: (leave empty - static files)
   - Build output directory: `/` or `.`
4. Deploy

---

## Step 3: Configure the Application (شرح مفصل)

### الفكرة باختصار: لماذا يوجد `config.js`؟

- **لا نضع أي مفاتيح داخل `index.html` أو `admin.html`**.
- بدل ذلك، المتجر يقرأ الإعدادات العامة (Public) من ملف واحد اسمه **`/config.js`**.
- هذا الملف يحتوي فقط على مفاتيح عامة مثل:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
  - `NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID`
- **أي مفاتيح سرية** مثل:
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `TURNSTILE_SECRET_KEY`
  - `META_ACCESS_TOKEN`
  - `CLOUDFLARE_IMAGES_API_TOKEN`

  يجب أن تبقى **داخل Supabase Edge Functions secrets** ولا تضعها أبداً في `config.js`.

---

## 3.1 تشغيل محلي (Local) – الطريقة الموصى بها

### A) أنشئ ملف `.env.local`

1) انسخ الملف `.env.example` إلى `.env.local` في جذر المشروع:

```bash
cp .env.example .env.local
```

2) افتح `.env.local` وضع القيم (مثال):

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
NEXT_PUBLIC_TURNSTILE_SITE_KEY=0x4AAAAA...
NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID=abcd1234
NEXT_PUBLIC_GA_MEASUREMENT_ID=G-XXXXXXX
NEXT_PUBLIC_META_PIXEL_ID=1234567890
```

> ملاحظة: هذه القيم **Public** مسموح تظهر في المتصفح.

### B) توليد ملف `config.js` تلقائياً

أضفنا سكربت جاهز يولّد `config.js` من `.env.local`:

```bash
node scripts/generate-config.mjs
```

بعدها سيتولد ملف:
- `config.js`

### C) شغّل الموقع محلياً

لأن الموقع static HTML، يكفي تشغيل سيرفر بسيط:

```bash
npx serve .
```

ثم افتح:
- Storefront: `http://localhost:3000/`
- Admin: `http://localhost:3000/admin.html`

> مهم: لا تفتح الملف مباشرة من File System (مثل `file:///...`) لأن بعض المتصفحات تمنع تحميل `/config.js` بشكل صحيح.

---

## 3.2 تشغيل على Cloudflare Pages (Production) – الطريقة الصحيحة

في Cloudflare Pages يوجد خيارين:

### الخيار 1 (الموصى به): Environment Variables + Build Command

1) اذهب إلى Cloudflare Pages → مشروعك → **Settings** → **Environment variables**
2) أضف المتغيرات (نفس أسماء `.env.example`) تحت Production:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
- `NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID`
- (اختياري) `NEXT_PUBLIC_GA_MEASUREMENT_ID`
- (اختياري) `NEXT_PUBLIC_META_PIXEL_ID`

3) في **Build settings**:
- Build command:

```bash
node scripts/generate-config.mjs
```

- Build output directory:
  - `.`

بهذا Cloudflare أثناء النشر سيولّد `config.js` تلقائياً داخل الـ output.

### الخيار 2 (سريع لكنه أقل تنظيماً): تعديل `config.js` مباشرة

- افتح `config.js` وضع القيم يدوياً.
- **غير مفضل** لأنه يسبب اختلاف بين local/prod وقد يؤدي لنسيان تحديث القيم.

---

## 3.3 تأكد أن `index.html` و `admin.html` يقرآن نفس `config.js`

- كلا الملفين يحتويان:

```html
<script src="/config.js"></script>
```

ولا تحتاج تعدّل شيء إضافي.

---

## 3.4 ملاحظة مهمة عن Turnstile

- `NEXT_PUBLIC_TURNSTILE_SITE_KEY` يذهب في `config.js` (Public)
- `TURNSTILE_SECRET_KEY` يوضع فقط في Supabase Secrets عبر:

```bash
supabase secrets set TURNSTILE_SECRET_KEY=...
```

---

## 3.5 (اختياري) التتبع GA4 / Meta Pixel

إذا تركتها فارغة في `config.js`، التتبع لن يعمل (بدون أخطاء).

> لا تحتاج تعديل سكربت داخل `index.html` لأن التحميل يتم ديناميكياً من القيم داخل `config.js`.

---

## Step 4: Meta (Facebook) Setup

### 4.1 Create Pixel

1. Go to [Meta Events Manager](https://business.facebook.com/events_manager)
2. Create a new Pixel
3. Copy the Pixel ID

### 4.2 Generate Access Token

1. Go to [Meta Business Settings](https://business.facebook.com/settings)
2. Navigate to **System Users**
3. Create a System User with **Admin** role
4. Generate a token with `ads_management` and `ads_read` permissions
5. Copy the access token

### 4.3 Test Events

1. Install [Meta Pixel Helper](https://chrome.google.com/webstore/detail/meta-pixel-helper/fdgfkebogiimcoedlicjlajpkdmockpc) Chrome extension
2. Visit your storefront
3. Verify events are firing correctly

---

## Step 5: Google Analytics 4

### 5.1 Create Property

1. Go to [Google Analytics](https://analytics.google.com)
2. Create a new GA4 property
3. Create a web data stream
4. Copy the Measurement ID (G-XXXXXXXXXX)

### 5.2 Configure Events

The following events are tracked automatically:
- `page_view`
- `view_item` (ViewContent)
- `add_to_cart` (AddToCart)
- `begin_checkout` (InitiateCheckout)
- `purchase` (Purchase)

---

## Step 6: Testing Checklist

### Local Testing

1. Open `index.html` in a browser (or use a local server)
2. Test product browsing
3. Test add to cart
4. Test checkout flow (use Turnstile test keys for local development)

### Turnstile Test Keys

For local development, use:
- Site Key: `1x00000000000000000000AA` (always passes)
- Secret Key: `1x0000000000000000000000000000000AA`

### Admin Testing

1. Open `admin.html`
2. Login with admin credentials
3. Test all CRUD operations
4. Verify audit logs are created

---

## Step 7: Go Live Checklist

- [ ] All CONFIG values updated with production keys
- [ ] Turnstile using production keys
- [ ] Database migration complete
- [ ] Admin user created
- [ ] Edge functions deployed
- [ ] Cloudflare Pages connected to GitHub
- [ ] Custom domain configured (optional)
- [ ] SSL/HTTPS enabled (automatic with Cloudflare)
- [ ] Test order placed successfully
- [ ] Tracking events verified in Meta & GA4
- [ ] Shipping rates configured for all 58 wilayas

---

## Troubleshooting

### "Unauthorized" error in admin

- Verify the user exists in Supabase Auth
- Check that admin_roles entry exists
- Verify JWT token is being sent

### Turnstile failing

- Check site key matches domain
- Verify secret key in Edge Function secrets
- Try test keys for local development

### Images not uploading

- Verify Cloudflare API token has Images permissions
- Check account ID is correct
- Verify admin authentication

### Orders not creating

- Check Edge Function logs in Supabase
- Verify Turnstile verification
- Check rate limiting thresholds

---

## Support

For issues, please check:
1. Supabase Dashboard → Logs
2. Cloudflare Dashboard → Pages → Functions logs
3. Browser Developer Console

Open a GitHub issue with:
- Error message
- Steps to reproduce
- Browser/environment info
