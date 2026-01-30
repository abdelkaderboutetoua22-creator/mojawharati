# 🛒 Algeria E-Commerce Platform

A production-ready, security-first e-commerce platform built specifically for Algeria with:
- **Arabic RTL** interface (storefront + admin)
- **DZD currency** with COD (Cash on Delivery) only
- **Guest checkout** (no customer accounts)
- **58 Wilayas** support with variable shipping rates

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Cloudflare Pages                         │
│                    (Static Hosting + Edge)                       │
├─────────────────────────────────────────────────────────────────┤
│  index.html (Storefront)    │    admin.html (Dashboard)         │
└──────────────┬──────────────┴──────────────┬────────────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Supabase                                 │
├─────────────────────────────────────────────────────────────────┤
│  PostgreSQL    │  Auth (Admin)  │  Edge Functions  │  RLS       │
│  + RLS Policies│  JWT Tokens    │  - create-order  │  Security  │
│                │                │  - meta-events   │            │
│                │                │  - cf-images     │            │
└──────────────┬─────────────────┴────────────┬────────────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌────────────────────────────────┐
│   Cloudflare Images      │    │   External Services            │
│   (Product Images)       │    │   - Meta Conversions API       │
│   - AVIF/WebP variants   │    │   - Google Analytics 4         │
│   - CDN delivery         │    │   - Cloudflare Turnstile       │
└──────────────────────────┘    └────────────────────────────────┘
```

## ✨ Features

### Storefront
- 📦 Product catalog with categories
- 🔍 Search by product name
- 🖼️ Image gallery with lazy loading
- 🛒 Cart with localStorage persistence
- 📝 Guest checkout (COD only)
- ⭐ Product reviews (moderated)
- 📈 Upsell/Downsell suggestions
- 🔒 Cloudflare Turnstile protection
- 📊 GA4 + Meta Pixel tracking
- 🍪 GDPR-style consent banner

### Admin Dashboard
- 📋 Orders management with status workflow
- 📦 Products & Categories CRUD
- 🚚 Per-wilaya shipping rates
- 🛒 Abandoned carts monitoring
- ⭐ Reviews moderation
- 📈 Upsell/Downsell rules
- 📊 Analytics dashboard
- ⚙️ Store settings
- 📝 Full audit logging

### Security Features
- ✅ RLS (Row Level Security) on all tables
- ✅ Server-side price calculation
- ✅ Turnstile verification on checkout
- ✅ Rate limiting (IP + phone)
- ✅ Duplicate order detection
- ✅ Input validation
- ✅ Admin-only routes
- ✅ Audit logging

## 📁 Project Structure

```
├── index.html                    # Storefront (Arabic RTL)
├── admin.html                    # Admin Dashboard (Arabic RTL)
├── database.sql                  # PostgreSQL schema + RLS + seed data
├── supabase/
│   └── functions/
│       ├── create-order/         # Secure order creation
│       ├── meta-server-events/   # Server-side Meta tracking
│       └── cloudflare-images-upload/  # Secure image uploads
├── README.md                     # This file
├── INSTALL.md                    # Setup instructions
├── SECURITY.md                   # Security documentation
└── TRACKING_SPEC.md              # Analytics events specification
```

## 🚀 Quick Start

See [INSTALL.md](./INSTALL.md) for detailed setup instructions.

### Prerequisites
- Supabase account
- Cloudflare account (Pages + Images)
- Meta Business account (for Pixel)
- Google Analytics 4 property

### Environment Variables

هذا المشروع يستخدم **Runtime Public Config** عبر `config.js` (يتولد تلقائياً) + **Secrets** داخل Supabase Edge Functions.

#### 1) Public (تظهر في المتصفح) — تضعها في `.env.local` أو Cloudflare Pages env vars

```env
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
NEXT_PUBLIC_TURNSTILE_SITE_KEY=xxx
NEXT_PUBLIC_CF_IMAGES_ACCOUNT_ID=xxx
NEXT_PUBLIC_GA_MEASUREMENT_ID=G-xxx
NEXT_PUBLIC_META_PIXEL_ID=xxx
```

#### 2) Server-only (أسرار) — تضعها فقط في Supabase Secrets (ولا تُضاف للمتصفح)

```env
SUPABASE_SERVICE_ROLE_KEY=eyJ...
TURNSTILE_SECRET_KEY=xxx
META_ACCESS_TOKEN=xxx
CLOUDFLARE_ACCOUNT_ID=xxx
CLOUDFLARE_IMAGES_API_TOKEN=xxx
```

> راجع `INSTALL.md` (Step 3) لطريقة توليد `config.js` محلياً وعلى Cloudflare Pages.

## 🔐 Security

See [SECURITY.md](./SECURITY.md) for:
- RLS policies explanation
- Threat model
- Security checklist
- Best practices

## 📊 Tracking

See [TRACKING_SPEC.md](./TRACKING_SPEC.md) for:
- Event specifications
- Client-side vs server-side tracking
- Deduplication strategy
- COD purchase event handling

## 📦 Order Status Flow

```
New → PendingConfirmation → Confirmed → SentToCarrier → OutForDelivery → Delivered
                                ↓                              ↓
                           Cancelled                    Refused/Returned
```

## 🇩🇿 Algeria-Specific Features

- 58 Wilayas with Arabic names
- Phone validation (05/06/07 format)
- DZD currency formatting
- Office vs Home delivery options
- WorldExpress tracking integration ready
- COD-only payment flow

## 📄 License

MIT License - See LICENSE file

## 🤝 Support

For support, please open an issue on GitHub.
