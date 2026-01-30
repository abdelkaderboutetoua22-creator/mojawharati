-- 2026-01-24: Product options + product images + order item options + wilayas 58
-- Security: does NOT weaken RLS; keep existing policies.

-- 1) Products: description (if missing), sizes, colors
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='products' AND column_name='description'
  ) THEN
    ALTER TABLE products ADD COLUMN description TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='products' AND column_name='sizes'
  ) THEN
    ALTER TABLE products ADD COLUMN sizes TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='products' AND column_name='colors'
  ) THEN
    ALTER TABLE products ADD COLUMN colors TEXT[];
  END IF;
END $$;

-- 2) Product images table (Cloudflare image IDs or URLs)
CREATE TABLE IF NOT EXISTS product_images (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  image_id TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_product_images_product_order ON product_images(product_id, sort_order);

ALTER TABLE product_images ENABLE ROW LEVEL SECURITY;

-- Public can read (only for active products)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='product_images' AND policyname='Product images public read'
  ) THEN
    CREATE POLICY "Product images public read" ON product_images
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM products p
          WHERE p.id = product_images.product_id AND p.is_active = true
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='product_images' AND policyname='Product images admin access'
  ) THEN
    CREATE POLICY "Product images admin access" ON product_images
      FOR ALL TO authenticated
      USING (is_admin())
      WITH CHECK (is_admin());
  END IF;
END $$;

-- 3) Order items: options support (backwards compatible)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='selected_size'
  ) THEN
    ALTER TABLE order_items ADD COLUMN selected_size TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='selected_color'
  ) THEN
    ALTER TABLE order_items ADD COLUMN selected_color TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='options'
  ) THEN
    ALTER TABLE order_items ADD COLUMN options JSONB;
  END IF;
END $$;

-- 4) Wilayas: ensure 58 entries exist (adds the 10 newer wilayas if missing)
INSERT INTO wilayas (code, name, name_ar)
VALUES
  ('49', 'El M''Ghair', 'المغير'),
  ('50', 'El Meniaa', 'المنيعة'),
  ('51', 'Ouled Djellal', 'أولاد جلال'),
  ('52', 'Bordj Badji Mokhtar', 'برج باجي مختار'),
  ('53', 'Béni Abbès', 'بني عباس'),
  ('54', 'Timimoun', 'تيميمون'),
  ('55', 'Touggourt', 'توقرت'),
  ('56', 'Djanet', 'جانت'),
  ('57', 'In Salah', 'عين صالح'),
  ('58', 'In Guezzam', 'عين قزام')
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    name_ar = EXCLUDED.name_ar;

-- 5) Shipping rates: ensure both office/home exist for all wilayas
INSERT INTO shipping_rates (wilaya_code, delivery_type, price, is_enabled)
SELECT w.code, 'office', 0, true
FROM wilayas w
WHERE NOT EXISTS (
  SELECT 1 FROM shipping_rates r WHERE r.wilaya_code = w.code AND r.delivery_type = 'office'
);

INSERT INTO shipping_rates (wilaya_code, delivery_type, price, is_enabled)
SELECT w.code, 'home', 0, true
FROM wilayas w
WHERE NOT EXISTS (
  SELECT 1 FROM shipping_rates r WHERE r.wilaya_code = w.code AND r.delivery_type = 'home'
);
