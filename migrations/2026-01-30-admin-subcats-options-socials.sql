-- 2026-01-30: Subcategories + product options + order item options + social links policy
-- Backwards-compatible, does not weaken RLS.

-- 1) Categories: parent-child relationship (subcategories)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='categories' AND column_name='parent_id'
  ) THEN
    ALTER TABLE public.categories ADD COLUMN parent_id UUID NULL REFERENCES public.categories(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_categories_parent_id ON public.categories(parent_id);

-- 2) Products: description + options (simple and fast)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products' AND column_name='description'
  ) THEN
    ALTER TABLE public.products ADD COLUMN description TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products' AND column_name='sizes'
  ) THEN
    ALTER TABLE public.products ADD COLUMN sizes TEXT[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products' AND column_name='colors'
  ) THEN
    ALTER TABLE public.products ADD COLUMN colors TEXT[];
  END IF;
END $$;

-- 3) Order items: store selected options (backwards compatible)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='order_items' AND column_name='selected_size'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN selected_size TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='order_items' AND column_name='selected_color'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN selected_color TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='order_items' AND column_name='options'
  ) THEN
    ALTER TABLE public.order_items ADD COLUMN options JSONB;
  END IF;
END $$;

-- 4) Settings: extend public read policy keys for new social links
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
