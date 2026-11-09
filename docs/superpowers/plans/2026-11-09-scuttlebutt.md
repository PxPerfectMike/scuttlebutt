# Scuttlebutt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon that spreads like/dislike votes, tags and Grump status between players over a hidden addon channel, and keeps private notes.

**Architecture:** Pure-logic modules (codec, store, guard, trust, sync) take no WoW API and are tested in real Lua 5.1 through lupa, including a many-client gossip simulation. Thin WoW modules (channel, presence, UI) wire them to the game. Task 1 is an in-game spike that checks the API assumptions before anything is built on them.

**Tech Stack:** Lua 5.1 (WoW Forever 1.60.1, Interface 16001), Python 3.13 + lupa 2.8 for tests (`PYLIBS` points at a folder with lupa).

**Spec:** `docs/superpowers/specs/2026-11-09-scuttlebutt-design.md`

## Global Constraints

- `## Interface: 16001`, WoW Forever client 1.60.1. No dependencies beyond the game; embedded libraries only if their license allows.
- Tabs for indentation. American English in all text, code and UI copy.
- Never say "anonymous" anywhere. The wording is "names aren't shown".
- Every Lua file compiles under real Lua 5.1 `loadstring` (the test runner checks this for every addon file).
- Pure-logic files (`Tunables.lua`, `Codec.lua`, `Store.lua`, `Guard.lua`, `Trust.lua`, `Sync.lua`) call no WoW API and no globals except `math`, `string`, `table`, `pairs`, `ipairs`, `type`, `tostring`, `tonumber`, `select`, `next`, `error`, `pcall`. Clock, randomness and sending are passed in.
- Each addon file starts with `local _, ns = ...` and exports through `ns`.
- Nothing is sent or processed inside instances (`IsInInstance()` true). No error when a value is a hidden (secret) value; skip the work instead (`issecretvalue` when it exists, plus `pcall` around reads of other units).
- Players are keyed `Name-Realm`, always normalized through `ns.Names.Normalize`.
- All tunables live in `Tunables.lua`, with the spec's values: `MIN_LEVEL = 9`, `DISLIKES_PER_DAY = 15`, `SOUR_WINDOW = 30`, `SOUR_RATIO = 0.8`, `SOUR_PAUSE = 86400`, `GRUMP_MIN_VOTES = 20`, `GRUMP_RATIO = 0.8`, `GRUMP_WEAR_OFF = 14 * 86400`, `RECENT_GROUP = 86400`, `ONLINE_RECENT = 300`, `UNWITNESSED_WEIGHT = 0.25`, `REFRESH_EVERY = 14 * 86400`, `FADE = 90 * 86400`, `MAX_RECORDS = 50000`, `MAX_TAGS = 3`, `REPLY_DELAY_MAX = 30`, `REPLY_LIMIT = 3`, `MSG_MAX = 255`, `PROTOCOL = 1`, `FUTURE_SLACK = 600`.
- Defaults: Exclude Grump votes off; tooltip, group finder and nameplates on; network on.
- Commit only when the user asks. Commit messages end with `Claude-Session: https://claude.ai/code/session_01RbmTbeTeib8qHTnoo67gSw`. The repo's git author is already `PxPerfectMike <56899037+PxPerfectMike@users.noreply.github.com>`.

## Review Focus

1. **Voting on yourself** (or another character on your own account): must be refused with a reason, never stored. Test in Task 4.
2. **The same player written differently** ("Bob", "Bob-Realm", "bob-realm" from a realm-less chat event): must map to one key, or one player gets split scores. Test in Task 2.
3. **Accented names** (UTF-8, e.g. "Zoë-Draenor"): must survive encode, decode and storage byte for byte. Test in Task 2.
4. **Garbage or hostile channel messages** (truncated, wrong version, huge counts, `\0`-free junk): must be dropped without a Lua error. Test in Task 2 (codec) and Task 6 (sync).
5. **Votes stamped in the future** (wrong clock or forged): a time more than `FUTURE_SLACK` ahead is clamped to receive time, so it can't win "newest wins" forever. Test in Task 3.

---

## File structure

| File | Responsibility |
|---|---|
| `Scuttlebutt/Scuttlebutt.toc` | Addon manifest, `## SavedVariables: ScuttlebuttDB`, file order. |
| `Scuttlebutt/Tunables.lua` | Every number from Global Constraints, tag list. |
| `Scuttlebutt/Names.lua` | `Name-Realm` normalization. |
| `Scuttlebutt/Codec.lua` | Records and messages to and from strings. |
| `Scuttlebutt/Store.lua` | Vote records, witness flags, private notes, digest, prune. |
| `Scuttlebutt/Guard.lua` | Layer 1: level, eligibility, daily cap, sour streak, one vote per account, no self-votes. |
| `Scuttlebutt/Trust.lua` | Layer 2 and scoring: weights, Grump status, circle, sender damage limit. |
| `Scuttlebutt/Sync.lua` | Gossip protocol: summary, delayed replies, trickle with forwarding, own-vote refresh. |
| `Scuttlebutt/Channel.lua` | WoW: join and hide the channel, prefix, throttled send queue, instance pause. |
| `Scuttlebutt/Presence.lua` | WoW: "online now" and "recently grouped" tracking, circle (friends, guild). |
| `Scuttlebutt/PlayerFile.lua` | WoW: the player file window, vote and tag controls, private note. |
| `Scuttlebutt/Display.lua` | WoW: tooltip lines, nameplate text, group finder text. |
| `Scuttlebutt/Menu.lua` | WoW: minimap button, settings panel, player right-click entry. |
| `Scuttlebutt/Core.lua` | WoW: SavedVariables setup, wiring, events, slash commands. |
| `ScuttlebuttSpike/` | Task 1 only, a throwaway dev addon; never packaged. |
| `tests/run.py` | Loads addon files into lupa, runs `tests/test_*.lua`, compiles every addon file. |
| `tests/lib.lua` | `T(name, fn)`, `eq(a, b, msg)`, `ok(v, msg)`, `fails(fn, pattern)`. |
| `tests/test_*.lua` | One file per pure-logic module, plus `test_sim.lua`. |
| `tools/package.sh` | Version check, Lua check, zip to `dist/Scuttlebutt-<version>.zip`. |

---

### Task 1: In-game spike for the API assumptions

**Files:**
- Create: `ScuttlebuttSpike/ScuttlebuttSpike.toc`, `ScuttlebuttSpike/Spike.lua`
- Create: `docs/spike-results.md`

**Interfaces:**
- Produces: `docs/spike-results.md`, which every later WoW-facing task reads. If a check failed, the owning task follows the fallback written there.

- [ ] **Step 1: Write the spike addon.** Slash command `/sbspike <check>`, printing results to chat with `print`. Checks, one subcommand each:
  - `chan`: `JoinTemporaryChannel("ScuttlebuttNet")`, remove it from every chat frame (`ChatFrame_RemoveChannel` for each `NUM_CHAT_WINDOWS` frame), print `GetChannelName("ScuttlebuttNet")`. Then `C_ChatInfo.RegisterAddonMessagePrefix("SBspike")` and send a 255-byte message, then a 256-byte one, by `C_ChatInfo.SendAddonMessage("SBspike", msg, "CHANNEL", id)`. Print each send's return value and every `CHAT_MSG_ADDON` received (prefix, length, channel, sender). Your own channel messages echo back, so one client can verify this.
  - `burst`: send 40 messages as fast as possible and print each return value (the `Enum.SendAddonMessageResult` value, or true/false) and receive times, to find the throttle.
  - `inst`: same as `chan`'s send, for running inside a dungeon.
  - `who`: print `UnitName("mouseover")`, `UnitName("target")`, `GetNormalizedRealmName()`, `UnitFullName("target")`, `UnitLevel("player")`, and whether `issecretvalue` exists.
  - `plates`: for each `C_NamePlate.GetNamePlates()`, print the unit token and `UnitName`, `UnitIsPlayer` (wrapped in `pcall`).
  - `lfg`: print whether `C_LFGList`, `LFGListFrame`, `PVEFrame`, `GroupFinderFrame` exist, and `C_LFGList.GetSearchResults` and `GetApplicants` if they do.
  - `menu`: print whether `Menu.ModifyMenu` exists and whether `UnitPopup_ShowMenu` exists.
  - `tip`: print whether `TooltipDataProcessor.AddTooltipPostCall` exists, and hook it (or `GameTooltip:HookScript("OnTooltipSetUnit")`) to add a test line.
  - `faction`: print the `CHAT_MSG_CHANNEL_JOIN` and roster events for `ScuttlebuttNet`, so a second player of the other faction can be seen joining or not.

- [ ] **Step 2: Copy it into the game and ask the user to run each check.** Deploy to `D:\World of Warcraft\_forever_\Interface\AddOns\ScuttlebuttSpike`. Ask the user to type the commands (never type into WoW without checking it has focus first). Read the results from a screenshot or the user's paste.

- [ ] **Step 3: Write `docs/spike-results.md`.** One section per check with the result and a decision: message size limit (expected 255), safe send rate (set `SEND_BUDGET` and `SEND_REFILL` in `Tunables.lua` to half the measured limit), whether channel messages arrive in instances, the tooltip hook to use, whether nameplate names are readable in and out of instances, the group finder API or "no group finder: Display drops that part", the menu API, and "faction split: unknown until a two-client test" if no second player was available.

- [ ] **Step 4: Remove the spike from the AddOns folder** (guarded path, `rm -rf "${A:?}/ScuttlebuttSpike"`). Keep it in the repo, excluded from packaging.

### Task 2: Test harness, Tunables, Names, Codec

**Files:**
- Create: `tests/run.py`, `tests/lib.lua`, `tests/test_names.lua`, `tests/test_codec.lua`
- Create: `Scuttlebutt/Tunables.lua`, `Scuttlebutt/Names.lua`, `Scuttlebutt/Codec.lua`

**Interfaces:**
- Produces:
  - `ns.Tunables` (all values in Global Constraints, plus `SEND_BUDGET`, `SEND_REFILL` from the spike) and `ns.Tunables.TAGS`, an array of `{ id = n, label = "...", good = bool }`: ids 1 to 8 are the good tags in spec order (Great Tank, Great Healer, Great DPS, Knows the Content, Friendly, Generous, Helpful Guide, Fair Looter), ids 9 to 14 the bad ones (Ninja Looter, Left Mid-Dungeon, Toxic, AFK Leecher, Pulls Everything, Scammer).
  - `ns.Names.Normalize(name: string, defaultRealm: string) -> string|nil`: `"Bob"` becomes `"Bob-<defaultRealm>"`; realm spaces and apostrophes removed and the realm lowercased (keys only; the UI shows the name part); first letter of the name upper case, the rest lower (UTF-8 safe: only change ASCII bytes); `nil` for empty or non-string input.
  - Record table: `{ target = "Name-Realm", author = "Name-Realm", vote = 1 | -1 | 0, tags = { id, ... } (0 to 3), time = integer seconds }`.
  - `ns.Codec.Encode(kind: "S"|"R"|"B", payload) -> { string, ... }`: for `"R"` and `"B"` the payload is an array of records, packed into as few messages as fit `MSG_MAX`; for `"S"` the payload is the summary table from `Store:Digest()`. Every message starts with the `PROTOCOL` version and the kind.
  - `ns.Codec.Decode(msg: string) -> kind, payload` or `nil, reason` on anything malformed. Never raises.

- [ ] **Step 1: Write `tests/run.py` and `tests/lib.lua`.** `run.py` reads `PYLIBS` from the environment, creates one `lua51.LuaRuntime`, loads `tests/lib.lua`, then for each test file creates a fresh `ns` table, loads the pure-logic addon files in `.toc` order through `loadstring(code)("Scuttlebutt", ns)`, exposes `ns` as a global, runs the test file, and prints `PASS name` or `FAIL name: message` per test and a final `N passed, M failed`. Exit code 1 on any failure. It also compiles every `.lua` under `Scuttlebutt/` with `loadstring` and fails on any syntax error. Optional argument: a single test file.

Run: `PYLIBS=<pylibs> "/c/Program Files/Python313/python.exe" tests/run.py`
Expected: `0 passed, 0 failed`, exit 0.

- [ ] **Step 2: Write failing tests.**

```lua
-- tests/test_names.lua
T("bare name gets the default realm", function()
	eq(ns.Names.Normalize("bob", "ArgentDawn"), "Bob-argentdawn")
end)
T("realm spaces and apostrophes removed", function()
	eq(ns.Names.Normalize("Bob-Argent Dawn", "X"), "Bob-argentdawn")
	eq(ns.Names.Normalize("Bob-Kel'Thuzad", "X"), "Bob-kelthuzad")
end)
T("same player, three spellings, one key", function()
	local a = ns.Names.Normalize("Bob", "ArgentDawn")
	eq(ns.Names.Normalize("Bob-ArgentDawn", "Other"), a)
	eq(ns.Names.Normalize("bob-argentdawn", "Other"), a)
end)
T("accented names untouched", function()
	eq(ns.Names.Normalize("Zoë", "Draenor"), "Zoë-draenor")
end)
T("bad input is nil", function()
	eq(ns.Names.Normalize("", "X"), nil)
	eq(ns.Names.Normalize(nil, "X"), nil)
end)

-- tests/test_codec.lua
local function rec(t, a, v, tags, time)
	return { target = t, author = a, vote = v, tags = tags or {}, time = time or 1700000000 }
end
T("records round-trip", function()
	local list = { rec("Bob-Realm", "Ann-Realm", 1, { 1, 5 }), rec("Zoë-Draenor", "Ann-Realm", -1, { 9, 10, 14 }), rec("Cy-Realm", "Dee-Realm", 0) }
	local msgs = ns.Codec.Encode("B", list)
	local back = {}
	for _, m in ipairs(msgs) do
		ok(#m <= ns.Tunables.MSG_MAX, "message too long")
		local kind, recs = ns.Codec.Decode(m)
		eq(kind, "B")
		for _, r in ipairs(recs) do back[#back + 1] = r end
	end
	eq(back, list)
end)
T("many records split across messages", function()
	local list = {}
	for i = 1, 200 do list[i] = rec("Target" .. i .. "-Realm", "Author" .. i .. "-Realm", 1, { 1 }) end
	local msgs = ns.Codec.Encode("R", list)
	ok(#msgs > 1)
	local n = 0
	for _, m in ipairs(msgs) do
		ok(#m <= ns.Tunables.MSG_MAX)
		local _, recs = ns.Codec.Decode(m)
		n = n + #recs
	end
	eq(n, 200)
end)
T("names are not plain text in messages", function()
	local m = ns.Codec.Encode("B", { rec("Bobbington-Realm", "Annabelle-Realm", 1) })[1]
	ok(not m:find("Bobbington", 1, true) and not m:find("Annabelle", 1, true))
end)
T("messages contain no NUL or pipe", function()
	local m = ns.Codec.Encode("B", { rec("Zoë-Draenor", "Ann-Realm", -1, { 14 }) })[1]
	ok(not m:find("%z") and not m:find("|", 1, true))
end)
T("garbage never raises", function()
	for _, junk in ipairs({ "", "x", "\255\255\255", string.rep("A", 255), "1B", "9B" .. string.rep("z", 40) }) do
		local okCall, kind = pcall(ns.Codec.Decode, junk)
		ok(okCall, "Decode raised on junk")
		eq(kind, nil)
	end
end)
T("truncated real message is rejected", function()
	local m = ns.Codec.Encode("B", { rec("Bob-Realm", "Ann-Realm", 1, { 1, 2 }) })[1]
	eq((ns.Codec.Decode(m:sub(1, #m - 3))), nil)
end)
T("summary round-trips", function()
	local s = { count = 12, buckets = { [0] = 1700000000, [5] = 1700000500 } }
	local kind, back = ns.Codec.Decode(ns.Codec.Encode("S", s)[1])
	eq(kind, "S")
	eq(back, s)
end)
```

`eq` compares tables deeply. The summary shape (`count`, `buckets` keyed by bucket index `0..SUMMARY_BUCKETS-1` with the newest time in each) is fixed here; add `SUMMARY_BUCKETS = 32` to Tunables.

- [ ] **Step 3: Run, expect failures** ("attempt to index field 'Names'" and similar).

- [ ] **Step 4: Implement `Tunables.lua`, `Names.lua`, `Codec.lua`.** Codec approach: numbers as fixed-width base-89 digits over printable ASCII excluding `|`; strings as a length digit then the bytes passed through a reversible byte transform that keeps bytes in 1..255 and never produces `|` (124); record tags as a count digit then ids. Decode checks every length against the remaining message and returns `nil, reason` on any mismatch, unknown kind or version other than `PROTOCOL`.

- [ ] **Step 5: Run, expect all pass.** Run: `PYLIBS=<pylibs> "/c/Program Files/Python313/python.exe" tests/run.py`. Expected: `12 passed, 0 failed`.

- [ ] **Step 6: Checkpoint.** Commit if the user has asked for commits.

### Task 3: Store

**Files:**
- Create: `Scuttlebutt/Store.lua`, `tests/test_store.lua`

**Interfaces:**
- Consumes: `ns.Tunables`, record table, `ns.Names`.
- Produces: `ns.Store.New(db: table) -> store` where `db` is the SavedVariables subtable (`db.records`, `db.notes` created if missing). Methods:
  - `store:Put(rec, sender: string, now: number) -> changed: boolean`. Keeps one record per `(author, target)`; newer `time` wins; a time more than `FUTURE_SLACK` past `now` is replaced by `now`. Sets a local `witnessed = true` when `sender == rec.author` (also when the record is unchanged but now witnessed; that counts as `changed`). Rejects records with `target == author`, bad votes, more than `MAX_TAGS` tags or unknown fields' types.
  - `store:About(target) -> { rec, ... }` all records about a player.
  - `store:ByAuthor(author) -> { rec, ... }`.
  - `store:Digest() -> { count, buckets }` (bucket = a stable string hash of `author .. target` modulo `SUMMARY_BUCKETS`).
  - `store:Missing(summary, limit) -> { rec, ... }` records in buckets where ours are newer than theirs, newest first, at most `limit`.
  - `store:Sample(n, random: function(lo, hi) -> int) -> { rec, ... }` random records for forwarding.
  - `store:Prune(now, keep: function(rec) -> boolean)` drops records with `time < now - FADE`, then the oldest down to `MAX_RECORDS`; never drops a record for which `keep(rec)` is true (own votes).
  - `store:SetNote(target, text|nil)`, `store:GetNote(target) -> string|nil`. Notes are never in `records` and never pruned.

- [ ] **Step 1: Write failing tests** in `tests/test_store.lua`: `newer replaces older` (two puts, `About` returns one record with the newer vote); `older is ignored` (`Put` returns false); `future time clamped` (`time = now + 3600` stored as `now`); `witnessed when author sends` (`Put(rec, "Ann-Realm")` with `rec.author == "Ann-Realm"` gives `witnessed == true`; forwarded by `"Cy-Realm"` gives false; then the author's own copy of the same record flips it to true and returns true); `self vote rejected`; `four tags rejected`; `digest matches equal stores` (two stores with the same records give equal digests); `missing finds only newer` (store A has a record B lacks; `A:Missing(B:Digest(), 50)` contains it and nothing B already has newer); `prune drops faded but keeps own` (record at `now - FADE - 1` with `keep` false is gone, with `keep` true stays); `prune caps count` (with `MAX_RECORDS` temporarily set to 10, 15 records leave 10, the oldest gone); `notes survive prune and are not records`.

- [ ] **Step 2: Run, expect failures.** Run: `... tests/run.py tests/test_store.lua`

- [ ] **Step 3: Implement `Store.lua`.** Records indexed by target then author (`db.records[target][author] = rec`) so `About` is direct; keep an author index in memory only, rebuilt on `New`.

- [ ] **Step 4: Run, expect all pass.**

- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 4: Guard (layer 1)

**Files:**
- Create: `Scuttlebutt/Guard.lua`, `tests/test_guard.lua`

**Interfaces:**
- Consumes: `ns.Tunables`.
- Produces: `ns.Guard.New(db: table) -> guard` (`db.history` = list of `{ vote, time }`, newest last, kept to `SOUR_WINDOW`; `db.dislikeDay`, `db.dislikeCount`; `db.sourUntil`; `db.chars` = set of this account's character keys). Methods:
  - `guard:AddCharacter(key)`.
  - `guard:CanVote(target, vote, ctx) -> ok: boolean, reason: string|nil` where `ctx = { me = key, level = n, eligible = bool, now = t }`. Reasons, checked in this order: `"self"` (target is any character in `db.chars`), `"level"` (`level < MIN_LEVEL`), `"absent"` (not `eligible`), and for `vote == -1` only: `"sour"` (`now < sourUntil`), `"cap"` (`DISLIKES_PER_DAY` reached today; day = `floor(now / 86400)`). Likes and clears skip the last two.
  - `guard:Record(vote, now)` updates history, the day count and, when more than `SOUR_RATIO` of the last `SOUR_WINDOW` votes are dislikes, sets `sourUntil = now + SOUR_PAUSE`.
  - `guard:AccountVote(store, target) -> rec|nil` the account's existing vote on `target` from any of `db.chars`, so Core can replace it (one vote per account).

- [ ] **Step 1: Write failing tests:** `self vote refused` (`CanVote("Me-R", 1, {me="Me-R",...})` gives `false, "self"`; also for an alt added with `AddCharacter`); `level 8 refused, level 9 allowed`; `absent refused`; `16th dislike in a day refused with "cap"` and allowed again the next day; `likes unlimited` (100 likes all allowed); `sour streak` (25 dislikes and 5 likes across days, without hitting the cap, then a dislike gives `"sour"`; a like is still allowed; after `SOUR_PAUSE` the dislike is allowed); `account vote found from an alt` (a store holding a vote by `"Alt-R"` on `"Bob-R"`, with both characters added, returns it).

- [ ] **Step 2: Run, expect failures.** Run: `... tests/run.py tests/test_guard.lua`
- [ ] **Step 3: Implement `Guard.lua`.**
- [ ] **Step 4: Run, expect all pass.**
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 5: Trust and scoring (layer 2)

**Files:**
- Create: `Scuttlebutt/Trust.lua`, `tests/test_trust.lua`

**Interfaces:**
- Consumes: `store:About`, `store:ByAuthor`, `ns.Tunables`.
- Produces: `ns.Trust.New(store, db) -> trust` (`db.senders` for the damage limit). Methods:
  - `trust:IsGrump(author, now) -> boolean`: from the author's **witnessed** votes only, with `time >= now - GRUMP_WEAR_OFF`; true when there are at least `GRUMP_MIN_VOTES` and dislikes are at least `GRUMP_RATIO` of them. (Wear-off falls out of the window: two weeks without that behavior and they drop below the line.)
  - `trust:Weight(rec, now) -> number`: `1` if witnessed else `UNWITNESSED_WEIGHT`; times `0` for a dislike from a Grump (the spec's "down to nothing"; a sliding scale is left to the builder only if tests still pass).
  - `trust:Score(target, opts) -> { likes = int, dislikes = int, tags = { [id] = int }, circle = int, unconfirmed = int, grump = boolean }` with `opts = { now, excludeGrumps = bool, inCircle = function(key) -> bool }`. Likes and dislikes are weighted sums rounded to the nearest integer; with `excludeGrumps` every vote from a Grump is skipped. `tags` counts each record's tags at the same weight, rounded. `circle` counts records by authors in the circle. `unconfirmed` counts unwitnessed records. `grump` is `IsGrump(target, now)`.
  - `trust:NoteForwarded(sender, rec, now)` and `trust:NoteWitnessed(author, now)`; `trust:SenderBlocked(sender, now) -> boolean` true when the sender has forwarded at least `FORGE_MIN = 30` records whose authors have not been seen sending in `FORGE_WINDOW = 7 * 86400` and that share is above `FORGE_RATIO = 0.9`. Blocked senders' forwarded records are ignored for `FORGE_BLOCK = 86400`. Add these four to Tunables as the builder's starting guesses.

- [ ] **Step 1: Write failing tests:** `witnessed counts 1, forwarded 0.25` (4 forwarded likes and 1 witnessed like give `likes == 2`); `grump needs witnessed votes` (25 forwarded dislikes by Ann give `IsGrump == false`; 25 witnessed dislikes give true); `framing fails` (a forger forwards 40 dislikes in Ann's name: Ann stays not a Grump and the 40 votes add at most 10 dislikes); `grump dislikes count zero` (a Grump's dislike on Bob does not change Bob's dislikes; their like still counts); `excludeGrumps drops likes too`; `grump wears off` (votes older than `GRUMP_WEAR_OFF` no longer count toward Grump status); `score shows grump tag for the target`; `circle and unconfirmed counted`; `tags weighted and rounded`; `forger sender blocked` (a sender that forwards 30 records from never-seen authors is blocked; one whose forwarded authors later send their own batches is not).

- [ ] **Step 2: Run, expect failures.**
- [ ] **Step 3: Implement `Trust.lua`.** Cache `IsGrump` per author per call to `Score` only; no long-lived cache (stores are small enough; revisit only if the simulation says it's slow).
- [ ] **Step 4: Run, expect all pass.**
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 6: Sync protocol and gossip simulation

**Files:**
- Create: `Scuttlebutt/Sync.lua`, `tests/test_sync.lua`, `tests/test_sim.lua`

**Interfaces:**
- Consumes: Codec, Store, Trust.
- Produces: `ns.Sync.New(env) -> sync` with `env = { me = key, store, trust, send = function(msg), now = function(), random = function(lo, hi), after = function(seconds, fn), ownVote = function(rec) -> bool }`. Methods:
  - `sync:Start()` sends one `"S"` summary.
  - `sync:OnMessage(sender, msg)`: decodes; ignores what fails to decode; on `"S"` schedules a reply after `random(0, REPLY_DELAY_MAX)` seconds, cancelled if `REPLY_LIMIT` other `"R"` replies to that sender's summary are seen first (replies name the summary's sender as the first record field, or carry it in the message header; builder's choice, but it must be tested); on `"R"`/`"B"` calls `store:Put(rec, sender, now)` for each record not from a blocked sender, and the trust bookkeeping.
  - `sync:Vote(rec)` stores the own vote (witnessed) and queues it for the next trickle.
  - `sync:Tick()` called every `TRICKLE_EVERY = 20` seconds: sends one `"B"` message mixing queued own votes (at most 2) with `random`-sampled forwards to fill it, shuffled; also queues own votes whose `time` is older than `REFRESH_EVERY` with a fresh `time` (the refresh). Add `TRICKLE_EVERY` to Tunables.
  - `sync:Stats() -> { sent = int, received = int }`.

- [ ] **Step 1: Write failing unit tests** in `tests/test_sync.lua`, with a fake env (a manual clock, a scripted `random`, `after` collecting callbacks): `start sends a summary`; `reply after delay`; `reply cancelled after three others`; `records from a batch are stored witnessed only for their author`; `junk message ignored without error`; `own vote goes out within one tick`; `own vote never alone` (when the store has other records, a batch with an own vote has at least 3 other records); `old own vote refreshed` (an own vote 15 days old is re-sent with a new time).

- [ ] **Step 2: Write failing simulation tests** in `tests/test_sim.lua`: a bus that delivers each sent message to every connected sync (including the sender, as the game does) and counts messages per sender per second; 100 clients on one virtual clock.
  - `news spreads`: client 1 votes on a target; after 2 virtual hours at least 90 of the 100 clients see `likes >= 1` for that target (unconfirmed counts too). Print the time when 50% and 90% had it.
  - `login catch-up`: a client joins late with an empty store and holds at least 80% of the network's records within 10 virtual minutes.
  - `throttle respected`: no client ever sends more than `SEND_BUDGET` messages in a burst or exceeds `SEND_REFILL` per second over a minute.
  - `login storm`: 100 clients start at the same second; total replies to each summary never exceed `REPLY_LIMIT + 2` (two may race).
  - `troll flood`: one client casts 200 dislikes through `Vote` with Layer 1 bypassed; within 2 hours every honest client sees it as a Grump and none of the 200 targets shows a dislike from it.
  - `forger framing`: one client forwards 300 fake dislikes in the names of 10 honest clients; no honest client becomes a Grump anywhere, and the forger is blocked by most clients.
  - `faction split`: two buses (Alliance, Horde); a vote on one never reaches the other.

- [ ] **Step 3: Run, expect failures.** Run: `... tests/run.py tests/test_sync.lua` then `tests/test_sim.lua`.
- [ ] **Step 4: Implement `Sync.lua`.** If `news spreads` misses 90% in 2 hours with a legal send rate, report the measured spread to the user instead of raising the rate past the throttle.
- [ ] **Step 5: Run, expect all pass.** The sim should finish in under a minute; if it doesn't, shrink to 50 clients and say so.
- [ ] **Step 6: Checkpoint.** Commit if asked.

### Task 7: WoW wiring: Core, Channel, Presence

**Files:**
- Create: `Scuttlebutt/Scuttlebutt.toc`, `Scuttlebutt/Core.lua`, `Scuttlebutt/Channel.lua`, `Scuttlebutt/Presence.lua`

**Interfaces:**
- Consumes: everything above, `docs/spike-results.md`.
- Produces:
  - `ns.Channel.Start(onMessage: function(sender, msg))`, `ns.Channel.Send(msg)` (queued, sent within `SEND_BUDGET`/`SEND_REFILL`, held while `IsInInstance()`), `ns.Channel.Stop()`.
  - `ns.Presence.IsEligible(key, now) -> boolean` (seen within `ONLINE_RECENT` through target, mouseover, nameplate, group or raid roster, guild roster online flag, whisper, say/yell/channel chat; or grouped within `RECENT_GROUP`), `ns.Presence.InCircle(key) -> boolean` (friends list or guild), `ns.Presence.Seen(key, now)` called by those events.
  - `ns.App` with `ns.App.store`, `ns.App.trust`, `ns.App.guard`, `ns.App.sync`, `ns.App.Score(key) -> score table` (calls `trust:Score` with the saved settings), `ns.App.Vote(key, vote, tags) -> ok, reason`, `ns.App.Settings.Get(name)`, `ns.App.Settings.Set(name, value)` firing `ns.App.OnSettingChanged(name)` callbacks.
  - Settings keys: `tooltip`, `groupFinder`, `nameplates`, `excludeGrumps`, `network`, `minimapAngle`, `minimapHidden`.
  - Slash: `/scuttle` and `/scuttlebutt`; `/scuttle <name>` opens the player file; `/scuttle status` prints records, peers heard in the last hour, messages sent and received, whether the channel is joined, and the level gate state.

- [ ] **Step 1: Write the `.toc`:** `## Interface: 16001`, `## Title: Scuttlebutt`, `## Notes: What the realm says about other players: likes, dislikes, tags and private notes, spread by word of mouth.`, `## Author: PxPerfectMike`, `## Version: 0.1.0`, `## SavedVariables: ScuttlebuttDB`, `## X-License: MIT`, files in the order of the File structure table.
- [ ] **Step 2: Implement `Channel.lua`, `Presence.lua`, `Core.lua`** following the spike's decisions. The network side (channel, voting, syncing) starts only at level 9 or above and with `network` on; it starts automatically on `PLAYER_LEVEL_UP` reaching 9. Private notes work at any level. `ns.App.Vote` normalizes the key, checks `guard:CanVote` with `eligible = Presence.IsEligible`, replaces an account vote from another character (`guard:AccountVote`), then `sync:Vote`.
- [ ] **Step 3: Run the suite.** `... tests/run.py` must still pass and compile the new files.
- [ ] **Step 4: In-game check (one client).** Deploy, ask the user to `/reload`, then `/scuttle status`: channel joined, the channel not visible in any chat tab, own summary counted as sent and received (echo). `/scuttle Somename` on a nearby player prints eligible, and on a far-away name prints not eligible. No Lua errors (ask the user to keep `/console scriptErrors 1` on).
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 8: Player file window and right-click entry

**Files:**
- Create: `Scuttlebutt/PlayerFile.lua`
- Modify: `Scuttlebutt/Menu.lua` (create here with only the right-click entry; Task 10 adds the rest)

**Interfaces:**
- Consumes: `ns.App.Score`, `ns.App.Vote`, `ns.App.store:GetNote/SetNote`, `ns.Tunables.TAGS`, `ns.Guard` reasons.
- Produces: `ns.PlayerFile.Open(key)`, `ns.PlayerFile.Refresh()` (called by Core when records about the open player change).

- [ ] **Step 1: Build the window:** player name; "35 / 7" (green and red); "based on what reached you"; "N from your circle", "N unconfirmed"; "Known Grump" if set; like and dislike buttons showing the current vote; a tag picker allowing up to 3 (bad tags drawn in red, good in green); a multi-line private note box that saves as you type. Movable, closes with Escape. No names of voters anywhere.
- [ ] **Step 2: Disabled states with these exact lines:** `"self"`: "You can't rate yourself or your own characters."; `"level"`: "Reach level 9 to rate players."; `"absent"`: "You can rate players who are online near you, or who you grouped with in the last day."; `"cap"`: "Easy there. Even the town crier needs a break."; `"sour"`: "You've been pretty sour lately. Dislikes are paused for a day."
- [ ] **Step 3: Right-click entry** "Scuttlebutt" on player unit menus (and chat name menus) through the API the spike chose, opening `PlayerFile.Open`.
- [ ] **Step 4: In-game check:** open a file on a nearby player, like, add two tags, write a note, `/reload`, reopen: all kept. Try a third and fourth tag (fourth refused). Open your own file: buttons disabled with the "self" line.
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 9: Tooltip and nameplates

**Files:**
- Create: `Scuttlebutt/Display.lua`

**Interfaces:**
- Consumes: `ns.App.Score`, `ns.App.store:GetNote`, settings `tooltip` and `nameplates`.
- Produces: `ns.Display.FormatScore(score) -> string` (`"|cff40ff4035|r / |cffff404007|r"`; pure, add a test `format score colors` in `tests/test_trust.lua` style under a new `tests/test_display.lua`, with Display's pure function loaded by the runner), `ns.Display.Refresh()`.

- [ ] **Step 1: Test `FormatScore`** (35/7 gives the string above; 0/0 gives `"No word yet"`). Run, fail, implement, pass.
- [ ] **Step 2: Tooltip:** for player units only, add "Scuttlebutt: 35 / 7", the top 3 tags by count ("Great Tank, Friendly"), "Known Grump" in orange if set, and the private note in gray, truncated to 80 characters. Skips silently when the unit's name is a hidden value.
- [ ] **Step 3: Nameplates:** a small font string under the name of player nameplates showing `FormatScore` when there is at least one vote. Updates on `NAME_PLATE_UNIT_ADDED` and when records change. Off inside instances if the spike found names hidden there. Settings text: "To see scores on friendly players, turn on friendly player nameplates (Options, Nameplates)."
- [ ] **Step 4: In-game check:** hover a player you voted on; check the nameplate; toggle both settings off and on with `/scuttle tooltip` and `/scuttle nameplates` (add these slash toggles).
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 10: Group finder, settings panel, minimap button

**Files:**
- Modify: `Scuttlebutt/Display.lua`, `Scuttlebutt/Menu.lua`

**Interfaces:**
- Consumes: spike results for the group finder; `ns.App.Settings`.
- Produces: nothing new for other tasks.

- [ ] **Step 1: Group finder** per the spike: add `FormatScore` next to applicants and listing leaders. If the spike found no usable group finder, skip, remove the `groupFinder` setting, and note it in the README and the hand-off to the user.
- [ ] **Step 2: Settings panel** (Blizzard settings, `Settings.RegisterCanvasLayoutCategory` or what the spike shows exists): checkboxes for tooltip, group finder, nameplates, Exclude Grump votes ("Hide votes from Known Grumps"), network ("Share and receive votes"), minimap button.
- [ ] **Step 3: Minimap button** like Starfall Trail's (`C:\repos\starfall-trail\StarfallTrail\Menu.lua`, same drag-around-the-rim behavior and shape table): left-click opens the settings, tooltip shows record count and peers heard in the last hour.
- [ ] **Step 4: In-game check** of every toggle; Exclude Grump votes changes nothing visible without Grumps, so check it through `/scuttle status` printing the current setting.
- [ ] **Step 5: Checkpoint.** Commit if asked.

### Task 11: Packaging and docs

**Files:**
- Create: `tools/package.sh`, `README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`

- [ ] **Step 1: `tools/package.sh`** modeled on `C:\repos\starfall-trail\tools\package.sh`: version from `Scuttlebutt/Scuttlebutt.toc`, CHANGELOG entry required, runs `tests/run.py` and stops on failure, zips only `Scuttlebutt/` into `dist/Scuttlebutt-<version>.zip`. `.gitignore`: `dist/`.
- [ ] **Step 2: README** (what it does, how word of mouth works, "names aren't shown", what it can't do: no score inside instances' traffic, faction split if confirmed, alts on other paid accounts), **CHANGELOG** `## 0.1.0`, **LICENSE** MIT 2026 PxPerfectMike.
- [ ] **Step 3: Run** `tools/package.sh`. Expected: tests pass and `wrote dist/Scuttlebutt-0.1.0.zip`.
- [ ] **Step 4: Tell the user** what's ready, and ask before any GitHub repo, CurseForge project or second-client test.
- [ ] **Step 5: Checkpoint.** Commit if asked.
