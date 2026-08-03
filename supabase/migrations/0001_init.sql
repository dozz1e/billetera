create table accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  tipo text not null check (tipo in ('efectivo', 'banco', 'credito', 'billetera_digital')),
  saldo_inicial numeric not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now()
);

create table categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  tipo text not null check (tipo in ('ingreso', 'gasto')),
  icono text not null default 'category',
  predefinida boolean not null default false
);

create table transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete restrict,
  category_id uuid references categories(id) on delete restrict,
  account_destino_id uuid references accounts(id) on delete restrict,
  tipo text not null check (tipo in ('ingreso', 'gasto', 'transferencia')),
  monto numeric not null check (monto > 0),
  fecha date not null,
  nota text,
  created_at timestamptz not null default now(),
  constraint transferencia_shape check (
    (tipo = 'transferencia' and account_destino_id is not null and category_id is null and account_destino_id <> account_id)
    or
    (tipo in ('ingreso', 'gasto') and category_id is not null and account_destino_id is null)
  )
);

create index transactions_user_fecha_idx on transactions(user_id, fecha);
create index transactions_user_account_idx on transactions(user_id, account_id);
create index transactions_user_category_idx on transactions(user_id, category_id);

create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null references categories(id) on delete cascade,
  mes date not null,
  monto_limite numeric not null check (monto_limite > 0),
  unique (user_id, category_id, mes)
);

create index budgets_user_mes_idx on budgets(user_id, mes);

-- RLS

alter table accounts enable row level security;
alter table categories enable row level security;
alter table transactions enable row level security;
alter table budgets enable row level security;

create policy "accounts_owner" on accounts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "categories_owner" on categories
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "transactions_owner" on transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "budgets_owner" on budgets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Seed predefined categories for every new user

create or replace function public.seed_default_categories()
returns trigger as $$
begin
  insert into public.categories (user_id, nombre, tipo, icono, predefinida) values
    (new.id, 'Comida', 'gasto', 'restaurant', true),
    (new.id, 'Transporte', 'gasto', 'directions_car', true),
    (new.id, 'Vivienda', 'gasto', 'home', true),
    (new.id, 'Salud', 'gasto', 'local_hospital', true),
    (new.id, 'Entretenimiento', 'gasto', 'movie', true),
    (new.id, 'Otros gastos', 'gasto', 'category', true),
    (new.id, 'Sueldo', 'ingreso', 'work', true),
    (new.id, 'Otros ingresos', 'ingreso', 'attach_money', true);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.seed_default_categories();
