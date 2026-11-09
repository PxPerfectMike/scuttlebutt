-- Scuttlebutt: layer 1 of the troll guard, run by the voter's own client.
-- Level gate, "online now or recently grouped", no votes on your own characters, a daily dislike
-- cap and a pause after a sour streak. A modified client can skip all of this; layer 2 (Trust)
-- covers that.

local _, ns = ...

local Guard = {}
Guard.__index = Guard
ns.Guard = Guard

local T = ns.Tunables

-- db is account-wide saved data: history, dislikeDay, dislikeCount, sourUntil, chars.
function Guard.New(db)
	db.history = db.history or {}
	db.chars = db.chars or {}
	db.dislikeCount = db.dislikeCount or 0
	db.sourUntil = db.sourUntil or 0
	return setmetatable({ db = db }, Guard)
end

function Guard:AddCharacter(key)
	self.db.chars[key] = true
end

function Guard:IsMine(key)
	return self.db.chars[key] == true
end

local function Day(now)
	return math.floor(now / 86400)
end

function Guard:DislikesToday(now)
	if self.db.dislikeDay ~= Day(now) then
		return 0
	end
	return self.db.dislikeCount
end

-- ctx = { me, level, eligible, now }. Returns true, or false and a reason:
-- "self", "level", "absent", "sour", "cap".
function Guard:CanVote(target, vote, ctx)
	if target == ctx.me or self:IsMine(target) then
		return false, "self"
	end
	if (ctx.level or 0) < T.MIN_LEVEL then
		return false, "level"
	end
	if not ctx.eligible then
		return false, "absent"
	end
	if vote == -1 then
		if ctx.now < self.db.sourUntil then
			return false, "sour"
		end
		if self:DislikesToday(ctx.now) >= T.DISLIKES_PER_DAY then
			return false, "cap"
		end
	end
	return true
end

-- Call after a vote is cast. Clears (vote 0) don't count.
function Guard:Record(vote, now)
	if vote == 0 then
		return
	end
	local db = self.db
	if vote == -1 then
		if db.dislikeDay ~= Day(now) then
			db.dislikeDay = Day(now)
			db.dislikeCount = 0
		end
		db.dislikeCount = db.dislikeCount + 1
	end
	local history = db.history
	history[#history + 1] = vote
	while #history > T.SOUR_WINDOW do
		table.remove(history, 1)
	end
	if #history >= T.SOUR_WINDOW then
		local dislikes = 0
		for _, v in ipairs(history) do
			if v == -1 then
				dislikes = dislikes + 1
			end
		end
		if dislikes / #history > T.SOUR_RATIO then
			db.sourUntil = now + T.SOUR_PAUSE
		end
	end
end

-- Every vote other characters on this account cast on target (one vote per account).
function Guard:AccountVotes(store, target, me)
	local out = {}
	for key in pairs(self.db.chars) do
		if key ~= me then
			local rec = store:Get(target, key)
			if rec then
				out[#out + 1] = rec
			end
		end
	end
	return out
end

-- True when changing current (a record or nil) to vote and tags only takes something away:
-- no new like or dislike and no new tag. Removals skip the eligibility rules.
function Guard.IsRemoval(current, vote, tags)
	local currentVote = current and current.vote or 0
	if vote ~= 0 and vote ~= currentVote then
		return false
	end
	local had = {}
	for _, id in ipairs(current and current.tags or {}) do
		had[id] = true
	end
	for _, id in ipairs(tags or {}) do
		if not had[id] then
			return false
		end
	end
	return true
end

-- The vote any character on this account already cast on target, if one exists.
function Guard:AccountVote(store, target)
	for key in pairs(self.db.chars) do
		local rec = store:Get(target, key)
		if rec then
			return rec
		end
	end
	return nil
end
