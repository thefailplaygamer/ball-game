-- Ball: Entwickler-Hilfe "Alle Trikots freischalten"
--
-- Gibt einem Spieler jedes existierende Trikot, um die Designs durchzutesten.
-- Im Supabase-Dashboard unter "SQL Editor" ausführen — läuft dort über die
-- Service-Rolle und umgeht damit RLS, deshalb ist kein Login nötig.
--
-- Vor dem Ausführen: unten in ALLEN Blöcken 'DEIN_NAME' durch den eigenen
-- Benutzernamen ersetzen (genau so geschrieben wie beim Registrieren).

-- ─────────────────────────────────────────────────────────────────────────
-- 1) Alle Trikots geben
-- ─────────────────────────────────────────────────────────────────────────
--
-- Die Liste kommt aus jersey_weights statt aus einer fest getippten Zahlen-
-- reihe: kommen später neue Trikots dazu, funktioniert dasselbe Skript ohne
-- Änderung weiter. id 0 (Standard) steht nicht in jersey_weights und wird
-- deshalb separat ergänzt.
--
-- "do nothing" bei Konflikt: bereits besessene Trikots behalten ihre
-- Dubletten-Anzahl, es wird nichts überschrieben.

insert into public.inventory (player_id, jersey_id, count)
select p.id, j.jersey_id, 1
from public.players p
cross join (
  select 0 as jersey_id
  union all
  select jersey_id from public.jersey_weights
) j
where p.username = 'DEIN_NAME'
on conflict (player_id, jersey_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) Kontrolle: sollte 29 Zeilen zeigen (Standard + 28 Loot-Trikots)
-- ─────────────────────────────────────────────────────────────────────────

select i.jersey_id, i.count
from public.inventory i
join public.players p on p.id = i.player_id
where p.username = 'DEIN_NAME'
order by i.jersey_id;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) Optional: Kisten auffüllen, um zusätzlich das Öffnen zu testen
-- ─────────────────────────────────────────────────────────────────────────
-- Das Tageslimit (5 Kisten/Tag) gilt nur für award_crate(); direkt gesetzte
-- Kisten umgehen es.

-- update public.players set crates = 25 where username = 'DEIN_NAME';

-- ─────────────────────────────────────────────────────────────────────────
-- 4) Optional: nach dem Testen wieder zurücksetzen
-- ─────────────────────────────────────────────────────────────────────────
-- Löscht alles außer dem Standard-Trikot. Wichtig ist das "equipped"-Update:
-- sonst zeigt der Account weiter auf ein Trikot, das er nicht mehr besitzt.

-- update public.players set equipped = 0 where username = 'DEIN_NAME';
--
-- delete from public.inventory
-- where jersey_id <> 0
--   and player_id = (select id from public.players where username = 'DEIN_NAME');
