\echo === 1. Byte-level check: is the dash in ActinomycinD corrupt or valid UTF-8? ===
SELECT inn_name,
       convert_to(inn_name, 'UTF8')::text AS utf8_bytes
FROM drug WHERE id::text LIKE '60d22dea%';

\echo === 2. How widespread are non-ASCII chars in inn_name across ALL drugs? ===
SELECT count(*) AS rows_with_non_ascii
FROM drug WHERE inn_name ~ '[^[:ascii:]]';

\echo === 3. Sample of those non-ASCII names (first 25) ===
SELECT substr(id::text,1,8) AS id, inn_name
FROM drug WHERE inn_name ~ '[^[:ascii:]]'
ORDER BY inn_name LIMIT 25;

\echo === 4. Naming-convention shapes among ALL drugs (how many use each form) ===
SELECT
  count(*) FILTER (WHERE inn_name LIKE '%/%')                    AS has_slash,
  count(*) FILTER (WHERE inn_name LIKE '%(%')                    AS has_paren,
  count(*) FILTER (WHERE inn_name LIKE '%/%' AND inn_name LIKE '%(%') AS has_both,
  count(*)                                                       AS total
FROM drug;
