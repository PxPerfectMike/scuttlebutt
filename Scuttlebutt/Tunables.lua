-- Scuttlebutt: every tunable number in one place, plus the tag list.

local _, ns = ...

local DAY = 86400

ns.Tunables = {
	MIN_LEVEL = 9,
	DISLIKES_PER_DAY = 15,
	SOUR_WINDOW = 30, -- last N votes checked for a sour streak
	SOUR_RATIO = 0.8,
	SOUR_PAUSE = DAY,
	GRUMP_MIN_VOTES = 20,
	GRUMP_RATIO = 0.8,
	GRUMP_WEAR_OFF = 14 * DAY,
	RECENT_GROUP = DAY,
	ONLINE_RECENT = 300,
	UNWITNESSED_WEIGHT = 0.25,
	REFRESH_EVERY = 14 * DAY,
	FADE = 90 * DAY,
	MAX_RECORDS = 50000,
	MAX_TAGS = 3,
	REPLY_DELAY_MAX = 30,
	REPLY_LIMIT = 3,
	REPLY_RECORDS = 60, -- records per reply to one summary
	MSG_MAX = 255,
	PROTOCOL = 1,
	FUTURE_SLACK = 600,
	SUMMARY_BUCKETS = 32,
	TRICKLE_EVERY = 20,
	-- Sender damage limit (forwarders whose records never get witnessed).
	FORGE_MIN = 30,
	FORGE_WINDOW = 7 * DAY,
	FORGE_RATIO = 0.9,
	FORGE_BLOCK = DAY,
	FORGE_DENIALS = 5, -- forwards denied by their supposed author within FORGE_WINDOW
	DENY_GRACE = DAY, -- no denials for this long after a new database (a reinstall forgets own votes)
	FORGE_FRESH = 3600, -- only votes cast this recently count as ghosts (forgers stamp "now")
	MAX_PER_AUTHOR = 1500, -- distinct players one author can have votes about
	-- Send queue. The game allows a burst of 10 (measured); stay well under it, since other
	-- addons may share the limit.
	SEND_BUDGET = 5,
	SEND_REFILL = 0.5,
	SEND_TRIES = 20, -- a message the game keeps refusing is dropped after this many tries
	DENY_PER_MINUTE = 60,
}

ns.Tunables.TAGS = {
	{ id = 1, label = "Great Tank", good = true },
	{ id = 2, label = "Great Healer", good = true },
	{ id = 3, label = "Great DPS", good = true },
	{ id = 4, label = "Knows the Content", good = true },
	{ id = 5, label = "Friendly", good = true },
	{ id = 6, label = "Generous", good = true },
	{ id = 7, label = "Helpful Guide", good = true },
	{ id = 8, label = "Fair Looter", good = true },
	{ id = 9, label = "Ninja Looter", good = false },
	{ id = 10, label = "Left Mid-Dungeon", good = false },
	{ id = 11, label = "Toxic", good = false },
	{ id = 12, label = "AFK Leecher", good = false },
	{ id = 13, label = "Pulls Everything", good = false },
	{ id = 14, label = "Scammer", good = false },
}
