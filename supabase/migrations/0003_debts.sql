create table people (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nombre text not null,
  created_at timestamptz not null default now()
);

create table debts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  person_id uuid not null references people(id) on delete cascade,
  motivo text not null,
  monto numeric not null check (monto > 0),
  fecha date not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'pagada')),
  created_at timestamptz not null default now()
);

create index debts_user_person_idx on debts(user_id, person_id);
create index debts_user_estado_idx on debts(user_id, estado);

alter table people enable row level security;
alter table debts enable row level security;

create policy "people_owner" on people
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "debts_owner" on debts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
