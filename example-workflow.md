# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for the first wave of a program, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers. Watch what does **not** cross to ZenSched: the client contact, the fees, the merchandiser's pay handle, QA notes, scores. ZenSched sees `Walmart - US Hwy 290`, a street address, an event title that may name the CPG brand, a form, and two merchandiser accounts. Watch also the Denver store: its shifts are created in `-06:00` while the agency runs on `-05:00`.

The agency is **Northline Merch**, Austin, Texas, Central time. Today is Tuesday, September 8, 2026.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My Merchandising Agency, timezone_offset = -05:00, invoice_due_days = 30,
    invoice_prefix = INV, default_visit_minutes = 25, default_checkin_radius_m = 150
sqlite_query:   SELECT * FROM visits_overdue;                              → (none)
sqlite_query:   SELECT * FROM visits_flagged WHERE qa_status = 'pending';  → (none)
```

## "We're Northline Merch in Austin, Central time. Set the check-in radius to 150 m and give merchandisers a 30-minute reminder."

```
sqlite_execute: UPDATE settings SET value = 'Northline Merch' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';

policy_get: policy_id 0
  → settings: { geofence_enabled: true, require_on_site: true, remote_checkin: false, checkin_radius_m: 91, ... }

policy_update:
  policy_id: 0
  settings_json: "{\"checkin_radius_m\": 150, \"checkin_reminder_min_before\": 30}"
  → settings: { checkin_radius_m: 150, checkin_reminder_min_before: 30, geofence_enabled: true, require_on_site: true, ... }

sqlite_execute: UPDATE settings SET value = '150' WHERE key = 'default_checkin_radius_m';
```

> Saved. Merchandisers must check in within 150 m of the store pin (that covers a big-box parking lot) and get a reminder 30 minutes before each visit. GPS verification stays on for every in-store program; that is the proof your clients pay for. If you also run phone audits later, we give those their own brand and policy instead of flipping `remote_checkin` on this one. Central time is the default for new stores, but each store keeps its own time zone.

## "New program. Client is Frito Bay, contact Priya Nair, priya@fritobay.example, billing ap@fritobay.example, net 30. Weekday bay audits, one per store, 8 to 6, Sep 8 through Sep 30. $35 per visit to them, merchandisers get $18. Visits should take at least 8 minutes. Stores: 1234, Walmart, 5015 W US Hwy 290, Austin TX 78735 / T-1781, Target, 2300 S MoPac Expy, Austin TX 78746 / 412, HEB, 1000 E 41st St, Austin TX 78751 / 85, King Soopers, 1155 E 9th Ave, Denver CO 80218. Brief: count Frito Bay facings on the chip aisle, photograph the full bay, note voids. Questionnaire: section shelf; brand facings; OOS None / Partial / Full out; planogram match Yes / No / Unknown; bay photo max 3 required; competitor facings; notes; void reason N/A / Not shipped / Not stocked / Other if OOS is not None. Score it: in-stock 3, planogram yes 2."

```
sqlite_query:   SELECT client_id FROM clients WHERE client_name = 'Frito Bay';   → (none)
sqlite_execute:
  INSERT INTO clients (client_name, contact_name, contact_email, billing_email, payment_terms_days)
  VALUES ('Frito Bay', 'Priya Nair', 'priya@fritobay.example', 'ap@fritobay.example', 30);
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO programs (client_id, program_name, wave_start, wave_end, window_start_time, window_end_time, allowed_weekdays,
                        quota_per_store, client_fee, merchandiser_fee, min_minutes, questionnaire_notes, merchandiser_brief, status)
  VALUES (1, 'Frito Bay Audit - Sep', '2026-09-08', '2026-09-30', '08:00', '18:00', '1111100',
          1, 35.00, 18.00, 8,
          'Client contact Priya Nair. Chip-aisle bay audit. Client scoring: oos=none 3, planogram=yes 2.',
          'Count Frito Bay facings on the chip aisle. Photograph the full bay before you touch anything. Note voids. Bay photo is required.',
          'draft');
  → lastInsertRowid = 1
```

Stores: normalize, look up, insert. Denver gets `-06:00`.

```
sqlite_query: SELECT store_id, zensched_location_id FROM stores WHERE client_id = 1 AND normalized_address = 'walmart 5015 w us hwy 290 austin tx 78735';   → (none)
sqlite_execute:
  INSERT INTO stores (client_id, banner, store_code, address, city, region, country, postal, normalized_address, tz_offset, store_label)
  VALUES (1, 'Walmart', '1234', '5015 W US Hwy 290', 'Austin', 'TX', 'US', '78735', 'walmart 5015 w us hwy 290 austin tx 78735', '-05:00', 'Walmart - US Hwy 290');   → 1
sqlite_execute: INSERT INTO stores (...) VALUES (1, 'Target', 'T-1781', '2300 S MoPac Expy', 'Austin', 'TX', 'US', '78746', 'target 2300 s mopac expy austin tx 78746', '-05:00', 'Target - S MoPac Expy');   → 2
sqlite_execute: INSERT INTO stores (...) VALUES (1, 'HEB', '412', '1000 E 41st St', 'Austin', 'TX', 'US', '78751', 'heb 1000 e 41st st austin tx 78751', '-05:00', 'HEB - E 41st St');   → 3
sqlite_execute: INSERT INTO stores (...) VALUES (1, 'King Soopers', '85', '1155 E 9th Ave', 'Denver', 'CO', 'US', '80218', 'king soopers 1155 e 9th ave denver co 80218', '-06:00', 'King Soopers - E 9th Ave');   → 4

sqlite_execute: INSERT INTO program_stores (program_id, store_id, visits_required) VALUES (1, 1, 1);   → 1
sqlite_execute: INSERT INTO program_stores (program_id, store_id, visits_required) VALUES (1, 2, 1);   → 2
sqlite_execute: INSERT INTO program_stores (program_id, store_id, visits_required) VALUES (1, 3, 1);   → 3
sqlite_execute: INSERT INTO program_stores (program_id, store_id, visits_required) VALUES (1, 4, 1);   → 4
```

The questionnaire becomes this program's form (free):

```
form_create:
  title: "Frito Bay Audit"
  idempotency_key: "form-program-1"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Shelf", "identifier": "sec_shelf", "text": "Photograph the Frito Bay bay before you touch anything. Count facings as they sit. Answer from what you see, not what the planogram says should be there."},
  {"type": "number", "label": "Brand facings", "identifier": "facings", "required": true},
  {"type": "select", "label": "Out of stock", "identifier": "oos", "required": true, "options": ["None", "Partial", "Full out"]},
  {"type": "select", "label": "Planogram match", "identifier": "planogram_match", "required": true, "options": ["Yes", "No", "Unknown"]},
  {"type": "photo", "label": "Bay photo (required, up to 3)", "identifier": "bay", "required": true, "max_images": 3, "stamp_photos": true},
  {"type": "number", "label": "Competitor facings", "identifier": "competitor_facings", "required": true},
  {"type": "textarea", "label": "Notes", "identifier": "notes"},
  {"type": "select", "label": "Void reason (if not in stock)", "identifier": "void_reason",
   "options": ["N/A", "Not shipped", "Not stocked", "Other"],
   "show_if": {"field": "oos", "op": "not_equals", "value": "none", "action": "show"}}
]
```

```
  → form_id: 301, fields: [ ...8 fields echoed with identifiers... ]

sqlite_execute: UPDATE programs SET zensched_form_id = 301 WHERE program_id = 1;

sqlite_execute: INSERT INTO question_weights (program_id, identifier, weight, expected_value, match_rule) VALUES (1, 'oos', 3, 'none', 'equals');
sqlite_execute: INSERT INTO question_weights (program_id, identifier, weight, expected_value, match_rule) VALUES (1, 'planogram_match', 2, 'yes', 'equals');
```

Agent (first metered call this session, rule 9):

> Four new stores cost $0.12 to geocode now. Each completed visit will cost about $0.35 on ZenSched (two GPS punches and one form read with the bay photos), so about $1.40 for the wave. If the account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Walmart - US Hwy 290"
  street_address: "5015 W US Hwy 290, Austin, TX 78735"
  checkin_radius_m: 150
  idempotency_key: "loc-store-1"
  → location_id: 9001, lat: 30.2364, lng: -97.8211, pin_quality: "place",
    radius_note: "Check-in radius is enforced by the talent policy ...",
    billing: { meter: "geocode", units: 1, price: 0.03 }

location_create: name "Target - S MoPac Expy", street_address "2300 S MoPac Expy, Austin, TX 78746", checkin_radius_m 150, idempotency_key "loc-store-2"  → 9002, pin_quality "place"
location_create: name "HEB - E 41st St",       street_address "1000 E 41st St, Austin, TX 78751",    checkin_radius_m 150, idempotency_key "loc-store-3"  → 9003, pin_quality "street"
location_create: name "King Soopers - E 9th Ave", street_address "1155 E 9th Ave, Denver, CO 80218", checkin_radius_m 150, idempotency_key "loc-store-4"  → 9004, pin_quality "place"

sqlite_execute: UPDATE stores SET zensched_location_id = 9001 WHERE store_id = 1;
sqlite_execute: UPDATE stores SET zensched_location_id = 9002 WHERE store_id = 2;
sqlite_execute: UPDATE stores SET zensched_location_id = 9003 WHERE store_id = 3;
sqlite_execute: UPDATE stores SET zensched_location_id = 9004 WHERE store_id = 4;
```

Nothing about Priya, the fees, or the scoring is in `name` or `notes`. One event per store for the wave, the form attached to each:

```
event_create:
  location_id: 9001
  title: "Frito Bay Audit - US Hwy 290"
  start_date: "2026-09-08"
  end_date:   "2026-09-30"          ← the wave (23 days; the cap is 60)
  idempotency_key: "event-ps-1-20260908"
  → event_id: 7001

form_assign:
  form_id: 301
  event_id: 7001
  idempotency_key: "assign-form-1-7001"
  → status: "assigned", form_id: 301, event_id: 7001, policy_id: 0

sqlite_execute: UPDATE program_stores SET zensched_event_id = 7001, event_valid_until = '2026-09-30' WHERE program_store_id = 1;

event_create: location_id 9002, title "Frito Bay Audit - S MoPac Expy", 2026-09-08..2026-09-30, key "event-ps-2-20260908"  → 7002;  form_assign 301 → 7002, key "assign-form-1-7002"
event_create: location_id 9003, title "Frito Bay Audit - E 41st St",    2026-09-08..2026-09-30, key "event-ps-3-20260908"  → 7003;  form_assign 301 → 7003, key "assign-form-1-7003"
event_create: location_id 9004, title "Frito Bay Audit - E 9th Ave",    2026-09-08..2026-09-30, key "event-ps-4-20260908"  → 7004;  form_assign 301 → 7004, key "assign-form-1-7004"
sqlite_execute: UPDATE program_stores SET zensched_event_id = 7002, event_valid_until = '2026-09-30' WHERE program_store_id = 2;
sqlite_execute: UPDATE program_stores SET zensched_event_id = 7003, event_valid_until = '2026-09-30' WHERE program_store_id = 3;
sqlite_execute: UPDATE program_stores SET zensched_event_id = 7004, event_valid_until = '2026-09-30' WHERE program_store_id = 4;

sqlite_execute: INSERT INTO visits (program_store_id) VALUES (1);   → visit 1 (open)
sqlite_execute: INSERT INTO visits (program_store_id) VALUES (2);   → visit 2
sqlite_execute: INSERT INTO visits (program_store_id) VALUES (3);   → visit 3
sqlite_execute: INSERT INTO visits (program_store_id) VALUES (4);   → visit 4

sqlite_execute: UPDATE programs SET status = 'active' WHERE program_id = 1;
```

> Frito Bay Audit - Sep is live: 4 stores (3 Austin, 1 Denver), 4 visits, weekdays 08:00–18:00 through Sep 30. $35 per visit to Frito Bay; merchandisers earn $18. The Frito Bay Audit form has 8 fields with a required bay photo (max 3), and I'll score each visit out of 100 from your weights. HEB geocoded to the street rather than the building; with the 150 m radius that's fine, tell me if a merchandiser has trouble checking in there. No merchandisers yet; who should I invite?

## "Invite Dana Ruiz, dana@example.com, Austin, PayPal same email. And Marcus Lee, marcus@example.com, Denver, Venmo @marcuslee."

> Inviting two merchandisers costs $0.50. OK?

Owner: *"yes"*

```
worker_invite:
  email: "dana@example.com"
  first_name: "Dana"
  last_name: "Ruiz"
  idempotency_key: "worker-dana@example.com"
  → worker_id: 501, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

worker_invite: email "marcus@example.com", first_name "Marcus", last_name "Lee", idempotency_key "worker-marcus@example.com"  → worker_id 502

sqlite_execute: INSERT INTO merchandisers (merchandiser_name, email, home_city, home_region, zensched_worker_id, pay_handle) VALUES ('Dana Ruiz', 'dana@example.com', 'Austin', 'TX', 501, 'paypal:dana@example.com');   → 1
sqlite_execute: INSERT INTO merchandisers (merchandiser_name, email, home_city, home_region, zensched_worker_id, pay_handle) VALUES ('Marcus Lee', 'marcus@example.com', 'Denver', 'CO', 502, 'venmo:@marcuslee');   → 2
```

> Invited Dana and Marcus. Each gets an email with the app link and an activation code. They'll see the store, their time slot, and the form; the brief ("count Frito Bay facings on the chip aisle, photograph the full bay") you send them yourself, or tell me to include it when I confirm assignments.

## "Give Dana the three Austin stores next week, morning, and Marcus the Denver one on Tuesday."

```
sqlite_query: SELECT * FROM visits_open;
  → visit 1 | Walmart - US Hwy 290      | Austin | -05:00 | evt 7001 | 08:00–18:00 | 1111100 | 22 days left
    visit 2 | Target - S MoPac Expy     | Austin | -05:00 | evt 7002 | ...
    visit 3 | HEB - E 41st St           | Austin | -05:00 | evt 7003 | ...
    visit 4 | King Soopers - E 9th Ave  | Denver | -06:00 | evt 7004 | ...
sqlite_query: SELECT merchandiser_id, zensched_worker_id FROM merchandisers WHERE is_active = 1;   → (1, 501), (2, 502)
```

Next week is Sep 14–18, all weekdays. Dana's three visits go on Mon, Wed, Fri as a south-Austin then central route; 25-minute slots inside 08:00–18:00.

```
sqlite_execute: UPDATE visits SET merchandiser_id = 1, scheduled_start = '2026-09-14T09:00:00', scheduled_end = '2026-09-14T09:25:00', status = 'assigned' WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET merchandiser_id = 1, scheduled_start = '2026-09-16T09:00:00', scheduled_end = '2026-09-16T09:25:00', status = 'assigned' WHERE visit_id = 2;
sqlite_execute: UPDATE visits SET merchandiser_id = 1, scheduled_start = '2026-09-18T10:00:00', scheduled_end = '2026-09-18T10:25:00', status = 'assigned' WHERE visit_id = 3;
sqlite_execute: UPDATE visits SET merchandiser_id = 2, scheduled_start = '2026-09-15T09:00:00', scheduled_end = '2026-09-15T09:25:00', status = 'assigned' WHERE visit_id = 4;

sqlite_query: SELECT * FROM visits_upcoming WHERE zensched_shift_id IS NULL;
  → visit 1 | Walmart      | worker 501 | start_iso 2026-09-14T09:00:00-05:00 | end_iso 2026-09-14T09:25:00-05:00 | shift-visit-1 | needs_location 0 | needs_event 0 | evt 7001
    visit 4 | King Soopers | worker 502 | start_iso 2026-09-15T09:00:00-06:00 | end_iso 2026-09-15T09:25:00-06:00 | shift-visit-4 | needs_location 0 | needs_event 0 | evt 7004
  (visits 2 and 3 are 8 and 10 days out, past the view's 7-day horizon; the agent builds their ISO strings the same way: scheduled_start || tz_offset)

shift_create:
  event_id: 7001
  worker_id: 501
  start: "2026-09-14T09:00:00-05:00"
  end:   "2026-09-14T09:25:00-05:00"
  idempotency_key: "shift-visit-1"
  → shift_id: 88001, status: "scheduled", forms_installed: [301]

shift_create: event_id 7002, worker_id 501, start "2026-09-16T09:00:00-05:00", end "2026-09-16T09:25:00-05:00", idempotency_key "shift-visit-2"  → 88002
shift_create: event_id 7003, worker_id 501, start "2026-09-18T10:00:00-05:00", end "2026-09-18T10:25:00-05:00", idempotency_key "shift-visit-3"  → 88003
shift_create:
  event_id: 7004
  worker_id: 502
  start: "2026-09-15T09:00:00-06:00"        ← Denver offset, not the agency's
  end:   "2026-09-15T09:25:00-06:00"
  idempotency_key: "shift-visit-4"
  → shift_id: 88004, status: "scheduled", forms_installed: [301]

sqlite_execute: UPDATE visits SET zensched_shift_id = 88001 WHERE visit_id = 1;
sqlite_execute: UPDATE visits SET zensched_shift_id = 88002 WHERE visit_id = 2;
sqlite_execute: UPDATE visits SET zensched_shift_id = 88003 WHERE visit_id = 3;
sqlite_execute: UPDATE visits SET zensched_shift_id = 88004 WHERE visit_id = 4;
```

> Assigned:
> - Dana: Mon 9/14 09:00–09:25 Walmart US Hwy 290; Wed 9/16 09:00–09:25 Target MoPac; Fri 9/18 10:00–10:25 HEB 41st
> - Marcus: Tue 9/15 09:00–09:25 King Soopers E 9th Ave (Mountain time)
>
> Both notified in the app with the Frito Bay Audit form attached and a reminder 30 minutes before. Send them the brief; remind them the bay photo is required (up to 3) and to arrive inside the slot.

Nothing but the shift IDs is written locally. Asking again for the same visits returns the same four shifts because of `shift-visit-{visit_id}`.

## The merchandisers do the work

Monday 09:03, Dana at Walmart: **Check in** (GPS: 48 m from the pin, verified, $0.10). Counts 12 Frito Bay facings, 8 competitor. Opens **Frito Bay Audit**: facings 12, OOS None, planogram Yes, three bay photos, competitor 8, notes "endcap fully set". Submit. **Check out** 09:22.

Tuesday, Marcus in Denver runs late. Slot was 09:00–09:25 Mountain; he checks in at 10:05 (GPS verified, 62 m), counts 4 facings with a partial void, planogram No, two bay photos, competitor 11, void reason Not stocked, checks out 10:21.

Wednesday, Dana at Target: in 09:02, facings 10, OOS None, planogram Yes, two photos, competitor 6, out 09:21.

Friday, Dana does HEB: in 10:01, facings 9, OOS Partial, planogram Unknown, three photos, competitor 7, void reason Not shipped, out 10:24.

## "Pull this week's results." (Saturday, Sep 19)

```
shift_list:
  date_from: "2026-09-14"
  date_to:   "2026-09-18"
  status:    "checked_out"
  → shifts: [
      { shift_id: 88001, event_id: 7001, worker_id: 501, date: "2026-09-14", start: "09:00", end: "09:25", status: "checked_out" },
      { shift_id: 88004, event_id: 7004, worker_id: 502, date: "2026-09-15", start: "09:00", end: "09:25", status: "checked_out" },
      { shift_id: 88002, event_id: 7002, worker_id: 501, date: "2026-09-16", start: "09:00", end: "09:25", status: "checked_out" },
      { shift_id: 88003, event_id: 7003, worker_id: 501, date: "2026-09-18", start: "10:00", end: "10:25", status: "checked_out" }
    ], count: 4

sqlite_query: SELECT visit_id, program_store_id, merchandiser_id FROM visits WHERE zensched_shift_id IN (88001, 88002, 88003, 88004) AND status = 'assigned';
  → (1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 2)

shift_status: shift_id 88001
  → status "checked_out", actual_in "2026-09-14T09:03:10-05:00", actual_out "2026-09-14T09:22:40-05:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 48 }, { type: "out", gps_verified: true, distance_from_site_m: 41 } ]
shift_status: shift_id 88004
  → actual_in "2026-09-15T10:05:20-06:00", actual_out "2026-09-15T10:21:05-06:00", both punches gps_verified, 62 m / 55 m
shift_status: shift_id 88002
  → actual_in "2026-09-16T09:02:00-05:00", actual_out "2026-09-16T09:21:15-05:00", both punches gps_verified, 22 m / 18 m
shift_status: shift_id 88003
  → actual_in "2026-09-18T10:01:30-05:00", actual_out "2026-09-18T10:24:10-05:00", both punches gps_verified, 35 m / 30 m
(free)
```

Agent (metered read, rule 9):

> Four visits have results. Reading them costs $0.15 each because each has bay photos, $0.60 total; I read each once and keep what matters locally. OK?

Owner: *"go."*

```
form_export:
  form_id: 301
  since: "2026-09-08"
  until: "2026-09-19"
  format: "json"
  → row_count: 4, rows: [
      { submission_id: 3301, worker_id: 501, event_id: 7001, submitted_at: "2026-09-14 09:20:10",
        data: { facings: 12, oos: "none", planogram_match: "yes", competitor_facings: 8, notes: "endcap fully set" },
        media: [ { field: "bay", cdn_url: "https://cdn.zensched.com/m/.../b3301a.jpg" }, ... ] },
      { submission_id: 3302, worker_id: 502, event_id: 7004, submitted_at: "2026-09-15 10:19:40",
        data: { facings: 4, oos: "partial", planogram_match: "no", competitor_facings: 11,
                void_reason: "not_stocked", notes: "two holes on the right, tags still up" },
        media: [ { field: "bay", cdn_url: "https://cdn.zensched.com/m/.../b3302a.jpg" }, ... ] },
      { submission_id: 3303, worker_id: 501, event_id: 7002, submitted_at: "2026-09-16 09:19:50",
        data: { facings: 10, oos: "none", planogram_match: "yes", competitor_facings: 6 },
        media: [ { field: "bay", cdn_url: "https://cdn.zensched.com/m/.../b3303a.jpg" } ] },
      { submission_id: 3304, worker_id: 501, event_id: 7003, submitted_at: "2026-09-18 10:22:00",
        data: { facings: 9, oos: "partial", planogram_match: "unknown", competitor_facings: 7,
                void_reason: "not_shipped", notes: "one SKU tagged not-on-truck this week" },
        media: [ { field: "bay", cdn_url: "https://cdn.zensched.com/m/.../b3304a.jpg" }, ... ] }
    ]
    billing: { meter: "form_media", units: 4, price: 0.60 }
```

Match: 3301 → event 7001 / worker 501 / Sep 14 → visit 1. 3302 → 7004 / 502 / Sep 15 → visit 4. 3303 → 7002 / 501 / Sep 16 → visit 2. 3304 → 7003 / 501 / Sep 18 → visit 3. Score from `question_weights` (total weight 5): visit 1 = 3+2 = 5 → **100**; visit 4 = 0+0 = 0 → **0**; visit 2 = 3+2 = 5 → **100**; visit 3 = 0+0 = 0 → **0**.

```
sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 3301,
         checkin_at = '2026-09-14T09:03:10-05:00', checkout_at = '2026-09-14T09:22:40-05:00',
         score = 100, qa_status = 'pending'
  WHERE visit_id = 1;
  (trigger fills duration_minutes = 20)

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 3302,
         checkin_at = '2026-09-15T10:05:20-06:00', checkout_at = '2026-09-15T10:21:05-06:00',
         score = 0, qa_status = 'pending'
  WHERE visit_id = 4;
  (duration_minutes = 16)

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 3303,
         checkin_at = '2026-09-16T09:02:00-05:00', checkout_at = '2026-09-16T09:21:15-05:00',
         score = 100, qa_status = 'pending'
  WHERE visit_id = 2;
  (duration_minutes = 19)

sqlite_execute:
  UPDATE visits SET status = 'completed', submission_dc_id = 3304,
         checkin_at = '2026-09-18T10:01:30-05:00', checkout_at = '2026-09-18T10:24:10-05:00',
         score = 0, qa_status = 'pending'
  WHERE visit_id = 3;
  (duration_minutes = 23)

sqlite_query: SELECT * FROM visits_flagged WHERE qa_status = 'pending';
  → visit 4 | King Soopers | Marcus Lee | slot 2026-09-15T09:00:00..09:25:00 | checkin 10:05:20-06:00 | 16 min
           | checkin_late 1 | checkin_early 0 | no_checkin 0 | short_visit 0 | minutes_after_slot_end 40
```

> Pulled 4 visits, all GPS-verified at the store.
>
> **Flag — King Soopers (Denver), Marcus, Tue.** He checked in at 10:05, 40 minutes after his 09:00–09:25 slot ended. The audit itself: 4 facings, partial OOS, planogram no, void not-stocked, competitor 11. Score 0.
>
> On time:
> - Walmart, Dana, Mon: 20 min. 12 facings, in stock, planogram yes, competitor 8. Score 100.
> - Target, Dana, Wed: 19 min. 10 facings, in stock, planogram yes, competitor 6. Score 100.
> - HEB, Dana, Fri: 23 min. 9 facings, partial OOS (not shipped), planogram unknown, competitor 7. Score 0 — genuine finding, not a flag.
>
> Approve, reject, or ask me for the bay-photo links.

## "Approve Dana's three. Reject Marcus — Frito Bay won't take a visit that started after the slot. Reopen it."

```
sqlite_execute: UPDATE visits SET qa_status = 'approved' WHERE visit_id IN (1, 2, 3);
sqlite_execute: UPDATE visits SET qa_status = 'rejected', status = 'rejected', qa_notes = 'Checked in 40 min after slot. Client will not accept.' WHERE visit_id = 4;
sqlite_execute: INSERT INTO visits (program_store_id) VALUES (4);   → visit 5 (open, King Soopers again)
```

> Done. Walmart, Target, and HEB approved. King Soopers rejected (not billed, not paid). The Denver visit is open again — want me to give it back to Marcus on Wednesday 09:00 Mountain, or to someone else?

## "How's the Frito Bay program doing?"

```
sqlite_query: SELECT * FROM program_progress WHERE program_id = 1;
  → Frito Bay Audit - Sep | active | 4 stores | required 4 | open 1 | assigned 0 | completed 3 | approved 3 | no_show 0 | qa_pending 0 | 75.0% | 11 days left
```

> Three-quarters done: 3 of 4 visits approved (Walmart 100, Target 100, HEB 0 — partial void). King Soopers is open after Marcus's late check-in. 11 days left in the wave.

## "Give the Denver redo to Marcus Wednesday 09:00. Then send Frito Bay their results and invoice for what's approved."

```
sqlite_execute: UPDATE visits SET merchandiser_id = 2, scheduled_start = '2026-09-23T09:00:00', scheduled_end = '2026-09-23T09:25:00', status = 'assigned' WHERE visit_id = 5;

sqlite_query: SELECT * FROM visits_upcoming WHERE zensched_shift_id IS NULL;
  → visit 5 | King Soopers | worker 502 | 2026-09-23T09:00:00-06:00 .. 09:25:00-06:00 | shift-visit-5 | evt 7004

shift_create: event_id 7004, worker_id 502, start "2026-09-23T09:00:00-06:00", end "2026-09-23T09:25:00-06:00", idempotency_key "shift-visit-5"  → 88005
sqlite_execute: UPDATE visits SET zensched_shift_id = 88005 WHERE visit_id = 5;
```

Submissions were already read, so the CSV export bills nothing new.

```
form_export:
  form_id: 301
  since: "2026-09-08"
  until: "2026-09-30"
  format: "csv"
  → download_url: "https://exports.zensched.com/.../frito-bay-audit.csv" (expires), row_count: 4
    billing: { meter: "form_media", units: 0, price: 0.00 }   ← all four already billed
```

> Results CSV: (link). It has 4 rows: the 3 approved visits plus Marcus's rejected Sep 15 visit; delete that row, and delete the `worker_name` column before it goes to Frito Bay. Summary: 3 of 4 stores audited so far; average score 67; Walmart 100, Target 100, HEB 0 (partial void, not shipped). King Soopers redo is on Marcus for Wed 9/23 09:00 Mountain.

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Frito Bay | ap@fritobay.example | net 30 | 3 visits | 1 program | fees 105.00 | total 105.00 | 2026-09-14 .. 2026-09-18

sqlite_execute:
  INSERT INTO invoices (client_id, program_id, invoice_date, due_date, visit_count, fees_amount, total_amount, line_items)
  SELECT p.client_id, CASE WHEN COUNT(DISTINCT p.program_id) = 1 THEN MIN(p.program_id) END, date('now'),
         date('now', '+' || COALESCE(MAX(c.payment_terms_days), (SELECT value FROM settings WHERE key = 'invoice_due_days')) || ' days'),
         COUNT(*), SUM(p.client_fee), SUM(p.client_fee),
         json_group_array(json_object('visit_id', v.visit_id, 'date', date(v.scheduled_start), 'store', st.store_label, 'store_code', st.store_code,
                                      'program', p.program_name, 'fee', p.client_fee, 'score', v.score))
  FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id JOIN programs p ON p.program_id = ps.program_id
       JOIN stores st ON st.store_id = ps.store_id JOIN clients c ON c.client_id = p.client_id
  WHERE v.status = 'completed' AND v.qa_status = 'approved' AND v.client_invoiced = 0 AND p.client_id = 1 GROUP BY p.client_id;

sqlite_execute:
  UPDATE visits SET client_invoiced = 1 WHERE visit_id IN (SELECT v.visit_id FROM visits v JOIN program_stores ps ON ps.program_store_id = v.program_store_id
                                                          JOIN programs p ON p.program_id = ps.program_id
                                                          WHERE v.status = 'completed' AND v.qa_status = 'approved' AND v.client_invoiced = 0 AND p.client_id = 1);
sqlite_query:   SELECT invoice_number, invoice_date, due_date, visit_count, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-19 | 2026-10-19 | 3 | 105.00     (number assigned by trigger)
```

> Here's the invoice, ready to paste into an email to ap@fritobay.example:
>
> ```
> Northline Merch
> Invoice INV-2026-0001
> To: Frito Bay — Frito Bay Audit - Sep
> Date: Sep 19, 2026    Due: Oct 19, 2026 (net 30)
>
>   Sep 14   #1234   Walmart - US Hwy 290         visit fee  $35.00
>   Sep 16   #T-1781 Target - S MoPac Expy        visit fee  $35.00
>   Sep 18   #412    HEB - E 41st St              visit fee  $35.00
>
> Visit fees:      $105.00
> Total due:       $105.00
> Every visit was GPS-verified at the store with timestamped bay photos. Results CSV sent separately.
> ```
>
> No merchandiser names on it. Say "sent" and I'll note the date. King Soopers will land on a later invoice if the redo is approved.

## "Sent. Now do merchandiser pay."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number = 'INV-2026-0001';

sqlite_query: SELECT * FROM merchandiser_pay_due;
  → Dana Ruiz | paypal:dana@example.com | 3 visits | fees 54.00 | total 54.00 | 2026-09-14 .. 2026-09-18 | [1,2,3]

sqlite_execute:
  INSERT INTO merchandiser_payouts (merchandiser_id, period_start, period_end, visit_count, fees_amount, total_amount, visit_ids)
  SELECT merchandiser_id, '2026-09-14', '2026-09-19', visit_count, fees_amount, total_due, visit_ids FROM merchandiser_pay_due WHERE merchandiser_id = 1;
sqlite_execute: UPDATE visits SET merchandiser_paid = 1 WHERE merchandiser_id = 1 AND status = 'completed' AND qa_status = 'approved' AND merchandiser_paid = 0;
```

> Pay sheet for Sep 14–19:
>
> ```
> Dana Ruiz     paypal:dana@example.com
>   Sep 14  Walmart US Hwy 290     $18.00
>   Sep 16  Target MoPac           $18.00
>   Sep 18  HEB 41st               $18.00
>                                       $54.00
> ```
>
> Marcus's rejected Sep 15 visit is not on here. Tell me "paid" when the transfer is done and I'll mark the payout.

Owner: *"paid"*

```
sqlite_execute: UPDATE merchandiser_payouts SET paid = 1, paid_date = date('now') WHERE paid = 0;
```

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Frito Bay's contact (Priya), billing email, payment terms | SQLite **only** | Client confidentiality; ZenSched does not model clients |
| The program: wave dates, window, weekdays, quota, $35 / $18, min minutes, the client's brief | SQLite **only** | Fees and the brief never reach merchandisers via ZenSched fields |
| Question weights and per-visit scores | SQLite **only** | ZenSched is not a scoring engine |
| Store cache with normalized addresses and per-store `tz_offset` | SQLite | Geocode each store once; Denver shifts in `-06:00` |
| Dana's and Marcus's pay handles, home cities, reliability | SQLite | Pay and assignment decisions; ZenSched holds only the worker account |
| QA decisions and notes, `client_invoiced` / `merchandiser_paid` flags | SQLite **only** | Money and judgment |
| Four store pins: `Walmart - US Hwy 290` etc. with street addresses | ZenSched (IDs in `stores`) | Needed for geofenced check-in |
| Four events `Frito Bay Audit - <street>`, Sep 8–30 | ZenSched (IDs + `event_valid_until` in `program_stores`) | Shifts hang off events; one per store per wave |
| The Frito Bay Audit form (8 fields, required bay photo max 3) | ZenSched (ID in `programs.zensched_form_id`) | Installed on the phone per shift; one form per program |
| Dana, Marcus, their invites, their apps | ZenSched (IDs in `merchandisers`) | Workforce and notifications |
| Five shifts (four original, one redo) | ZenSched only (IDs in `visits`) | Live schedule; never copied |
| GPS punches, distance from the store, actual in/out times | ZenSched only | Verified record; stamps copied to `visits.checkin_at` / `checkout_at` |
| Four submissions with bay photos | ZenSched (originals); `submission_dc_id` and score in `visits` | Read once (metered), then answered from SQLite; CSV replay for the client was free |
| One client invoice, one merchandiser payout | SQLite | Money |
