-- Scuttlebutt: the vote records this player has heard, plus private notes.
--
-- db.records[target][author] = { target, author, vote, tags, time, witnessed }
-- One record per author per target; the newest time wins. "witnessed" is local only: true when
-- this client received the record from its own author (the game proves who sent a message).
-- "via" (also local) names who passed on an unwitnessed record, so a forger can be blamed.
-- db.notes[target] = text. Notes never leave this computer and are never pruned.

local _, ns = ...

local Store = {}
Store.__index = Store
ns.Store = Store

local T = ns.Tunables

local function Hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 2147483647
	end
	return h
end

local function Bucket(rec)
	return Hash(rec.author .. "\1" .. rec.target) % T.SUMMARY_BUCKETS
end

function Store.New(db)
	db.records = db.records or {}
	db.notes = db.notes or {}
	local self = setmetatable({ db = db, byAuthor = {}, authorCount = {}, count = 0 }, Store)
	for _, byTarget in pairs(db.records) do
		for author, rec in pairs(byTarget) do
			self:Index(author, rec)
		end
	end
	return self
end

function Store:Index(author, rec)
	local list = self.byAuthor[author]
	if not list then
		list = {}
		self.byAuthor[author] = list
	end
	if not list[rec.target] then
		self.count = self.count + 1
		self.authorCount[author] = (self.authorCount[author] or 0) + 1
	end
	list[rec.target] = rec
	self.list = nil
end

function Store:Unindex(rec)
	local byTarget = self.db.records[rec.target]
	byTarget[rec.author] = nil
	if next(byTarget) == nil then
		self.db.records[rec.target] = nil
	end
	local list = self.byAuthor[rec.author]
	list[rec.target] = nil
	if next(list) == nil then
		self.byAuthor[rec.author] = nil
	end
	self.count = self.count - 1
	self.authorCount[rec.author] = self.authorCount[rec.author] - 1
	self.list = nil
end

local function Valid(rec)
	if type(rec) ~= "table" or type(rec.target) ~= "string" or type(rec.author) ~= "string" then
		return false
	end
	if rec.target == rec.author then
		return false
	end
	-- Only the one spelling Names.Normalize produces, so one player is one key.
	if ns.Names.Normalize(rec.target) ~= rec.target or ns.Names.Normalize(rec.author) ~= rec.author then
		return false
	end
	if rec.vote ~= -1 and rec.vote ~= 0 and rec.vote ~= 1 then
		return false
	end
	if type(rec.time) ~= "number" or rec.time < 0 then
		return false
	end
	local tags = rec.tags or {}
	if type(tags) ~= "table" or #tags > T.MAX_TAGS then
		return false
	end
	for _, id in ipairs(tags) do
		if type(id) ~= "number" or id < 1 or id > 92 or id % 1 ~= 0 then
			return false
		end
	end
	return true
end

-- Stores rec heard from sender at time now. Returns true when anything changed.
function Store:Put(rec, sender, now)
	if not Valid(rec) then
		return false
	end
	local time = rec.time
	if time > now + T.FUTURE_SLACK then
		time = now
	end
	local byTarget = self.db.records[rec.target]
	local old = byTarget and byTarget[rec.author]
	local fromAuthor = sender == rec.author
	if not old and (self.authorCount[rec.author] or 0) >= T.MAX_PER_AUTHOR then
		return false -- one author can't fill the store
	end
	if old then
		if time < old.time then
			return false
		end
		if time == old.time then
			if fromAuthor and not old.witnessed then
				old.witnessed = true
				old.via = nil
				return true
			end
			return false
		end
	end
	if not byTarget then
		byTarget = {}
		self.db.records[rec.target] = byTarget
	end
	local tags = {}
	for i, id in ipairs(rec.tags or {}) do
		tags[i] = id
	end
	local copy = { target = rec.target, author = rec.author, vote = rec.vote, tags = tags, time = time, witnessed = fromAuthor }
	if not fromAuthor then
		copy.via = sender
	end
	byTarget[rec.author] = copy
	self:Index(rec.author, copy)
	return true
end

function Store:Get(target, author)
	local byTarget = self.db.records[target]
	return byTarget and byTarget[author]
end

function Store:About(target)
	local out = {}
	for _, rec in pairs(self.db.records[target] or {}) do
		out[#out + 1] = rec
	end
	return out
end

function Store:ByAuthor(author)
	local out = {}
	for _, rec in pairs(self.byAuthor[author] or {}) do
		out[#out + 1] = rec
	end
	return out
end

function Store:All()
	if not self.list then
		local list = {}
		for _, byTarget in pairs(self.db.records) do
			for _, rec in pairs(byTarget) do
				list[#list + 1] = rec
			end
		end
		self.list = list
	end
	return self.list
end

function Store:Digest()
	local buckets = {}
	for _, rec in ipairs(self:All()) do
		local b = Bucket(rec)
		if not buckets[b] or rec.time > buckets[b] then
			buckets[b] = rec.time
		end
	end
	return { count = self.count, buckets = buckets }
end

-- Records in buckets where this store has something newer than the summary, newest first.
function Store:Missing(summary, limit)
	local theirs = summary.buckets or {}
	local out = {}
	for _, rec in ipairs(self:All()) do
		local t = theirs[Bucket(rec)]
		if not t or rec.time > t then
			out[#out + 1] = rec
		end
	end
	table.sort(out, function(a, b)
		return a.time > b.time
	end)
	for i = #out, limit + 1, -1 do
		out[i] = nil
	end
	return out
end

-- Up to n distinct random records. random(lo, hi) returns an integer in lo..hi.
function Store:Sample(n, random)
	local all = self:All()
	local picked, used = {}, {}
	local total = #all
	n = math.min(n, total)
	-- Partial Fisher-Yates over a sparse swap map, so the shared list isn't reordered.
	for i = 1, n do
		local j = random(i, total)
		local vi, vj = used[i] or i, used[j] or j
		used[j] = vi
		used[i] = vj
		picked[i] = all[vj]
	end
	return picked
end

function Store:Remove(rec)
	if self:Get(rec.target, rec.author) == rec then
		self:Unindex(rec)
	end
end

-- Moves forwarded records whose author is a short name of the client that sent them
-- (isShort(author, via)) to that client's own key, as witnessed votes. Where the full key
-- already has a newer vote on the same target, the short copy is just dropped.
function Store:AdoptShortNames(isShort, now)
	for _, rec in ipairs(self:All()) do
		if rec.via and isShort(rec.author, rec.via) then
			self:Remove(rec)
			self:Put({ target = rec.target, author = rec.via, vote = rec.vote, tags = rec.tags, time = rec.time }, rec.via, math.max(now, rec.time))
		end
	end
end

-- Drops faded records, then the oldest past MAX_RECORDS. keep(rec) protects own votes.
function Store:Prune(now, keep)
	local cutoff = now - T.FADE
	local candidates = {}
	for _, rec in ipairs(self:All()) do
		if not keep(rec) then
			candidates[#candidates + 1] = rec
		end
	end
	local remaining = {}
	for _, rec in ipairs(candidates) do
		if rec.time < cutoff then
			self:Unindex(rec)
		else
			remaining[#remaining + 1] = rec
		end
	end
	local excess = self.count - T.MAX_RECORDS
	if excess > 0 then
		table.sort(remaining, function(a, b)
			return a.time < b.time
		end)
		for i = 1, math.min(excess, #remaining) do
			self:Unindex(remaining[i])
		end
	end
end

function Store:SetNote(target, text)
	if text == "" then
		text = nil
	end
	self.db.notes[target] = text
end

function Store:GetNote(target)
	return self.db.notes[target]
end
