# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What ZenSched verifies and what it does not" section of `README.md`. Short version: ZenSched proves a merchandiser was at the store, inside the slot, for a plausible time, and collected the form with bay photos. It does not score, branch, or report; the AI and your local database do that.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\merch-ops` (Windows) or `/Users/yourname/merch-ops` (Mac). Note the full path. It will hold client fees and merchandiser pay details, so keep it backed up.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "merch-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/merch-ops/merch-ops.db" }
    }
  }
}
```

- On Windows, double every backslash: `"C:\\Users\\YourName\\merch-ops\\merch-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Merchandising Agency". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my merch-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> We're Northline Merch in Austin, Texas, Central time. Set the check-in radius to 150 m and give merchandisers a 30-minute reminder.

The AI saves your name and default time zone and sets the ZenSched check-in policy (free): merchandisers must be within 150 m of the store pin (big-box parking lots), GPS verification stays on, and they get a reminder before each visit. There is no form yet; each client program gets its own.

## 6. Set up your first program

Paste the client's store CSV and questionnaire. For example:

> New program. Client is Frito Bay, contact Priya Nair, priya@fritobay.example, billing ap@fritobay.example, net 30. Weekday bay audits, one per store, 8 to 6, Sep 8 through Sep 30. $35 per visit to them, merchandisers get $18, visits at least 8 minutes. Stores: 1234, Walmart, 5015 W US Hwy 290, Austin TX 78735 / T-1781, Target, 2300 S MoPac Expy, Austin TX 78746 / 412, HEB, 1000 E 41st St, Austin TX 78751 / 85, King Soopers, 1155 E 9th Ave, Denver CO 80218. Brief: count Frito Bay facings on the chip aisle, photograph the full bay, note voids. Questionnaire: section shelf; brand facings; OOS None / Partial / Full out; planogram match Yes / No / Unknown; bay photo max 3 required; competitor facings; notes; void reason N/A / Not shipped / Not stocked / Other if OOS is not None.

Behind the scenes the AI saves the client and program locally, adds the four stores to its store cache (the Denver one in Mountain time), turns the questionnaire into a ZenSched form with a required bay photo (free), asks you before geocoding the four stores ($0.12, may trigger the $5 activation deposit the first time), creates one event per store for the wave with the form attached, and creates four open visits. You just see a confirmation. Each completed visit will cost about $0.35 on ZenSched.

## 7. Invite your merchandisers

> Invite Dana Ruiz, dana@example.com, Austin, PayPal same email. And Marcus Lee, marcus@example.com, Denver, Venmo @marcuslee.

Each gets an email ($0.25), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Send them the brief yourself; ZenSched shows them the store, the slot, and the form.

## 8. Assign the visits

> Give Dana the three Austin stores next week, morning, and Marcus the Denver one on Tuesday.

The AI picks weekdays inside the 8–6 window, creates one shift per visit on ZenSched in each store's own time zone, and confirms by merchandiser and day. Dana gets a push notification per visit with the form attached. She checks in at the store (GPS-verified), counts facings, photographs the bay, fills in the form, and checks out.

Or say "fill the open visits" and the AI proposes who should take what, by home city and track record, and waits for your yes.

## 9. After the visits are done

> Pull this week's results.

The AI pulls the completed, GPS-verified shifts and their punch times from ZenSched (free), then the submissions (metered, so it tells you the cost first, about $0.15 per visit), records scores, and leads with anything suspicious: a check-in 40 minutes after the slot ended, a form with no check-in, a 4-minute visit. Missed shifts become no-shows and the visit is reopened.

> Approve Dana's two. Reject Marcus, he checked in after the slot. Reopen it.

Approved visits go on the client invoice and the merchandiser pay sheet. Rejected ones are reopened for someone to redo.

> How's the Frito Bay program doing?

Required, assigned, completed, approved, percent complete, days left. From the local database, free.

> Send Frito Bay their results and invoice.

A CSV download of the wave's submissions (already-read submissions are not billed again) plus a plain-text invoice with one line per approved visit and a note that every visit was GPS-verified with timestamped bay photos. No merchandiser names.

> Run merchandiser pay.

A pay sheet per merchandiser (fee, with their pay handle). You pay them through PayPal or Venmo and say "paid".

> Frito Bay paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, what ZenSched does and does not verify, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
- `SKILL.md` if you also run phone or remote photo audits — it has the brand/policy recipe so you do not flip geofencing off for in-store work
