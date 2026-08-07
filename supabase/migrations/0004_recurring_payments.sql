create table recurring_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete restrict,
  category_id uuid not null references categories(id) on delete restrict,
  monto numeric not null check (monto > 0),
  dia_mes integer not null check (dia_mes between 1 and 31),
  nota text,
  fecha_inicio date not null,
  ultima_generada date,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create index recurring_payments_user_activo_idx on recurring_payments(user_id, activo);

alter table recurring_payments enable row level security;

create policy "recurring_payments_owner" on recurring_payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

alter table transactions
  add column recurring_payment_id uuid references recurring_payments(id) on delete set null;
