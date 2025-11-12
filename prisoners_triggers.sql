-- PostgreSQL triggers and functions for automatic prisoner numbering
-- and maintaining a global prisoner_count in app_stats

BEGIN;

-- Ensure stats table exists
CREATE TABLE IF NOT EXISTS app_stats (
  name  TEXT PRIMARY KEY,
  value INTEGER NOT NULL DEFAULT 0
);

-- Drop existing triggers and functions if present
DROP TRIGGER IF EXISTS trg_prisoner_before_insert_display_no ON prisoners;
DROP TRIGGER IF EXISTS trg_prisoner_after_insert_inc_count ON prisoners;
DROP TRIGGER IF EXISTS trg_prisoner_after_delete_renumber ON prisoners;

DROP FUNCTION IF EXISTS fn_prisoner_before_insert();
DROP FUNCTION IF EXISTS fn_prisoner_after_insert_inc_count();
DROP FUNCTION IF EXISTS fn_prisoner_after_delete_renumber();

-- BEFORE INSERT: set display_no to MAX(display_no)+1 when not provided
CREATE OR REPLACE FUNCTION fn_prisoner_before_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.display_no IS NULL THEN
    SELECT COALESCE(MAX(display_no), 0) + 1
      INTO NEW.display_no
      FROM prisoners;
  END IF;
  RETURN NEW; -- BEFORE triggers must return NEW
END;
$$;

CREATE TRIGGER trg_prisoner_before_insert_display_no
BEFORE INSERT ON prisoners
FOR EACH ROW
EXECUTE FUNCTION fn_prisoner_before_insert();

-- AFTER INSERT: increment prisoner_count in app_stats (upsert)
CREATE OR REPLACE FUNCTION fn_prisoner_after_insert_inc_count()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO app_stats(name, value)
  VALUES ('prisoner_count', 1)
  ON CONFLICT(name) DO UPDATE
    SET value = app_stats.value + 1;

  RETURN NULL; -- AFTER triggers may return NULL
END;
$$;

CREATE TRIGGER trg_prisoner_after_insert_inc_count
AFTER INSERT ON prisoners
FOR EACH ROW
EXECUTE FUNCTION fn_prisoner_after_insert_inc_count();

-- AFTER DELETE: decrement prisoner_count and renumber display_no
CREATE OR REPLACE FUNCTION fn_prisoner_after_delete_renumber()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Decrement counter but not below 0
  INSERT INTO app_stats(name, value)
  VALUES ('prisoner_count', 0)
  ON CONFLICT(name) DO UPDATE
    SET value = GREATEST(app_stats.value - 1, 0);

  -- Shift down display_no for prisoners after the deleted one
  IF OLD.display_no IS NOT NULL THEN
    UPDATE prisoners
       SET display_no = display_no - 1
     WHERE display_no > OLD.display_no;
  END IF;

  RETURN NULL; -- AFTER triggers may return NULL
END;
$$;

CREATE TRIGGER trg_prisoner_after_delete_renumber
AFTER DELETE ON prisoners
FOR EACH ROW
EXECUTE FUNCTION fn_prisoner_after_delete_renumber();

COMMIT;

