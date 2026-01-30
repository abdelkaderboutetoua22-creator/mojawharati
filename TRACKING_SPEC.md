# 📊 Tracking Specification

Complete specification for analytics events, including client-side and server-side tracking.

---

## 1. Events Overview

| Event | Trigger | Client-Side | Server-Side | Platforms |
|-------|---------|-------------|-------------|-----------|
| PageView | Page load | ✅ | ❌ | GA4, Meta |
| ViewContent | Product page view | ✅ | ❌ | GA4, Meta |
| AddToCart | Add item to cart | ✅ | ❌ | GA4, Meta |
| InitiateCheckout | Start checkout | ✅ | ❌ | GA4, Meta |
| Purchase | Order confirmed/delivered | ✅ | ✅ | GA4, Meta |

---

## 2. Event Details

### 2.1 PageView

**Trigger**: Every page load (after consent)

**GA4 Event**: `page_view` (automatic)

**Meta Event**: `PageView`

**Payload**: None (automatic)

---

### 2.2 ViewContent

**Trigger**: Product detail page viewed

**GA4 Event**: `view_item`

**Meta Event**: `ViewContent`

**Payload**:
```javascript
{
    content_ids: ['product_uuid'],
    content_name: 'Product Name',
    content_type: 'product',
    value: 2500,  // Price in DZD
    currency: 'DZD'
}
```

**Implementation**:
```javascript
trackEvent('ViewContent', {
    content_ids: [product.id],
    content_name: product.name,
    content_type: 'product',
    value: product.price,
    currency: 'DZD'
});
```

---

### 2.3 AddToCart

**Trigger**: Product added to cart

**GA4 Event**: `add_to_cart`

**Meta Event**: `AddToCart`

**Payload**:
```javascript
{
    content_ids: ['product_uuid'],
    content_name: 'Product Name',
    content_type: 'product',
    value: 5000,  // Total value (price * quantity)
    currency: 'DZD'
}
```

**Implementation**:
```javascript
trackEvent('AddToCart', {
    content_ids: [product.id],
    content_name: product.name,
    content_type: 'product',
    value: product.price * quantity,
    currency: 'DZD'
});
```

---

### 2.4 InitiateCheckout

**Trigger**: Checkout page loaded

**GA4 Event**: `begin_checkout`

**Meta Event**: `InitiateCheckout`

**Payload**:
```javascript
{
    content_ids: ['uuid1', 'uuid2'],
    num_items: 3,
    value: 7500,  // Cart subtotal
    currency: 'DZD'
}
```

**Implementation**:
```javascript
trackEvent('InitiateCheckout', {
    content_ids: cart.map(i => i.id),
    num_items: cart.reduce((s, i) => s + i.quantity, 0),
    value: calculateSubtotal(),
    currency: 'DZD'
});
```

---

### 2.5 Purchase

**Trigger**: Configurable (see COD Settings)

**GA4 Event**: `purchase`

**Meta Event**: `Purchase`

**Payload**:
```javascript
{
    content_ids: ['uuid1', 'uuid2'],
    content_type: 'product',
    value: 8100,  // Total including shipping
    currency: 'DZD',
    order_id: 'order_uuid'
}
```

---

## 3. COD Purchase Event Timing

For Cash on Delivery, the Purchase event timing is **configurable**:

### Option A: At Confirmation (Default)

- Purchase event fires when order status changes to `confirmed`
- Faster attribution for ad optimization
- May include orders that are later refused

### Option B: At Delivery

- Purchase event fires when order status changes to `delivered`
- More accurate revenue tracking
- Delayed attribution (affects ad optimization)

### Configuration

Set in Admin → Settings → "حدث الشراء (COD)"

**Implementation** (server-side):
```typescript
// In meta-server-events Edge Function
const purchaseEventTrigger = settings?.value || "confirmed";

if (purchaseEventTrigger === "delivered") {
    // Queue event for later
    await supabase.from("pending_tracking_events").insert({
        order_id: orderId,
        trigger_status: "delivered"
    });
} else {
    // Send immediately
    await sendToMeta(event);
}
```

---

## 4. Deduplication Strategy

### Problem
Both client-side pixel and server-side API might send the same event.

### Solution
Use `event_id` for deduplication:

```javascript
// Client-side
const eventId = generateEventId(); // 'evt_1234567890_abc123'
fbq('track', 'Purchase', params, { eventID: eventId });

// Server-side (same event_id)
{
    "event_name": "Purchase",
    "event_id": "evt_1234567890_abc123",  // Must match client
    ...
}
```

### Event ID Format
```javascript
function generateEventId() {
    return 'evt_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}
```

---

## 5. Server-Side Tracking (Meta Conversions API)

### Why Server-Side?

1. **Reliability**: Not blocked by ad blockers
2. **Privacy**: Better control over data sent
3. **Accuracy**: Works even if user closes browser quickly

### Implementation

```typescript
// Edge Function: meta-server-events

const eventPayload = {
    data: [{
        event_name: "Purchase",
        event_time: Math.floor(Date.now() / 1000),
        event_id: eventId,  // For deduplication
        action_source: "website",
        user_data: {
            ph: await hashSHA256(phone),  // Hashed phone
            client_ip_address: clientIP,
            client_user_agent: userAgent,
            fbc: fbClickId,  // If available
            fbp: fbBrowserId  // If available
        },
        custom_data: {
            value: total,
            currency: "DZD",
            content_ids: productIds,
            content_type: "product"
        }
    }]
};

await fetch(`https://graph.facebook.com/v18.0/${pixelId}/events`, {
    method: "POST",
    body: JSON.stringify(eventPayload)
});
```

### PII Hashing

Phone numbers MUST be hashed before sending:

```typescript
async function hashSHA256(text: string): Promise<string> {
    // Normalize: remove leading 0, add country code
    const normalized = "213" + text.substring(1);
    
    const encoder = new TextEncoder();
    const data = encoder.encode(normalized);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
}
```

---

## 6. Consent Management

### Flow

```
1. User visits site
2. Check localStorage for consent status
3. If not set → Show consent banner
4. If accepted → Initialize tracking
5. If rejected → Skip all tracking
```

### Implementation

```javascript
function checkConsent() {
    const consent = localStorage.getItem('consentGiven');
    if (consent === null) {
        showConsentBanner();
    } else if (consent === 'true') {
        initTracking();
    }
}

function acceptConsent() {
    localStorage.setItem('consentGiven', 'true');
    initTracking();
    hideConsentBanner();
}

function rejectConsent() {
    localStorage.setItem('consentGiven', 'false');
    hideConsentBanner();
}
```

### Banner Text (Arabic)

```
نستخدم ملفات تعريف الارتباط لتحسين تجربتك. 
بالمتابعة، أنت توافق على سياسة الخصوصية.

[موافق] [رفض]
```

---

## 7. GA4 Configuration

### Custom Dimensions (Optional)

| Dimension | Scope | Value |
|-----------|-------|-------|
| wilaya | Event | Wilaya code (01-58) |
| delivery_type | Event | office / home |
| order_status | Event | Order status |

### E-commerce Configuration

GA4 Enhanced E-commerce is enabled automatically with:
- `view_item` events
- `add_to_cart` events
- `begin_checkout` events
- `purchase` events

---

## 8. Testing Events

### Meta Pixel Helper

1. Install [Meta Pixel Helper](https://chrome.google.com/webstore/detail/meta-pixel-helper/fdgfkebogiimcoedlicjlajpkdmockpc)
2. Visit your site
3. Check each event fires correctly
4. Verify deduplication IDs match

### Meta Events Manager

1. Go to Events Manager → Test Events
2. Copy your test event code
3. Add to URL: `?fbclid=test123`
4. Perform actions and verify in real-time

### GA4 DebugView

1. Install [Google Analytics Debugger](https://chrome.google.com/webstore/detail/google-analytics-debugger/jnkmfdileelhofjcijamephohjechhna)
2. Go to GA4 → Configure → DebugView
3. Perform actions and verify events

---

## 9. Event Flow Diagram

```
User Action          Client-Side              Server-Side
    │                     │                        │
    ├── Page Load ──────► PageView                 │
    │                     │                        │
    ├── View Product ───► ViewContent              │
    │                     │                        │
    ├── Add to Cart ────► AddToCart                │
    │                     │                        │
    ├── Start Checkout ─► InitiateCheckout         │
    │                     │                        │
    ├── Submit Order ───► Purchase ──────────────► Purchase (CAPI)
    │                     (event_id: abc123)       (event_id: abc123)
    │                                              ▲
    │                                              │ Deduplicated
    │                                              │ by Meta
    ▼                                              ▼
```

---

## 10. Troubleshooting

### Events Not Firing

1. Check consent is accepted
2. Check Pixel ID is correct
3. Check browser console for errors
4. Verify ad blockers are disabled for testing

### Duplicate Events

1. Verify `event_id` is same on client and server
2. Check Meta Events Manager for dedup status
3. Ensure Purchase is only fired once per order

### Server Events Failing

1. Check Edge Function logs in Supabase
2. Verify Meta access token is valid
3. Check Pixel ID in environment variables
4. Test with Meta's Event Testing tool
