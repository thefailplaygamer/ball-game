-- Ball: Cloud-Inventar-Schema für Supabase
--
-- Einmalig im Supabase-Dashboard unter "SQL Editor" komplett einfügen und
-- ausführen ("Run"). Legt Tabellen, Sicherheitsregeln und die Funktionen an,
-- über die das Spiel Kisten öffnet / Trikots ausrüstet / Kisten vergibt.
--
-- Wichtig: Alle drei "echten" Aktionen (Kiste öffnen, Trikot ausrüsten,
-- Kiste vergeben) laufen serverseitig in den Funktionen unten. Der Client
-- kann NICHT direkt in players/inventory schreiben (keine Insert/Update-
-- Policies) — nur lesen, was ihm gehört. Admin-Änderungen (Spieler Kisten/
-- Skins geben oder wegnehmen) macht man im Dashboard unter "Table Editor",
-- das läuft über die Service-Rolle und umgeht RLS automatisch.

-- ─────────────────────────────────────────────────────────────────────────
-- Tabellen
-- ─────────────────────────────────────────────────────────────────────────

create table public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  crates int not null default 5,
  equipped int not null default 0,
  award_date date not null default current_date,
  awards_today int not null default 0,
  created_at timestamptz not null default now()
);

create table public.inventory (
  player_id uuid not null references public.players (id) on delete cascade,
  jersey_id int not null,
  count int not null default 1,
  primary key (player_id, jersey_id)
);

-- Gesamt-Drop-Gewicht pro Seltenheitsstufe (0=Gewöhnlich .. 4=Legendär),
-- muss zu JerseyData.RARITY_WEIGHT in jersey_data.gd passen.
create table public.rarity_weights (
  rarity int primary key,
  total_weight numeric not null
);

insert into public.rarity_weights (rarity, total_weight) values
  (0, 40.0),
  (1, 28.0),
  (2, 18.0),
  (3, 10.0),
  (4, 4.0);

-- Welches Trikot gehört zu welcher Seltenheitsstufe. 1:1 aus JerseyData.JERSEYS
-- (nur die Einträge mit "loot": true, id 0 "Standard" ist nicht dabei).
--
-- WARTUNGSHINWEIS: Wird in jersey_data.gd ein neues Trikot zu JERSEYS
-- hinzugefügt, muss hier manuell eine passende Zeile ergänzt werden — sonst
-- kann dieses Trikot nie aus einer Kiste gezogen werden.
create table public.jersey_weights (
  jersey_id int primary key,
  rarity int not null references public.rarity_weights (rarity)
);

insert into public.jersey_weights (jersey_id, rarity) values
  (1, 0), (2, 0), (3, 0), (4, 0),
  (5, 1), (6, 1), (7, 1), (8, 1),
  (9, 2), (10, 2), (11, 2), (12, 2),
  (13, 3), (14, 3), (15, 3), (16, 3),
  (17, 4), (18, 4), (19, 4), (20, 4);

-- ─────────────────────────────────────────────────────────────────────────
-- Neuen Account automatisch anlegen (players-Zeile + Standard-Trikot)
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.players (id, username)
    values (new.id, new.raw_user_meta_data ->> 'username');
  insert into public.inventory (player_id, jersey_id, count)
    values (new.id, 0, 1);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────────────────
-- Row Level Security: jeder darf nur seine eigene Zeile lesen, schreiben
-- geht nur über die Funktionen unten (security definer, laufen mit erhöhten
-- Rechten, prüfen aber genau was erlaubt ist).
-- ─────────────────────────────────────────────────────────────────────────

alter table public.players enable row level security;
alter table public.inventory enable row level security;
alter table public.rarity_weights enable row level security;
alter table public.jersey_weights enable row level security;

create policy "players read own row" on public.players
  for select using (auth.uid() = id);

create policy "inventory read own rows" on public.inventory
  for select using (auth.uid() = player_id);

-- Referenztabellen sind reine Balance-Daten, unkritisch lesbar.
create policy "rarity_weights read" on public.rarity_weights
  for select using (true);

create policy "jersey_weights read" on public.jersey_weights
  for select using (true);

grant select on public.players to authenticated;
grant select on public.inventory to authenticated;
grant select on public.rarity_weights to authenticated;
grant select on public.jersey_weights to authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- open_crate(): zieht eine Kiste ab, würfelt serverseitig gewichtet nach
-- Seltenheit (Efraimidis-Spirakis gewichtetes Sampling: pro Trikot einen
-- Schlüssel -ln(random())/Gewicht ziehen, kleinster Schlüssel gewinnt —
-- entspricht exakt der gleichen Gewichtsverteilung wie zuvor client-seitig
-- in _weighted_roll()), erhöht den Dubletten-Zähler im Inventar.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.open_crate()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_crates int;
  v_new_crates int;
  won_id int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select crates into v_crates from public.players where id = uid for update;
  if v_crates is null then
    raise exception 'player not found';
  end if;
  if v_crates <= 0 then
    raise exception 'no crates available';
  end if;

  update public.players set crates = crates - 1 where id = uid
    returning crates into v_new_crates;

  with weighted as (
    select jw.jersey_id,
           rw.total_weight / count(*) over (partition by jw.rarity) as item_weight
    from public.jersey_weights jw
    join public.rarity_weights rw on rw.rarity = jw.rarity
  )
  select jersey_id into won_id
  from weighted
  order by -ln(random()) / item_weight
  limit 1;

  insert into public.inventory (player_id, jersey_id, count)
    values (uid, won_id, 1)
    on conflict (player_id, jersey_id) do update set count = public.inventory.count + 1;

  return jsonb_build_object('jersey_id', won_id, 'crates', v_new_crates);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- award_crate(): serverseitige Version von Inventory.add_crate() — prüft
-- das Tageslimit (5/Tag) anhand des heutigen Datums auf dem Server, nicht
-- auf dem potenziell manipulierbaren Client.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.award_crate()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_award_date date;
  v_awards_today int;
  today date := current_date;
  awarded boolean := false;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select award_date, awards_today into v_award_date, v_awards_today
    from public.players where id = uid for update;

  if v_award_date is distinct from today then
    v_awards_today := 0;
  end if;

  if v_awards_today < 5 then
    update public.players
      set crates = crates + 1, award_date = today, awards_today = v_awards_today + 1
      where id = uid;
    awarded := true;
  else
    update public.players
      set award_date = today, awards_today = v_awards_today
      where id = uid;
  end if;

  return awarded;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- equip_jersey(): prüft Besitz bevor ausgerüstet wird, damit niemand ein
-- fremdes/nicht besessenes Trikot per direktem API-Aufruf ausrüsten kann.
-- ─────────────────────────────────────────────────────────────────────────

create or replace function public.equip_jersey(p_jersey_id int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  owned_count int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  select count into owned_count
    from public.inventory where player_id = uid and jersey_id = p_jersey_id;

  if owned_count is null or owned_count <= 0 then
    return false;
  end if;

  update public.players set equipped = p_jersey_id where id = uid;
  return true;
end;
$$;

-- Nur eingeloggte Nutzer dürfen diese Funktionen aufrufen (nicht "anon").
revoke all on function public.open_crate() from public;
revoke all on function public.award_crate() from public;
revoke all on function public.equip_jersey(int) from public;

grant execute on function public.open_crate() to authenticated;
grant execute on function public.award_crate() to authenticated;
grant execute on function public.equip_jersey(int) to authenticated;
