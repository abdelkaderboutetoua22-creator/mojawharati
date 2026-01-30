-- =====================================================
-- ALGERIA E-COMMERCE DATABASE SCHEMA
-- Supabase PostgreSQL Migration
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- TABLES
-- =====================================================

-- Categories
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Products
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    compare_price DECIMAL(10,2),
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    images TEXT[] DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Wilayas (58 Algerian provinces)
CREATE TABLE wilayas (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_ar TEXT NOT NULL
);

-- Shipping Rates
CREATE TABLE shipping_rates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wilaya_code TEXT NOT NULL REFERENCES wilayas(code),
    delivery_type TEXT NOT NULL CHECK (delivery_type IN ('office', 'home')),
    price DECIMAL(10,2) NOT NULL DEFAULT 0,
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(wilaya_code, delivery_type)
);

-- Orders
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name TEXT NOT NULL,
    phone TEXT NOT NULL,
    wilaya TEXT NOT NULL,
    commune TEXT,
    address TEXT,
    delivery_type TEXT NOT NULL CHECK (delivery_type IN ('office', 'home')),
    note TEXT,
    subtotal DECIMAL(10,2) NOT NULL,
    shipping DECIMAL(10,2) NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN (
        'new', 'pending_confirmation', 'confirmed', 'sent_to_carrier',
        'out_for_delivery', 'delivered', 'refused', 'returned', 'cancelled'
    )),
    tracking_number TEXT,
    ip_address INET,
    user_agent TEXT,
    event_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Order Items
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Order Status History
CREATE TABLE order_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status TEXT NOT NULL,
    changed_by UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Carts (for abandoned cart tracking)
CREATE TABLE carts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone TEXT,
    items JSONB DEFAULT '[]',
    total_value DECIMAL(10,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Reviews
CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    reviewer_name TEXT NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Upsell/Downsell Rules
CREATE TABLE upsell_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type TEXT NOT NULL CHECK (type IN ('upsell', 'downsell')),
    trigger_product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    upsell_product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    discount_percent INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Admin Roles
CREATE TABLE admin_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('admin', 'support')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Settings
CREATE TABLE settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key TEXT NOT NULL UNIQUE,
    value TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit Logs
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID,
    action TEXT NOT NULL,
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Rate Limiting (for order spam prevention)
CREATE TABLE rate_limits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    identifier TEXT NOT NULL, -- IP or phone
    identifier_type TEXT NOT NULL CHECK (identifier_type IN ('ip', 'phone')),
    action TEXT NOT NULL,
    count INTEGER DEFAULT 1,
    window_start TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- INDEXES
-- =====================================================

CREATE INDEX idx_products_active_created ON products(is_active, created_at DESC);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_orders_status_created ON orders(status, created_at DESC);
CREATE INDEX idx_orders_phone ON orders(phone);
CREATE INDEX idx_orders_wilaya ON orders(wilaya);
CREATE INDEX idx_orders_created ON orders(created_at DESC);
CREATE INDEX idx_carts_updated ON carts(updated_at);
CREATE INDEX idx_reviews_product_status ON reviews(product_id, status);
CREATE INDEX idx_shipping_rates_wilaya ON shipping_rates(wilaya_code);
CREATE INDEX idx_rate_limits_identifier ON rate_limits(identifier, identifier_type, action, window_start);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC);

-- =====================================================
-- UPDATED_AT TRIGGER
-- =====================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_carts_updated_at BEFORE UPDATE ON carts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_shipping_rates_updated_at BEFORE UPDATE ON shipping_rates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_settings_updated_at BEFORE UPDATE ON settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- ROW LEVEL SECURITY (RLS)
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE wilayas ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipping_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE upsell_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS POLICIES
-- =====================================================

-- Helper function to check if user is admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_roles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'support')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_full_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM admin_roles 
        WHERE user_id = auth.uid() AND role = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Categories: Public read, Admin write
CREATE POLICY "Categories public read" ON categories FOR SELECT USING (is_active = true);
CREATE POLICY "Categories admin read all" ON categories FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "Categories admin insert" ON categories FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "Categories admin update" ON categories FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "Categories admin delete" ON categories FOR DELETE TO authenticated USING (is_full_admin());

-- Products: Public read active, Admin all
CREATE POLICY "Products public read active" ON products FOR SELECT USING (is_active = true);
CREATE POLICY "Products admin read all" ON products FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "Products admin insert" ON products FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "Products admin update" ON products FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "Products admin delete" ON products FOR DELETE TO authenticated USING (is_full_admin());

-- Wilayas: Public read
CREATE POLICY "Wilayas public read" ON wilayas FOR SELECT USING (true);
CREATE POLICY "Wilayas admin write" ON wilayas FOR ALL TO authenticated USING (is_full_admin());

-- Shipping Rates: Public read enabled, Admin all
CREATE POLICY "Shipping rates public read" ON shipping_rates FOR SELECT USING (is_enabled = true);
CREATE POLICY "Shipping rates admin read all" ON shipping_rates FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "Shipping rates admin write" ON shipping_rates FOR ALL TO authenticated USING (is_admin());

-- Orders: Admin only (orders created via Edge Function)
CREATE POLICY "Orders admin access" ON orders FOR ALL TO authenticated USING (is_admin());
-- Service role can insert (for Edge Function)
CREATE POLICY "Orders service insert" ON orders FOR INSERT WITH CHECK (true);

-- Order Items: Admin only
CREATE POLICY "Order items admin access" ON order_items FOR ALL TO authenticated USING (is_admin());
CREATE POLICY "Order items service insert" ON order_items FOR INSERT WITH CHECK (true);

-- Order Status History: Admin only
CREATE POLICY "Order history admin access" ON order_status_history FOR ALL TO authenticated USING (is_admin());
CREATE POLICY "Order history service insert" ON order_status_history FOR INSERT WITH CHECK (true);

-- Carts: Public insert/update own, Admin read all
CREATE POLICY "Carts public insert" ON carts FOR INSERT WITH CHECK (true);
CREATE POLICY "Carts public update" ON carts FOR UPDATE USING (true);
CREATE POLICY "Carts admin read" ON carts FOR SELECT TO authenticated USING (is_admin());

-- Reviews: Public read approved, Public insert, Admin all
CREATE POLICY "Reviews public read approved" ON reviews FOR SELECT USING (status = 'approved');
CREATE POLICY "Reviews public insert" ON reviews FOR INSERT WITH CHECK (true);
CREATE POLICY "Reviews admin access" ON reviews FOR ALL TO authenticated USING (is_admin());

-- Upsell Rules: Public read active, Admin all
CREATE POLICY "Upsell rules public read" ON upsell_rules FOR SELECT USING (is_active = true);
CREATE POLICY "Upsell rules admin access" ON upsell_rules FOR ALL TO authenticated USING (is_admin());

-- Admin Roles: Admin only
CREATE POLICY "Admin roles access" ON admin_roles FOR ALL TO authenticated USING (is_admin());

-- Settings: Public read some, Admin all
CREATE POLICY "Settings public read" ON settings FOR SELECT USING (
    key IN ('facebook', 'instagram', 'tiktok', 'consent_banner')
);
CREATE POLICY "Settings admin access" ON settings FOR ALL TO authenticated USING (is_admin());

-- Audit Logs: Admin read only
CREATE POLICY "Audit logs admin read" ON audit_logs FOR SELECT TO authenticated USING (is_admin());
CREATE POLICY "Audit logs insert" ON audit_logs FOR INSERT WITH CHECK (true);

-- Rate Limits: Service only (accessed via Edge Functions)
CREATE POLICY "Rate limits service access" ON rate_limits FOR ALL USING (true);

-- =====================================================
-- SEED DATA: 58 WILAYAS OF ALGERIA
-- =====================================================

INSERT INTO wilayas (code, name, name_ar) VALUES
('01', 'Adrar', 'أدرار'),
('02', 'Chlef', 'الشلف'),
('03', 'Laghouat', 'الأغواط'),
('04', 'Oum El Bouaghi', 'أم البواقي'),
('05', 'Batna', 'باتنة'),
('06', 'Béjaïa', 'بجاية'),
('07', 'Biskra', 'بسكرة'),
('08', 'Béchar', 'بشار'),
('09', 'Blida', 'البليدة'),
('10', 'Bouira', 'البويرة'),
('11', 'Tamanrasset', 'تمنراست'),
('12', 'Tébessa', 'تبسة'),
('13', 'Tlemcen', 'تلمسان'),
('14', 'Tiaret', 'تيارت'),
('15', 'Tizi Ouzou', 'تيزي وزو'),
('16', 'Alger', 'الجزائر'),
('17', 'Djelfa', 'الجلفة'),
('18', 'Jijel', 'جيجل'),
('19', 'Sétif', 'سطيف'),
('20', 'Saïda', 'سعيدة'),
('21', 'Skikda', 'سكيكدة'),
('22', 'Sidi Bel Abbès', 'سيدي بلعباس'),
('23', 'Annaba', 'عنابة'),
('24', 'Guelma', 'قالمة'),
('25', 'Constantine', 'قسنطينة'),
('26', 'Médéa', 'المدية'),
('27', 'Mostaganem', 'مستغانم'),
('28', 'M''Sila', 'المسيلة'),
('29', 'Mascara', 'معسكر'),
('30', 'Ouargla', 'ورقلة'),
('31', 'Oran', 'وهران'),
('32', 'El Bayadh', 'البيض'),
('33', 'Illizi', 'إليزي'),
('34', 'Bordj Bou Arreridj', 'برج بوعريريج'),
('35', 'Boumerdès', 'بومرداس'),
('36', 'El Tarf', 'الطارف'),
('37', 'Tindouf', 'تندوف'),
('38', 'Tissemsilt', 'تيسمسيلت'),
('39', 'El Oued', 'الوادي'),
('40', 'Khenchela', 'خنشلة'),
('41', 'Souk Ahras', 'سوق أهراس'),
('42', 'Tipaza', 'تيبازة'),
('43', 'Mila', 'ميلة'),
('44', 'Aïn Defla', 'عين الدفلى'),
('45', 'Naâma', 'النعامة'),
('46', 'Aïn Témouchent', 'عين تموشنت'),
('47', 'Ghardaïa', 'غرداية'),
('48', 'Relizane', 'غليزان'),
('49', 'El M''Ghair', 'المغير'),
('50', 'El Meniaa', 'المنيعة'),
('51', 'Ouled Djellal', 'أولاد جلال'),
('52', 'Bordj Badji Mokhtar', 'برج باجي مختار'),
('53', 'Béni Abbès', 'بني عباس'),
('54', 'Timimoun', 'تيميمون'),
('55', 'Touggourt', 'تقرت'),
('56', 'Djanet', 'جانت'),
('57', 'In Salah', 'عين صالح'),
('58', 'In Guezzam', 'عين قزام');

-- =====================================================
-- SEED DATA: DEFAULT SHIPPING RATES
-- =====================================================

-- Insert default shipping rates for all wilayas (can be adjusted later)
INSERT INTO shipping_rates (wilaya_code, delivery_type, price, is_enabled)
SELECT code, 'office', 400, true FROM wilayas
UNION ALL
SELECT code, 'home', 600, true FROM wilayas;

-- Adjust rates for major cities
UPDATE shipping_rates SET price = 300 WHERE wilaya_code = '16' AND delivery_type = 'office';
UPDATE shipping_rates SET price = 400 WHERE wilaya_code = '16' AND delivery_type = 'home';
UPDATE shipping_rates SET price = 350 WHERE wilaya_code = '31' AND delivery_type = 'office';
UPDATE shipping_rates SET price = 500 WHERE wilaya_code = '31' AND delivery_type = 'home';

-- =====================================================
-- SEED DATA: DEFAULT SETTINGS
-- =====================================================

INSERT INTO settings (key, value) VALUES
('purchase_event', 'confirmed'),
('consent_banner', 'true'),
('facebook', ''),
('instagram', ''),
('tiktok', ''),
('abandoned_cart_minutes', '60');

-- =====================================================
-- CREATE FIRST ADMIN USER (Run after creating auth user)
-- Replace 'YOUR_USER_ID' with the actual user ID from auth.users
-- =====================================================

-- INSERT INTO admin_roles (user_id, role) VALUES ('YOUR_USER_ID', 'admin');
