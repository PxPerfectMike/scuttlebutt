-- Scuttlebutt: layer 2 of the troll guard and the score shown to the player.
--
-- A vote counts fully when its author's own client sent it to us ("witnessed"); a vote heard
-- only secondhand counts UNWITNESSED_WEIGHT. Grump status is judged from witnessed votes only,
-- so nobody can be framed by forwarded fakes. A Grump's dislikes count for nothing.
-- Senders that keep forwarding votes from authors who are never seen sending are ignored for a
-- while (the damage limit for forgers).

local _, ns = ...

local Trust = {}
Trust.__index = Trust
ns.Trust = Trust

local T = ns.Tunables
local FORWARD_KEEP = 200 -- forwards remembered per sender

-- db: saved table for forwards (db.forwards[sender] = list of { author, time }), when each
-- author was last seen sending (db.seen[author] = time) and blocks (db.blocked[sender] = until).
function Trust.New(store, db)
	db.forwards = db.forwards or {}
	db.seen = db.seen or {}
	db.blocked = db.blocked or {}
	db.denied = db.denied or {}
	return setmetatable({ store = store, db = db }, Trust)
end

function Trust:IsGrump(author, now)
	local since = now - T.GRUMP_WEAR_OFF
	local total, bad = 0, 0
	for _, rec in ipairs(self.store:ByAuthor(author)) do
		if rec.witnessed and rec.vote ~= 0 and rec.time >= since then
			total = total + 1
			if rec.vote == -1 then
				bad = bad + 1
			end
		end
	end
	return total >= T.GRUMP_MIN_VOTES and bad / total >= T.GRUMP_RATIO
end

local function Round(x)
	return math.floor(x + 0.5)
end

-- opts = { now, excludeGrumps, inCircle(key) }.
function Trust:Score(target, opts)
	local now = opts.now
	local grumps = {}
	local function Grump(author)
		local g = grumps[author]
		if g == nil then
			g = self:IsGrump(author, now)
			grumps[author] = g
		end
		return g
	end
	local likes, dislikes, tags = 0, 0, {}
	local circle, unconfirmed = 0, 0
	for _, rec in ipairs(self.store:About(target)) do
		local grump = Grump(rec.author)
		if not (grump and opts.excludeGrumps) then
			local w = rec.witnessed and 1 or T.UNWITNESSED_WEIGHT
			if rec.vote == 1 then
				likes = likes + w
			elseif rec.vote == -1 and not grump then
				dislikes = dislikes + w
			end
			for _, id in ipairs(rec.tags) do
				tags[id] = (tags[id] or 0) + w
			end
			if opts.inCircle and opts.inCircle(rec.author) then
				circle = circle + 1
			end
			if not rec.witnessed then
				unconfirmed = unconfirmed + 1
			end
		end
	end
	local rounded = {}
	for id, w in pairs(tags) do
		local n = Round(w)
		if n > 0 then
			rounded[id] = n
		end
	end
	return {
		likes = Round(likes),
		dislikes = Round(dislikes),
		tags = rounded,
		circle = circle,
		unconfirmed = unconfirmed,
		grump = self:IsGrump(target, now),
	}
end

-- Sync calls this for every record a sender passes on in a batch that isn't its own. Only votes
-- cast in the last FORGE_FRESH seconds can count as ghosts: a forger has to stamp them fresh,
-- while honest relays mostly pass on older votes from players who are offline.
function Trust:NoteForwarded(sender, rec, now)
	local list = self.db.forwards[sender]
	if not list then
		list = {}
		self.db.forwards[sender] = list
	end
	list[#list + 1] = { rec.author, now, rec.time >= now - T.FORGE_FRESH }
	if #list > FORWARD_KEEP then
		table.remove(list, 1)
	end
end

-- Sync calls this whenever a player's own client sends anything.
function Trust:NoteWitnessed(author, now)
	self.db.seen[author] = now
end

-- Sync calls this when `author` denies a record that `sender` passed on to us. It takes
-- FORGE_DENIALS different authors to block a sender, so one liar can't frame a relay.
function Trust:NoteDenied(sender, author, now)
	local list = self.db.denied[sender]
	if not list then
		list = {}
		self.db.denied[sender] = list
	end
	list[#list + 1] = { author, now }
	if #list > FORWARD_KEEP then
		table.remove(list, 1)
	end
end

function Trust:SenderBlocked(sender, now)
	if (self.db.blocked[sender] or 0) > now then
		return true
	end
	local since = now - T.FORGE_WINDOW
	local authors, denials = {}, 0
	for _, d in ipairs(self.db.denied[sender] or {}) do
		if d[2] >= since and not authors[d[1]] then
			authors[d[1]] = true
			denials = denials + 1
		end
	end
	if denials >= T.FORGE_DENIALS then
		self.db.blocked[sender] = now + T.FORGE_BLOCK
		return true
	end
	local total, ghosts = 0, 0
	for _, f in ipairs(self.db.forwards[sender] or {}) do
		if f[2] >= since then
			total = total + 1
			if f[3] and (self.db.seen[f[1]] or 0) < since then
				ghosts = ghosts + 1
			end
		end
	end
	if total >= T.FORGE_MIN and ghosts / total > T.FORGE_RATIO then
		self.db.blocked[sender] = now + T.FORGE_BLOCK
		return true
	end
	return false
end

-- Drops bookkeeping older than FORGE_WINDOW and expired blocks, so saved data stays small.
function Trust:Prune(now)
	local since = now - T.FORGE_WINDOW
	local function Trim(tbl, timeIndex)
		for key, list in pairs(tbl) do
			local keep = {}
			for _, entry in ipairs(list) do
				if entry[timeIndex] >= since then
					keep[#keep + 1] = entry
				end
			end
			tbl[key] = #keep > 0 and keep or nil
		end
	end
	Trim(self.db.forwards, 2)
	Trim(self.db.denied, 2)
	for author, t in pairs(self.db.seen) do
		if t < since then
			self.db.seen[author] = nil
		end
	end
	for sender, untilTime in pairs(self.db.blocked) do
		if untilTime <= now then
			self.db.blocked[sender] = nil
		end
	end
end
