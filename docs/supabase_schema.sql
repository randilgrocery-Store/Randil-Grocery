-- ===========================================================================
-- Randil Grocery POS - Supabase setup script
-- Run this ONCE in your Supabase project:  supabase.com -> SQL Editor -> paste -> Run
-- The desktop POS and phone app are pre-configured with this shop's project,
-- so after running this script use Settings -> Cloud -> Save & Sync Now.
-- ===========================================================================

-- 1) Sales (push created for every completed sale; store totals + line items)
create table if not exists public.sales_sync (
  id            text primary key,
  bill_number   text not null default '',
  amount        double precision not null default 0,
  discount      double precision not null default 0,
  tax           double precision not null default 0,
  payment_method text not null default 'Cash',
  items_count   integer not null default 0,
  items_json    jsonb not null default '[]'::jsonb,
  cashier       text not null default '',
  timestamp     timestamptz not null default now(),
  synced_at     timestamptz not null default now()
);

-- 2) Live product snapshot (stock levels, prices, categories)
create table if not exists public.products_snapshot (
  id                 text primary key,
  name               text not null,
  barcode            text not null default '',
  category           text not null default '',
  price              double precision not null default 0,
  cost               double precision not null default 0,
  stock              double precision not null default 0,
  unit               text not null default '',
  low_stock_threshold double precision not null default 0,
  updated_at         timestamptz not null default now()
);

-- 3) Customers (loyalty points, lifetime spend, visits)
create table if not exists public.customers_sync (
  id            text primary key,
  name          text not null default '',
  phone         text not null default '',
  email         text not null default '',
  loyalty_points double precision not null default 0,
  total_spend   double precision not null default 0,
  visits        integer not null default 0,
  updated_at    timestamptz not null default now()
);

-- 4) Goods Received Notes (supplier deliveries)
create table if not exists public.supplier_grns_sync (
  id            text primary key,
  grn_number    text not null default '',
  supplier_name text not null default '',
  amount        double precision not null default 0,
  items_count   integer not null default 0,
  items_json    jsonb not null default '[]'::jsonb,
  created_by    text not null default '',
  timestamp     timestamptz not null default now()
);

-- 5) Expenses
create table if not exists public.expenses_sync (
  id             text primary key,
  category       text not null default 'Other',
  amount         double precision not null default 0,
  description    text not null default '',
  payment_method text not null default 'Cash',
  created_by     text not null default '',
  timestamp      timestamptz not null default now()
);

-- 6) Refunds / returns
create table if not exists public.refunds_sync (
  id            text primary key,
  original_bill text not null default '',
  amount        double precision not null default 0,
  reason        text not null default '',
  refund_type   text not null default 'Cash',
  cashier       text not null default '',
  status        text not null default 'Pending',
  timestamp     timestamptz not null default now()
);

-- 7) Daily routines helper: the POS recomputes today's summary after every
-- sale and on each incremental sync, and upserts ONE row per shop day here.
-- The phone app reads this single small table instead of downloading every
-- record, which keeps Supabase free-tier egress tiny.
create table if not exists public.daily_routines (
  shop_id       text not null default 'main',
  date          date not null,
  sales_count   integer not null default 0,
  gross         double precision not null default 0,
  discount      double precision not null default 0,
  net           double precision not null default 0,
  cash_amt      double precision not null default 0,
  card_amt      double precision not null default 0,
  mixed_amt     double precision not null default 0,
  refunds_amt   double precision not null default 0,
  expenses_amt  double precision not null default 0,
  wastage_amt   double precision not null default 0,
  grn_count     integer not null default 0,
  grn_value     double precision not null default 0,
  top_products  jsonb not null default '[]'::jsonb,
  updated_at    timestamptz not null default now(),
  primary key (shop_id, date)
);

-- 8) Supplier payments (payments made to suppliers for stock)
create table if not exists public.supplier_payments_sync (
  id            text primary key,
  supplier_name text not null default '',
  amount        double precision not null default 0,
  method        text not null default '',
  cheque_number text not null default '',
  bank_name     text not null default '',
  note          text not null default '',
  timestamp     timestamptz not null default now(),
  synced_at     timestamptz not null default now()
);

-- Helpful indexes for the phone charts
create index if not exists idx_sales_timestamp on public.sales_sync (timestamp);
create index if not exists idx_grns_timestamp on public.supplier_grns_sync (timestamp);
create index if not exists idx_expenses_timestamp on public.expenses_sync (timestamp);
create index if not exists idx_refunds_timestamp on public.refunds_sync (timestamp);
create index if not exists idx_supplier_payments_timestamp on public.supplier_payments_sync (timestamp);
create index if not exists idx_daily_routines_date on public.daily_routines (date desc);

-- ===========================================================================
-- Row Level Security
-- The phone app uses the anon key (no login), so let anon users read and write.
-- For a single shop this is fine. For extra safety you can use a Supabase Edge
-- Function or the service role later.
-- ===========================================================================
alter table public.sales_sync enable row level security;
alter table public.products_snapshot enable row level security;
alter table public.customers_sync enable row level security;
alter table public.supplier_grns_sync enable row level security;
alter table public.expenses_sync enable row level security;
alter table public.refunds_sync enable row level security;
alter table public.daily_routines enable row level security;
alter table public.supplier_payments_sync enable row level security;

drop policy if exists "anon_access_sales" on public.sales_sync;
create policy "anon_access_sales" on public.sales_sync
  for all using (true) with check (true);

drop policy if exists "anon_access_products" on public.products_snapshot;
create policy "anon_access_products" on public.products_snapshot
  for all using (true) with check (true);

drop policy if exists "anon_access_customers" on public.customers_sync;
create policy "anon_access_customers" on public.customers_sync
  for all using (true) with check (true);

drop policy if exists "anon_access_grns" on public.supplier_grns_sync;
create policy "anon_access_grns" on public.supplier_grns_sync
  for all using (true) with check (true);

drop policy if exists "anon_access_expenses" on public.expenses_sync;
create policy "anon_access_expenses" on public.expenses_sync
  for all using (true) with check (true);

drop policy if exists "anon_access_refunds" on public.refunds_sync;
create policy "anon_access_refunds" on public.refunds_sync
  for all using (true) with check (true);

drop policy if exists "anon_access_routines" on public.daily_routines;
create policy "anon_access_routines" on public.daily_routines
  for all using (true) with check (true);

drop policy if exists "anon_access_supplier_payments" on public.supplier_payments_sync;
create policy "anon_access_supplier_payments" on public.supplier_payments_sync
  for all using (true) with check (true);

-- Grant public access to the anon role (default in Supabase).
grant usage on schema public to anon;
grant select, insert, update on all tables in schema public to anon;