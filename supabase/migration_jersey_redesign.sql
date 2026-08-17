-- Ball: Migration "Trikot-Neuauflage"
--
-- Bringt eine bereits laufende Datenbank (Stand: 20 Loot-Trikots, IDs 1–20)
-- auf den neuen Stand mit 28 Loot-Trikots (IDs 1–28, Verteilung 6/6/6/5/5).
--
-- Einmalig im Supabase-Dashboard unter "SQL Editor" einfügen und ausführen.
-- Bei einer frisch aufgesetzten Datenbank NICHT nötig — dort enthält
-- schema.sql die neue Liste bereits.
--
-- Bestehende Inventare bleiben unangetastet: public.inventory verweist nicht
-- per Fremdschlüssel auf jersey_weights. Wer vorher z.B. Trikot 17 besaß,
-- besitzt danach weiterhin Trikot 17 — es sieht durch das Redesign nur anders
-- aus und liegt jetzt in einer anderen Seltenheitsstufe.

begin;

delete from public.jersey_weights;

insert into public.jersey_weights (jersey_id, rarity) values
  -- Gewöhnlich (6)
  (1, 0), (2, 0), (3, 0), (4, 0), (5, 0), (6, 0),
  -- Ungewöhnlich (6)
  (7, 1), (8, 1), (9, 1), (10, 1), (11, 1), (12, 1),
  -- Selten (6)
  (13, 2), (14, 2), (15, 2), (16, 2), (17, 2), (18, 2),
  -- Episch (5)
  (19, 3), (20, 3), (21, 3), (22, 3), (23, 3),
  -- Legendär (5)
  (24, 4), (25, 4), (26, 4), (27, 4), (28, 4);

commit;

-- Kontrolle: muss 6/6/6/5/5 zeigen.
select rarity, count(*) from public.jersey_weights group by rarity order by rarity;
