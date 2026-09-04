-- ZenSched Merchandising-Audit Local Database Schema
-- SQLite database for clients (CPG brands / brokers), merchandising
-- programs, the store cache, the merchandiser pool, individual store
-- visits and shelf-audit results, QA, client invoicing, and merchandiser
-- pay runs.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, the
-- original form submissions and bay photos).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my merch-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 merch-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.
--
-- WHAT CROSSES TO ZENSCHED AND WHAT DOES NOT
--   ZenSched receives: a store label (banner + street, e.g. 'Walmart - US Hwy
--   290'), the store's street address for the GPS pin, an event title per
--   store per wave (the CPG brand name may appear: merchandisers must know
--   which bay they are auditing), the shelf-audit form, and the merchandiser's
--   account (name + email).
--   ZenSched never receives: the broker/client contact details, fees,
--   merchandiser pay handles, QA notes, or scores. Those live only here.
--   SKILL.md makes this a hard rule.
--
-- TIME CONVENTIONS
--   visits.scheduled_start / scheduled_end are STORE-LOCAL wall-clock times
--   without an offset ('2026-09-10T09:00:00'). Views append the store's
--   tz_offset to build the ISO strings shift_create needs, so a multi-region
--   program comes out right without the agent doing timezone arithmetic.
--   visits.checkin_at / checkout_at are ISO 8601 WITH an explicit offset, as
--   recorded from ZenSched (any offset is fine; SQLite normalizes to UTC when
--   comparing).

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session.
-- timezone_offset is the DEFAULT for new stores; each store carries its own
-- tz_offset because programs often span time zones.
-- default_checkin_radius_m is informational: the radius ZenSched enforces is
-- the account POLICY's, set with policy_update(0, {"checkin_radius_m": N}).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Merchandising Agency');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '30');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_visit_minutes', '25');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_checkin_radius_m', '150');

-- Clients: the CPG brands or retail brokers that buy store visits from the
-- agency. LOCAL ONLY. Nothing from this table is ever sent to ZenSched.
CREATE TABLE IF NOT EXISTS clients (
  client_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_name TEXT NOT NULL,
  contact_name TEXT,
  contact_email TEXT,
  contact_phone TEXT,
  billing_email TEXT,
  payment_terms_days INTEGER DEFAULT 30,
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Programs: one WAVE of store visits for one client. A program says which
-- stores, which questionnaire (its own ZenSched form), when (wave dates,
-- daily window, allowed weekdays), how many visits per store, and the money
-- (client fee, merchandiser fee). A quarter-long engagement is several
-- program rows, one per wave, because a ZenSched event is capped at 60 days
-- and the kit creates one event per store per wave (the CHECK below enforces
-- the split). allowed_weekdays is a 7-character 0/1 mask, Monday first:
-- '1111100' = weekdays only.
CREATE TABLE IF NOT EXISTS programs (
  program_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  program_name TEXT NOT NULL,                       -- 'Frito Bay Audit - Sep'
  wave_start TEXT NOT NULL,                         -- ISO date
  wave_end TEXT NOT NULL                            -- ISO date, at most 59 days after wave_start
    CHECK (wave_end >= wave_start AND julianday(wave_end) - julianday(wave_start) <= 59),
  window_start_time TEXT NOT NULL DEFAULT '08:00'   -- earliest local time a visit may start
    CHECK (window_start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  window_end_time TEXT NOT NULL DEFAULT '18:00'     -- latest local time a visit may END
    CHECK (window_end_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  allowed_weekdays TEXT NOT NULL DEFAULT '1111100'
    CHECK (length(allowed_weekdays) = 7 AND allowed_weekdays NOT GLOB '*[^01]*'),
  quota_per_store INTEGER NOT NULL DEFAULT 1 CHECK (quota_per_store >= 1),
  client_fee REAL NOT NULL,                         -- what the client pays per approved visit
  merchandiser_fee REAL NOT NULL,                   -- what the merchandiser earns per approved visit
  min_minutes INTEGER DEFAULT 8,                    -- visits shorter than this are flagged
  zensched_form_id INTEGER,                         -- from form_create (one form per program)
  questionnaire_notes TEXT,                         -- the client's brief: SKUs, planogram, what to photograph
  merchandiser_brief TEXT,                          -- the ONLY text about this program a merchandiser may be told
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'active', 'closed')),
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE
);

-- Stores: the cache of physical locations, one ZenSched LOCATION each, created
-- once and kept forever (geocoding is metered). Keyed by client + normalized
-- address so the same store pasted in two CSVs is one row and one geocode.
-- tz_offset is PER STORE: a national program has stores in several zones.
-- store_label is the only name that crosses to ZenSched ('Walmart - US Hwy 290').
CREATE TABLE IF NOT EXISTS stores (
  store_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  banner TEXT NOT NULL,                             -- 'Walmart', 'Target', 'HEB'
  store_code TEXT,                                  -- the client's / retailer's own store number
  address TEXT NOT NULL,                            -- as the client wrote it
  city TEXT,
  region TEXT,                                      -- state / province
  country TEXT DEFAULT 'US',
  postal TEXT,
  normalized_address TEXT NOT NULL,                 -- see SKILL.md "Normalize an address"
  tz_offset TEXT NOT NULL                           -- '-05:00'; defaults to settings.timezone_offset unless the agent knows better
    CHECK (tz_offset GLOB '[+-][0-1][0-9]:[0-5][0-9]'),
  store_label TEXT,                                 -- name sent to ZenSched: banner + street
  zensched_location_id INTEGER,                     -- from location_create (permanent)
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- 'chip aisle endcap', 'store-in-store kiosk'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  UNIQUE (client_id, normalized_address)
);

-- Program x store: which stores are in this wave, how many visits each needs,
-- and the ZenSched EVENT for that store for this wave (start_date = wave_start,
-- end_date = wave_end, never more than 60 days). The program's form is
-- assigned to the event so it installs on the merchandiser's phone at shift_create.
CREATE TABLE IF NOT EXISTS program_stores (
  program_store_id INTEGER PRIMARY KEY AUTOINCREMENT,
  program_id INTEGER NOT NULL,
  store_id INTEGER NOT NULL,
  visits_required INTEGER NOT NULL DEFAULT 1 CHECK (visits_required >= 0),
  zensched_event_id INTEGER,                        -- from event_create
  event_valid_until TEXT,                           -- ISO date: last day the event covers (= wave_end)
  is_active INTEGER DEFAULT 1,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE CASCADE,
  FOREIGN KEY (store_id) REFERENCES stores(store_id) ON DELETE CASCADE,
  UNIQUE (program_id, store_id)
);

-- Merchandisers: the independent-contractor pool. zensched_worker_id comes
-- from worker_invite. pay_handle (PayPal email, Venmo, bank nickname) is
-- LOCAL ONLY. Reliability is derived from visits (see merchandiser_reliability).
CREATE TABLE IF NOT EXISTS merchandisers (
  merchandiser_id INTEGER PRIMARY KEY AUTOINCREMENT,
  merchandiser_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT,
  home_city TEXT,
  home_region TEXT,
  zensched_worker_id INTEGER UNIQUE,                -- from worker_invite
  pay_handle TEXT,                                  -- LOCAL ONLY: how you pay them
  is_active INTEGER DEFAULT 1,
  notes TEXT,                                       -- 'has car', 'warehouse badge', 'speaks Spanish'
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Visits: one row per store visit the program requires. Created 'open' from
-- the quota, becomes 'assigned' when a merchandiser and a date/time slot are
-- chosen (one ZenSched shift), then 'completed' / 'no_show' / 'rejected' /
-- 'cancelled'. scheduled_* are store-local wall-clock ('YYYY-MM-DDTHH:MM:SS',
-- no offset); checkin_at / checkout_at are ISO with offset as recorded from
-- ZenSched. duration_minutes is filled by trigger from the punches when left
-- NULL. score is computed locally by the agent from question_weights (optional).
CREATE TABLE IF NOT EXISTS visits (
  visit_id INTEGER PRIMARY KEY AUTOINCREMENT,
  program_store_id INTEGER NOT NULL,
  merchandiser_id INTEGER,                          -- NULL until assigned
  scheduled_start TEXT                              -- store-local, no offset
    CHECK (scheduled_start IS NULL OR scheduled_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  scheduled_end TEXT
    CHECK (scheduled_end IS NULL OR scheduled_end GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]'),
  zensched_shift_id INTEGER UNIQUE,                 -- from shift_create
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'assigned', 'completed', 'no_show', 'rejected', 'cancelled')),
  submission_dc_id INTEGER,                         -- form submission_id
  checkin_at TEXT,                                  -- ISO with offset, from shift_status
  checkout_at TEXT,
  duration_minutes INTEGER,                         -- trigger fills from punches if NULL
  score REAL,                                       -- 0-100, agent-computed from question_weights
  qa_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (qa_status IN ('pending', 'approved', 'rejected')),
  qa_notes TEXT,                                    -- LOCAL ONLY
  client_invoiced INTEGER DEFAULT 0,
  merchandiser_paid INTEGER DEFAULT 0,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (program_store_id) REFERENCES program_stores(program_store_id) ON DELETE CASCADE,
  FOREIGN KEY (merchandiser_id) REFERENCES merchandisers(merchandiser_id) ON DELETE SET NULL
);

-- Question weights (optional): lets the agent turn a submission into a 0-100
-- score without a scoring engine. One row per scored question: the form
-- identifier, its weight, the expected value (an OPTION KEY for select fields,
-- e.g. 'none', 'yes', or a number as text), and how to compare. Score =
-- 100 * SUM(weight of questions that pass) / SUM(weight). Questions absent
-- from this table are informational only.
CREATE TABLE IF NOT EXISTS question_weights (
  weight_id INTEGER PRIMARY KEY AUTOINCREMENT,
  program_id INTEGER NOT NULL,
  identifier TEXT NOT NULL,                         -- form field identifier, e.g. 'oos'
  weight REAL NOT NULL DEFAULT 1 CHECK (weight > 0),
  expected_value TEXT,                              -- option key or number as text
  match_rule TEXT NOT NULL DEFAULT 'equals'
    CHECK (match_rule IN ('equals', 'not_equals', 'gte', 'lte', 'contains', 'not_contains')),
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE CASCADE,
  UNIQUE (program_id, identifier)
);

-- Invoices to clients. invoice_number is filled by trigger if left NULL.
-- line_items is a JSON array with one object per visit.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id INTEGER NOT NULL,
  program_id INTEGER,                               -- NULL when one invoice spans programs
  invoice_number TEXT UNIQUE,                       -- 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  visit_count INTEGER,
  fees_amount REAL,                                 -- SUM(client_fee)
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  sent_date TEXT,
  line_items TEXT,                                  -- JSON array: one object per visit
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE,
  FOREIGN KEY (program_id) REFERENCES programs(program_id) ON DELETE SET NULL
);

-- Merchandiser payouts: one row per merchandiser per pay run. The agency
-- pays outside the kit (PayPal, Venmo, bank); this is the record.
-- visit_ids is a JSON array.
CREATE TABLE IF NOT EXISTS merchandiser_payouts (
  payout_id INTEGER PRIMARY KEY AUTOINCREMENT,
  merchandiser_id INTEGER NOT NULL,
  period_start TEXT,
  period_end TEXT,
  visit_count INTEGER,
  fees_amount REAL,                                 -- SUM(merchandiser_fee)
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,
  paid_date TEXT,
  visit_ids TEXT,                                   -- JSON array of visit_id
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (merchandiser_id) REFERENCES merchandisers(merchandiser_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_programs_client ON programs(client_id, status);
CREATE INDEX IF NOT EXISTS idx_stores_client ON stores(client_id);
CREATE INDEX IF NOT EXISTS idx_stores_zensched_location ON stores(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_program_stores_program ON program_stores(program_id);
CREATE INDEX IF NOT EXISTS idx_program_stores_store ON program_stores(store_id);
CREATE INDEX IF NOT EXISTS idx_program_stores_event ON program_stores(zensched_event_id);
CREATE INDEX IF NOT EXISTS idx_visits_program_store ON visits(program_store_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_merchandiser ON visits(merchandiser_id, status);
CREATE INDEX IF NOT EXISTS idx_visits_scheduled ON visits(scheduled_start);
CREATE INDEX IF NOT EXISTS idx_visits_qa ON visits(qa_status, client_invoiced, merchandiser_paid);
CREATE INDEX IF NOT EXISTS idx_invoices_client ON invoices(client_id, paid);
CREATE INDEX IF NOT EXISTS idx_payouts_merchandiser ON merchandiser_payouts(merchandiser_id, paid);

-- Keep updated_at current
CREATE TRIGGER IF NOT EXISTS update_client_timestamp
AFTER UPDATE ON clients
BEGIN
  UPDATE clients SET updated_at = datetime('now') WHERE client_id = NEW.client_id;
END;

CREATE TRIGGER IF NOT EXISTS update_program_timestamp
AFTER UPDATE ON programs
BEGIN
  UPDATE programs SET updated_at = datetime('now') WHERE program_id = NEW.program_id;
END;

CREATE TRIGGER IF NOT EXISTS update_store_timestamp
AFTER UPDATE ON stores
BEGIN
  UPDATE stores SET updated_at = datetime('now') WHERE store_id = NEW.store_id;
END;

CREATE TRIGGER IF NOT EXISTS update_merchandiser_timestamp
AFTER UPDATE ON merchandisers
BEGIN
  UPDATE merchandisers SET updated_at = datetime('now') WHERE merchandiser_id = NEW.merchandiser_id;
END;

CREATE TRIGGER IF NOT EXISTS update_visit_timestamp
AFTER UPDATE ON visits
BEGIN
  UPDATE visits SET updated_at = datetime('now') WHERE visit_id = NEW.visit_id;
END;

-- Fill duration_minutes from the punches when the agent leaves it NULL, on
-- insert and whenever the punch columns change. Both stamps carry an offset,
-- so julianday arithmetic is exact even across midnight or time zones.
CREATE TRIGGER IF NOT EXISTS fill_visit_duration_insert
AFTER INSERT ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

CREATE TRIGGER IF NOT EXISTS fill_visit_duration_update
AFTER UPDATE OF checkin_at, checkout_at ON visits
WHEN NEW.duration_minutes IS NULL AND NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL
BEGIN
  UPDATE visits
  SET duration_minutes = CAST(round((julianday(NEW.checkout_at) - julianday(NEW.checkin_at)) * 1440.0) AS INTEGER)
  WHERE visit_id = NEW.visit_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Unassigned visits in active programs, with everything the agent needs to
-- propose an assignment: store, city, tz, the daily window, allowed weekdays,
-- and how many days remain in the wave. Sorted by urgency.
CREATE VIEW IF NOT EXISTS visits_open AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  st.store_id,
  st.banner,
  st.store_code,
  st.address,
  st.city,
  st.region,
  st.tz_offset,
  st.store_label,
  st.zensched_location_id,
  ps.program_store_id,
  ps.zensched_event_id,
  p.wave_start,
  p.wave_end,
  p.window_start_time,
  p.window_end_time,
  p.allowed_weekdays,
  p.min_minutes,
  p.merchandiser_fee,
  p.merchandiser_brief,
  CAST(julianday(p.wave_end) - julianday(date('now')) AS INTEGER) AS days_until_wave_end
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN stores st         ON st.store_id = ps.store_id
JOIN clients c         ON c.client_id = p.client_id
WHERE v.status = 'open'
  AND p.status = 'active'
  AND ps.is_active = 1
ORDER BY p.wave_end, st.city, st.banner;

-- Assigned visits in the next 7 days (today + 6, by store-local date). One
-- row = one shift_create call (if zensched_shift_id is NULL) or one shift to
-- watch. start_iso / end_iso use the STORE's tz_offset. needs_location /
-- needs_event mean the store or the program-store row has not been set up on
-- ZenSched yet.
CREATE VIEW IF NOT EXISTS visits_upcoming AS
SELECT
  v.visit_id,
  v.status,
  p.program_id,
  p.program_name,
  c.client_name,
  st.store_id,
  st.banner,
  st.address,
  st.city,
  st.tz_offset,
  st.store_label,
  st.zensched_location_id,
  ps.program_store_id,
  ps.zensched_event_id,
  ps.event_valid_until,
  m.merchandiser_id,
  m.merchandiser_name,
  m.zensched_worker_id                               AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.scheduled_start || st.tz_offset                  AS start_iso,
  v.scheduled_end   || st.tz_offset                  AS end_iso,
  'shift-visit-' || v.visit_id                       AS idempotency_key,
  v.zensched_shift_id,
  CASE WHEN st.zensched_location_id IS NULL THEN 1 ELSE 0 END AS needs_location,
  CASE WHEN ps.zensched_event_id IS NULL
         OR ps.event_valid_until IS NULL
         OR ps.event_valid_until < date(v.scheduled_start) THEN 1 ELSE 0 END AS needs_event,
  p.merchandiser_brief
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN stores st         ON st.store_id = ps.store_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN merchandisers m ON m.merchandiser_id = v.merchandiser_id
WHERE v.status = 'assigned'
  AND date(v.scheduled_start) BETWEEN date('now') AND date('now', '+6 days')
ORDER BY v.scheduled_start, st.city;

-- Assigned visits whose slot has already ended (store-local, compared in UTC)
-- with no result recorded. Either the merchandiser did it and results have
-- not been pulled, or it is a no-show.
CREATE VIEW IF NOT EXISTS visits_overdue AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  st.banner,
  st.address,
  st.city,
  st.tz_offset,
  ps.zensched_event_id,
  m.merchandiser_id,
  m.merchandiser_name,
  m.zensched_worker_id                               AS worker_id,
  v.scheduled_start,
  v.scheduled_end,
  v.zensched_shift_id,
  CAST((julianday('now') - julianday(v.scheduled_end || st.tz_offset)) * 24 AS INTEGER) AS hours_overdue
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN stores st         ON st.store_id = ps.store_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN merchandisers m ON m.merchandiser_id = v.merchandiser_id
WHERE v.status = 'assigned'
  AND v.scheduled_end IS NOT NULL
  AND julianday(v.scheduled_end || st.tz_offset) < julianday('now')
ORDER BY v.scheduled_end;

-- Completed visits with a quality signal, for QA to look at first:
--   checkin_late     check-in after the assigned slot ended
--   checkin_early    check-in more than 15 minutes before the slot started
--   no_checkin       completed (form in) but no GPS check-in recorded
--   short_visit      duration below the program's min_minutes
-- On-time visits with a normal duration do not appear here. The kit's
-- headline flags are late and short; early and no-punch are kept so a
-- drive-by photo from the parking lot still surfaces.
CREATE VIEW IF NOT EXISTS visits_flagged AS
SELECT
  v.visit_id,
  p.program_id,
  p.program_name,
  c.client_name,
  st.banner,
  st.address,
  st.city,
  st.tz_offset,
  m.merchandiser_id,
  m.merchandiser_name,
  v.scheduled_start,
  v.scheduled_end,
  v.checkin_at,
  v.checkout_at,
  v.duration_minutes,
  p.min_minutes,
  v.submission_dc_id,
  v.zensched_shift_id,
  v.qa_status,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) > julianday(v.scheduled_end || st.tz_offset) THEN 1 ELSE 0 END AS checkin_late,
  CASE WHEN v.checkin_at IS NOT NULL
        AND julianday(v.checkin_at) < julianday(v.scheduled_start || st.tz_offset, '-15 minutes') THEN 1 ELSE 0 END AS checkin_early,
  CASE WHEN v.checkin_at IS NULL THEN 1 ELSE 0 END AS no_checkin,
  CASE WHEN v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(p.min_minutes, 0) THEN 1 ELSE 0 END AS short_visit,
  CAST(round((julianday(v.checkin_at) - julianday(v.scheduled_end || st.tz_offset)) * 1440.0) AS INTEGER) AS minutes_after_slot_end
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN stores st         ON st.store_id = ps.store_id
JOIN clients c         ON c.client_id = p.client_id
LEFT JOIN merchandisers m ON m.merchandiser_id = v.merchandiser_id
WHERE v.status = 'completed'
  AND (
       v.checkin_at IS NULL
    OR julianday(v.checkin_at) > julianday(v.scheduled_end || st.tz_offset)
    OR julianday(v.checkin_at) < julianday(v.scheduled_start || st.tz_offset, '-15 minutes')
    OR (v.duration_minutes IS NOT NULL AND v.duration_minutes < COALESCE(p.min_minutes, 0))
  )
ORDER BY CASE v.qa_status WHEN 'pending' THEN 0 ELSE 1 END, v.scheduled_start;

-- One row per program: how many visits are required, assigned, completed,
-- approved, percent complete (approved / required), and days left in the wave.
CREATE VIEW IF NOT EXISTS program_progress AS
SELECT
  p.program_id,
  p.program_name,
  c.client_name,
  p.status,
  p.wave_start,
  p.wave_end,
  CAST(julianday(p.wave_end) - julianday(date('now')) AS INTEGER)            AS days_left,
  (SELECT COUNT(*) FROM program_stores ps WHERE ps.program_id = p.program_id AND ps.is_active = 1) AS store_count,
  (SELECT COALESCE(SUM(ps.visits_required), 0) FROM program_stores ps WHERE ps.program_id = p.program_id AND ps.is_active = 1) AS visits_required,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'open')               AS visits_open,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'assigned')           AS visits_assigned,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'completed')          AS visits_completed,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'approved') AS visits_approved,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'no_show')            AS visits_no_show,
  (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
     WHERE ps.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'pending') AS visits_qa_pending,
  CASE WHEN (SELECT COALESCE(SUM(ps.visits_required), 0) FROM program_stores ps WHERE ps.program_id = p.program_id AND ps.is_active = 1) = 0 THEN 0
       ELSE round(100.0 *
            (SELECT COUNT(*) FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
               WHERE ps.program_id = p.program_id AND v.status = 'completed' AND v.qa_status = 'approved')
            / (SELECT SUM(ps.visits_required) FROM program_stores ps WHERE ps.program_id = p.program_id AND ps.is_active = 1), 1)
  END AS pct_complete
FROM programs p
JOIN clients c ON c.client_id = p.client_id
ORDER BY p.status = 'active' DESC, p.wave_end;

-- Approved visits not yet invoiced, grouped by client.
CREATE VIEW IF NOT EXISTS visits_to_invoice AS
SELECT
  c.client_id,
  c.client_name,
  c.billing_email,
  c.payment_terms_days,
  COUNT(v.visit_id)                                   AS visit_count,
  COUNT(DISTINCT p.program_id)                        AS program_count,
  SUM(p.client_fee)                                   AS fees_amount,
  SUM(p.client_fee)                                   AS total_amount,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN clients c         ON c.client_id = p.client_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.client_invoiced = 0
GROUP BY c.client_id
ORDER BY c.client_name;

-- Approved visits not yet paid to the merchandiser, grouped by merchandiser.
CREATE VIEW IF NOT EXISTS merchandiser_pay_due AS
SELECT
  m.merchandiser_id,
  m.merchandiser_name,
  m.email,
  m.pay_handle,
  COUNT(v.visit_id)                                   AS visit_count,
  SUM(p.merchandiser_fee)                             AS fees_amount,
  SUM(p.merchandiser_fee)                             AS total_due,
  MIN(date(v.scheduled_start))                        AS first_visit_date,
  MAX(date(v.scheduled_start))                        AS last_visit_date,
  json_group_array(v.visit_id)                        AS visit_ids
FROM visits v
JOIN program_stores ps ON ps.program_store_id = v.program_store_id
JOIN programs p        ON p.program_id = ps.program_id
JOIN merchandisers m   ON m.merchandiser_id = v.merchandiser_id
WHERE v.status = 'completed'
  AND v.qa_status = 'approved'
  AND v.merchandiser_paid = 0
GROUP BY m.merchandiser_id
ORDER BY m.merchandiser_name;

-- Per merchandiser: how many visits they were given, completed, no-showed,
-- had rejected, and what share of their visits (completed or rejected) had
-- an on-time check-in (within 15 minutes before the slot start and before
-- the slot end). avg_score also covers completed and rejected visits. Use
-- this when deciding who gets the next assignment.
CREATE VIEW IF NOT EXISTS merchandiser_reliability AS
SELECT
  m.merchandiser_id,
  m.merchandiser_name,
  m.home_city,
  m.is_active,
  COUNT(v.visit_id) FILTER (WHERE v.status IN ('assigned', 'completed', 'no_show', 'rejected')) AS visits_given,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed')                                        AS completed,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'completed' AND v.qa_status = 'approved')           AS approved,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'no_show')                                          AS no_shows,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'rejected' OR (v.status = 'completed' AND v.qa_status = 'rejected')) AS rejected,
  COUNT(v.visit_id) FILTER (WHERE v.status = 'assigned')                                         AS upcoming,
  CASE WHEN COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL) = 0 THEN NULL
       ELSE round(100.0 *
            COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL
                                        AND julianday(v.checkin_at) >= julianday(v.scheduled_start || st.tz_offset, '-15 minutes')
                                        AND julianday(v.checkin_at) <= julianday(v.scheduled_end || st.tz_offset))
            / COUNT(v.visit_id) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.checkin_at IS NOT NULL), 1)
  END AS on_time_pct,
  round(AVG(v.score) FILTER (WHERE v.status IN ('completed', 'rejected') AND v.score IS NOT NULL), 1) AS avg_score,
  MAX(date(v.scheduled_start)) FILTER (WHERE v.status = 'completed')                             AS last_completed_date
FROM merchandisers m
LEFT JOIN visits v          ON v.merchandiser_id = m.merchandiser_id
LEFT JOIN program_stores ps ON ps.program_store_id = v.program_store_id
LEFT JOIN stores st         ON st.store_id = ps.store_id
GROUP BY m.merchandiser_id
ORDER BY m.is_active DESC, no_shows, m.merchandiser_name;

-- Unpaid client invoices with aging.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.client_name,
  c.billing_email,
  i.invoice_date,
  i.due_date,
  i.visit_count,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue,
  CASE WHEN i.due_date >= date('now') THEN 0
       ELSE CAST(julianday(date('now')) - julianday(i.due_date) AS INTEGER) END AS days_overdue,
  CASE WHEN i.due_date >= date('now') THEN 'current'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 30 THEN '1-30'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 60 THEN '31-60'
       WHEN julianday(date('now')) - julianday(i.due_date) <= 90 THEN '61-90'
       ELSE '90+' END AS aging_bucket
FROM invoices i
JOIN clients c ON c.client_id = i.client_id
WHERE i.paid = 0
ORDER BY i.due_date;
