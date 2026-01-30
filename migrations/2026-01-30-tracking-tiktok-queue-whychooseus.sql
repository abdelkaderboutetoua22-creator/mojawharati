-- 2026-01-30: TikTok server-side tracking queue + homepage why-choose-us setting (optional)
-- Safe, backwards-compatible. Does not weaken RLS.

-- 0) Ensure extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1) Optional: queue table for delayed Purchase event (COD)
CREATE TABLE IF NOT EXISTS public.pending_tracking_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL,
  event_id TEXT,
  event_data JSONB,
  trigger_status TEXT NOT NULL DEFAULT 'delivered',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pending_tracking_events_order ON public.pending_tracking_events(order_id);
CREATE INDEX IF NOT EXISTS idx_pending_tracking_events_created ON public.pending_tracking_events(created_at);

ALTER TABLE public.pending_tracking_events ENABLE ROW LEVEL SECURITY;

-- Only admins can read; inserts can be done by service role functions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pending_tracking_events' AND policyname='Pending tracking admin read'
  ) THEN
    CREATE POLICY "Pending tracking admin read" ON public.pending_tracking_events
      FOR SELECT TO authenticated
      USING (is_admin());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pending_tracking_events' AND policyname='Pending tracking service insert'
  ) THEN
    CREATE POLICY "Pending tracking service insert" ON public.pending_tracking_events
      FOR INSERT WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pending_tracking_events' AND policyname='Pending tracking service update'
  ) THEN
    CREATE POLICY "Pending tracking service update" ON public.pending_tracking_events
      FOR UPDATE USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 2) Ensure orders.public_token exists (refresh-safe confirmation page)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name='orders' AND column_name='public_token'
  ) THEN
    ALTER TABLE public.orders ADD COLUMN public_token UUID;
  END IF;
END $$;

UPDATE public.orders SET public_token = COALESCE(public_token, uuid_generate_v4());
ALTER TABLE public.orders ALTER COLUMN public_token SET DEFAULT uuid_generate_v4();
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_public_token ON public.orders(public_token);

-- 3) Ensure product options columns
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='sizes') THEN
    ALTER TABLE public.products ADD COLUMN sizes TEXT[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='colors') THEN
    ALTER TABLE public.products ADD COLUMN colors TEXT[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='products' AND column_name='description') THEN
    ALTER TABLE public.products ADD COLUMN description TEXT;
  END IF;
END $$;

-- 4) Ensure order item option storage
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='selected_size') THEN
    ALTER TABLE public.order_items ADD COLUMN selected_size TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='selected_color') THEN
    ALTER TABLE public.order_items ADD COLUMN selected_color TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='order_items' AND column_name='options') THEN
    ALTER TABLE public.order_items ADD COLUMN options JSONB;
  END IF;
END $$;

-- 5) Optional: homepage why-choose-us content as JSON (editable later)
INSERT INTO public.settings (key, value)
VALUES (
  'homepage_why_choose_us',
  '{"cards":[{"title":"توصيل سريع","desc":"نوصلك في أقرب وقت"},{"title":"الدفع عند الاستلام","desc":"ادفع بعد استلام الطلب"},{"title":"إرجاع مجاني","desc":"استبدال/إرجاع حسب الشروط"},{"title":"دعم مستمر","desc":"نجيبك على استفساراتك"}]}'
)
ON CONFLICT (key) DO NOTHING;
