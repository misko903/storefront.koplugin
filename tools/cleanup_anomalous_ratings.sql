-- Storefront Ratings & Downloads Cleanup Script
-- Resets anomalous / spammed vote counts and downloads to verified historical baselines.
-- Run via: npx wrangler d1 execute DB --file=tools/cleanup_anomalous_ratings.sql
-- Or via Cloudflare Dashboard D1 Console for storefront-db.

-- 1. Purge automated spammed votes for target repos
DELETE FROM votes WHERE repo_id IN ('1102096716', '1033827759', '1304319884');

-- 2. Reset ratings table to realistic historical values
INSERT INTO ratings (repo_id, up, down, wilson) VALUES
  ('1304319884', 65, 0, 0.945),
  ('1102096716', 6, 0, 0.610),
  ('1033827759', 8, 0, 0.676)
ON CONFLICT(repo_id) DO UPDATE SET
  up = excluded.up,
  down = excluded.down,
  wilson = excluded.wilson;

-- 3. Reset downloads to verified baselines
UPDATE downloads SET count = 0 WHERE repo_id IN ('1102096716', '1033827759');
UPDATE downloads SET count = 120 WHERE repo_id = '1304319884';
