-- 2026-01-29: Tracking additions, social links keys, subcategories, public order token, options columns, wilayas 58 safety
-- Safe, backwards-compatible migration. Does not weaken RLS.

-- 1) Categories: parent-child relationship (subcategories)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='categories' AND column_name='parent_id'
  ) THEN
    ALTER TABLE public.categories ADD COLUMN parent_id UUID NULL REFERENCES public.categories(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON public.categories(parent_id);

-- 2) Orders: public token for customer order confirmation lookup
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='orders' AND column_name='public_token'
  ) THEN
    ALTER TABLE public.orders ADD COLUMN public_token UUID;
  END IF;
END $$;

-- Backfill + default
UPDATE public.orders
SET public_token = COALESCE(public_token, uuid_generate_v4());

ALTER TABLE public.orders
  ALTER COLUMN public_token SET DEFAULT uuid_generate_v4();

CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_public_token ON public.orders(public_token);

-- 3) Product options (sizes/colors) if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='products' AND column_name='sizes'
  ) THEN
    ALTER TABLE public.products ADD COLUMN sizes TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='products' AND column_name='colors'
  ) THEN
    ALTER TABLE public.products ADD COLUMN colors TEXT[];
  END IF;
END $$;

-- 4) Order items: store selected options (backwards compatible)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='selected_size'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN selected_size TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='selected_color'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN selected_color TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='order_items' AND column_name='options'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN options JSONB;
  END IF;
END $$;

-- 5) Settings: extend public read policy keys for new social links
-- NOTE: we RECREATE the policy to include new keys.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='settings' AND policyname='Settings public read'
  ) THEN
    DROP POLICY "Settings public read" ON public.settings;
  END IF;

  CREATE POLICY "Settings public read" ON public.settings
    FOR SELECT USING (
      key IN (
        'facebook','instagram','tiktok','consent_banner',
        'telegram','snapchat','youtube','twitter','whatsapp'
      )
    );
END $$;

-- 6) Wilayas: ensure 58 entries exist
INSERT INTO public.wilayas (code, name, name_ar)
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

-- 7) Shipping rates: ensure office/home exist for all wilayas
INSERT INTO public.shipping_rates (wilaya_code, delivery_type, price, is_enabled)
SELECT w.code, 'office', 0, true
FROM public.wilayas w
WHERE NOT EXISTS (
  SELECT 1 FROM public.shipping_rates r WHERE r.wilaya_code = w.code AND r.delivery_type = 'office'
);

INSERT INTO public.shipping_rates (wilaya_code, delivery_type, price, is_enabled)
SELECT w.code, 'home', 0, true
FROM public.wilayas w
WHERE NOT EXISTS (
  SELECT 1 FROM public.shipping_rates r WHERE r.wilaya_code = w.code AND r.delivery_type = 'home'
);
