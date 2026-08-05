create table goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  account_id uuid not null references accounts(id) on delete cascade,
  monto_objetivo numeric not null check (monto_objetivo > 0),
  fecha_objetivo date not null,
  estado text not null default 'activo' check (estado in ('activo', 'pausado', 'alcanzado')),
  created_at timestamptz not null default now()
);

create index goals_user_estado_idx on goals(user_id, estado);

alter table goals enable row level security;

create policy "goals_owner" on goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
