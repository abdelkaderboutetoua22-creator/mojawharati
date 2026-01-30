# 🔐 Security Documentation

## Overview

This document outlines the security architecture, RLS policies, threat model, and security checklist for the Algeria E-Commerce Platform.

---

## 1. Row Level Security (RLS) Policies

RLS is enabled on **ALL** tables. Here's the complete policy breakdown:

### Public Tables (Read-Only)

| Table | Policy | Access |
|-------|--------|--------|
| `products` | `is_active = true` | Public can read active products only |
| `categories` | `is_active = true` | Public can read active categories only |
| `wilayas` | `true` | Public can read all wilayas |
| `shipping_rates` | `is_enabled = true` | Public can read enabled rates only |
| `reviews` | `status = 'approved'` | Public can read approved reviews only |
| `upsell_rules` | `is_active = true` | Public can read active rules only |
| `settings` | specific keys only | Public can read social links & consent setting |

### Public Tables (Insert-Only)

| Table | Policy | Notes |
|-------|--------|-------|
| `reviews` | Insert allowed | Anyone can submit a review (moderated) |
| `carts` | Insert/Update allowed | For abandoned cart tracking |

### Admin-Only Tables

| Table | Policy |
|-------|--------|
| `orders` | Full access for authenticated admins |
| `order_items` | Full access for authenticated admins |
| `order_status_history` | Full access for authenticated admins |
| `admin_roles` | Full access for authenticated admins |
| `audit_logs` | Read-only for admins |
| `rate_limits` | Service role only |

### Helper Functions

```sql
-- Check if current user is any admin
CREATE FUNCTION is_admin() RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_roles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'support')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if current user is full admin
CREATE FUNCTION is_full_admin() RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_roles 
        WHERE user_id = auth.uid() AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Role Permissions

| Action | Admin | Support |
|--------|-------|---------|
| View orders | ✅ | ✅ |
| Update order status | ✅ | ✅ |
| Create/edit products | ✅ | ✅ |
| Delete products | ✅ | ❌ |
| Manage shipping rates | ✅ | ✅ |
| Manage settings | ✅ | ❌ |
| View audit logs | ✅ | ✅ |
| Manage admin users | ✅ | ❌ |

---

## 2. Order Creation Security

Orders are created **exclusively** via the `create-order` Edge Function, which enforces:

### Input Validation

```typescript
// Phone validation (Algerian format)
const phoneRegex = /^0[567]\d{8}$/;

// Required fields check
if (!body.full_name?.trim()) throw "Name required";
if (!phoneRegex.test(body.phone)) throw "Invalid phone";
if (!validWilayas.includes(body.wilaya)) throw "Invalid wilaya";
if (!['office', 'home'].includes(body.delivery_type)) throw "Invalid delivery type";
if (body.delivery_type === 'home' && !body.address?.trim()) throw "Address required";
```

### Server-Side Price Calculation

```typescript
// NEVER trust client-side prices
const { data: products } = await supabase
    .from("products")
    .select("id, price")
    .in("id", productIds);

// Calculate totals from database
let subtotal = 0;
cartItems.forEach(item => {
    const dbProduct = products.find(p => p.id === item.product_id);
    subtotal += dbProduct.price * item.quantity;
});

// Get shipping from database
const { data: rate } = await supabase
    .from("shipping_rates")
    .select("price")
    .eq("wilaya_code", wilaya)
    .eq("delivery_type", deliveryType)
    .single();
```

### Turnstile Verification

```typescript
const response = await fetch(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    {
        method: "POST",
        body: `secret=${secret}&response=${token}&remoteip=${clientIP}`,
    }
);
if (!result.success) throw "Verification failed";
```

### Rate Limiting

| Limit | Threshold | Window |
|-------|-----------|--------|
| Per IP | 10 orders | 1 hour |
| Per Phone | 3 orders | 1 hour |

### Duplicate Detection

- Checks for orders with same phone in last 5 minutes
- Compares cart items to detect exact duplicates

---

## 3. Threat Model

### Threat: Price Manipulation
- **Attack**: Client modifies prices before checkout
- **Mitigation**: All prices calculated server-side from database

### Threat: Spam Orders
- **Attack**: Bot submits fake orders
- **Mitigation**: Turnstile + rate limiting + duplicate detection

### Threat: Admin Account Compromise
- **Attack**: Attacker gains admin access
- **Mitigation**: 
  - Strong password requirements
  - Audit logging of all actions
  - Role-based access control
  - Sessions can be revoked in Supabase

### Threat: Data Exposure
- **Attack**: Unauthorized access to customer data
- **Mitigation**:
  - RLS prevents public access to orders
  - Sensitive data only accessible to admins
  - No passwords stored (Supabase Auth handles this)

### Threat: XSS/Injection
- **Attack**: Malicious scripts in product descriptions
- **Mitigation**:
  - Input sanitization
  - Content Security Policy (Cloudflare Pages)
  - No `eval()` or `innerHTML` with user data

### Threat: CSRF
- **Attack**: Forged requests from other sites
- **Mitigation**:
  - SameSite cookies
  - JWT token verification
  - Origin validation

### Threat: API Key Exposure
- **Attack**: Secrets exposed in client code
- **Mitigation**:
  - Only anon key in client (public)
  - Service role key in Edge Functions only
  - Cloudflare API tokens server-side only

---

## 4. Security Checklist

### Pre-Launch

- [ ] All RLS policies verified in SQL
- [ ] Edge Functions using service role key (not anon)
- [ ] Turnstile configured with production keys
- [ ] No secrets in client-side code
- [ ] Admin user has strong password
- [ ] Rate limiting thresholds appropriate
- [ ] Audit logging enabled

### Configuration

- [ ] Supabase: RLS enabled on all tables
- [ ] Supabase: Email confirmation disabled (admin-only auth)
- [ ] Cloudflare: HTTPS enforced
- [ ] Cloudflare: Security headers configured
- [ ] Images: Signed URLs for private images (if needed)

### Monitoring

- [ ] Supabase Logs accessible
- [ ] Edge Function logs reviewed
- [ ] Audit logs regularly checked
- [ ] Failed login attempts monitored
- [ ] Rate limit hits monitored

### Recommended Cloudflare Security Headers

```
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

---

## 5. Data Privacy

### PII Handling

| Data | Storage | Encryption | Retention |
|------|---------|------------|-----------|
| Customer Name | Orders table | At rest (Supabase) | Indefinite |
| Phone Number | Orders table | At rest | Indefinite |
| Address | Orders table | At rest | Indefinite |
| IP Address | Orders table | At rest | 90 days (recommended) |

### Meta Tracking Compliance

- Phone numbers are **SHA256 hashed** before sending to Meta
- Event IDs used for **deduplication** (no duplicate tracking)
- **Consent banner** must be shown before tracking
- No PII sent to GA4

### Recommended Data Retention

```sql
-- Clean up old rate limits (run weekly)
DELETE FROM rate_limits 
WHERE created_at < NOW() - INTERVAL '7 days';

-- Clean up old audit logs (run monthly)
DELETE FROM audit_logs 
WHERE created_at < NOW() - INTERVAL '1 year';

-- Anonymize old order IPs (run monthly)
UPDATE orders 
SET ip_address = NULL 
WHERE created_at < NOW() - INTERVAL '90 days';
```

---

## 6. Incident Response

### If Admin Account Compromised

1. Immediately disable user in Supabase Auth
2. Revoke all sessions
3. Review audit logs for unauthorized actions
4. Reset admin password
5. Review and rollback any malicious changes

### If Database Breach Suspected

1. Rotate Supabase service role key
2. Review Supabase logs
3. Check for unauthorized RLS policy changes
4. Notify affected customers if PII exposed

### If API Keys Exposed

1. Immediately rotate the exposed key
2. Update Edge Function secrets
3. Redeploy affected functions
4. Review logs for unauthorized usage

---

## 7. Security Updates

### Regular Maintenance

- [ ] Weekly: Review failed order attempts
- [ ] Weekly: Check rate limit effectiveness
- [ ] Monthly: Audit admin user list
- [ ] Monthly: Review audit logs for anomalies
- [ ] Quarterly: Rotate API tokens
- [ ] Quarterly: Review and update RLS policies

### Dependency Updates

- Monitor Supabase client library updates
- Monitor Deno standard library updates
- Keep Cloudflare Turnstile script up to date
