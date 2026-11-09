-- Scuttlebutt: the word-of-mouth protocol. Pure Lua: the clock, randomness, timers and the raw
-- send come in through env, so the same code runs in the game and in the offline simulation.
--
-- On start a client sends a summary of what it knows ("S"). Others wait a random moment and
-- answer with records it seems to lack ("R", addressed to it), unless REPLY_LIMIT others already
-- did. Every TRICKLE_EVERY seconds each client sends one batch ("B"): its own new votes mixed
-- with randomly picked votes it has heard. Own votes older than REFRESH_EVERY are re-sent with a
-- fresh time so they don't fade while their author still plays. A record "by me" that is newer
-- than anything I cast is a forgery: I answer with my true record ("D"), and everyone who got the
-- fake from someone holds a strike against that someone.
--
-- env = { me, store, trust, created, send(msg), now(), random(lo, hi), after(seconds, fn),
--         ownVote(rec), onChange(target) (optional) }

local _, ns = ...

local Sync = {}
Sync.__index = Sync
ns.Sync = Sync

local T = ns.Tunables
local Codec = ns.Codec

local QUEUE_MAX = 200
local OWN_PER_BATCH = 2
local SAMPLE_PER_BATCH = 10
local REFRESH_PER_TICK = 2
local CATCHUP_WAIT = 120
local CATCHUP_ROUNDS = 5
local REPLY_FORGET = 120

function Sync.New(env)
	local self = setmetatable({
		env = env,
		queue = {},
		pendingOwn = {},
		replies = {}, -- summaries we may answer: [sender] = { repliers = {}, count, started }
		tokens = T.SEND_BUDGET,
		lastPump = env.now(),
		stats = { sent = 0, received = 0, junk = 0, caughtUp = 0 },
		rounds = 0,
	}, Sync)
	return self
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- Adds a message to the send queue. check(), if given, runs right before sending and can veto.
function Sync:Queue(msg, check, front)
	if not msg then
		return
	end
	local entry = { msg = msg, check = check }
	if front then
		table.insert(self.queue, 1, entry)
	else
		self.queue[#self.queue + 1] = entry
	end
	while #self.queue > QUEUE_MAX do
		table.remove(self.queue, #self.queue)
	end
end

-- Sends what the token bucket allows. Call often (every frame or second).
function Sync:Pump()
	local now = self.env.now()
	self.tokens = math.min(T.SEND_BUDGET, self.tokens + (now - self.lastPump) * T.SEND_REFILL)
	self.lastPump = now
	while self.tokens >= 1 and #self.queue > 0 do
		local entry = table.remove(self.queue, 1)
		if not entry.check or entry.check() then
			local result = self.env.send(entry.msg)
			if result == false then
				-- Refused for now (throttled, not joined yet): try again later, but not forever.
				entry.tries = (entry.tries or 0) + 1
				if entry.tries < T.SEND_TRIES then
					table.insert(self.queue, 1, entry)
				end
				self.tokens = 0
				return
			elseif result == nil or result == true then
				self.tokens = self.tokens - 1
				self.stats.sent = self.stats.sent + 1
			end
			-- Any other result means it can't be sent at all: drop it.
		end
	end
end

function Sync:SendSummary()
	self:Queue(Codec.Encode("S", self.env.store:Digest())[1])
end

function Sync:Start()
	self.rounds = 0
	self:SendSummary()
	self:ScheduleCatchUp()
end

-- After a summary, ask again while replies keep bringing a lot of news.
function Sync:ScheduleCatchUp()
	self.roundNew = 0
	self.env.after(CATCHUP_WAIT, function()
		self.rounds = self.rounds + 1
		if self.roundNew >= T.REPLY_RECORDS / 2 and self.rounds < CATCHUP_ROUNDS then
			self:SendSummary()
			self:ScheduleCatchUp()
		end
	end)
end

---------------------------------------------------------------------------
-- Voting and the trickle
---------------------------------------------------------------------------

-- Casts a vote by this player, or by another character on the same account (env.ownVote).
function Sync:Vote(rec)
	local env = self.env
	if not env.ownVote(rec) then
		return
	end
	-- A change within the same second as the last one must still win "newest wins".
	local old = env.store:Get(rec.target, rec.author)
	if old and rec.time <= old.time then
		rec = { target = rec.target, author = rec.author, vote = rec.vote, tags = rec.tags, time = old.time + 1 }
	end
	if env.store:Put(rec, rec.author, env.now()) then
		self.pendingOwn[#self.pendingOwn + 1] = env.store:Get(rec.target, rec.author)
	end
end

function Sync:RefreshOwn(now)
	local env = self.env
	local done = 0
	for _, rec in ipairs(env.store:ByAuthor(env.me)) do
		if done >= REFRESH_PER_TICK then
			return
		end
		-- A fully cleared vote isn't kept alive: it fades like anything else.
		local cleared = rec.vote == 0 and #rec.tags == 0
		if not cleared and rec.time < now - T.REFRESH_EVERY then
			env.store:Put({ target = rec.target, author = rec.author, vote = rec.vote, tags = rec.tags, time = now }, env.me, now)
			self.pendingOwn[#self.pendingOwn + 1] = env.store:Get(rec.target, rec.author)
			done = done + 1
		end
	end
end

local function Shuffle(list, random)
	for i = #list, 2, -1 do
		local j = random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Call every TRICKLE_EVERY seconds.
function Sync:Tick()
	local env = self.env
	local now = env.now()
	self:RefreshOwn(now)
	if #self.queue > 5 then
		return -- still busy; don't pile up batches
	end
	local list, seen = {}, {}
	for i = 1, math.min(OWN_PER_BATCH, #self.pendingOwn) do
		local rec = self.pendingOwn[i]
		list[#list + 1] = rec
		seen[rec] = true
	end
	for _, rec in ipairs(env.store:Sample(SAMPLE_PER_BATCH, env.random)) do
		if not seen[rec] then
			list[#list + 1] = rec
			seen[rec] = true
		end
	end
	if #list == 0 then
		return
	end
	-- The longest prefix that fits one message: own votes come first so they always fit.
	local n = #list
	while n > 1 and #Codec.Encode("B", { unpack(list, 1, n) }) > 1 do
		n = n - 1
	end
	local chosen = { unpack(list, 1, n) }
	local ownSent = math.min(OWN_PER_BATCH, #self.pendingOwn, n)
	for _ = 1, ownSent do
		table.remove(self.pendingOwn, 1)
	end
	Shuffle(chosen, env.random)
	self:Queue(Codec.Encode("B", chosen)[1])
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function SameVote(a, b)
	if a.vote ~= b.vote or #a.tags ~= #b.tags then
		return false
	end
	for i, id in ipairs(a.tags) do
		if b.tags[i] ~= id then
			return false
		end
	end
	return true
end

function Sync:OnSummary(sender, summary)
	if self.replies[sender] then
		return
	end
	local p = { repliers = {}, count = 0 }
	self.replies[sender] = p
	local env = self.env
	env.after(env.random(0, T.REPLY_DELAY_MAX * 10) / 10, function()
		if p.count >= T.REPLY_LIMIT then
			return
		end
		local missing = env.store:Missing(summary, T.REPLY_RECORDS)
		if #missing == 0 then
			return
		end
		local function Check()
			if p.started then
				return true
			end
			if p.count >= T.REPLY_LIMIT then
				return false
			end
			p.started = true
			return true
		end
		for _, msg in ipairs(Codec.Encode("R", missing, sender)) do
			self:Queue(msg, Check)
		end
	end)
	env.after(REPLY_FORGET, function()
		if self.replies[sender] == p then
			self.replies[sender] = nil
		end
	end)
end

-- A record "by me" that I never cast: answer with my true record.
function Sync:Deny(rec, now)
	local env = self.env
	if now < (env.created or 0) + T.DENY_GRACE then
		return
	end
	local own = env.store:Get(rec.target, env.me)
	if own and own.time >= rec.time then
		return -- an old copy of a real vote; the newer one already wins
	end
	-- Rate limit, so a flood of forgeries can't flood the channel with denials.
	local minute = math.floor(now / 60)
	if self.denyMinute ~= minute then
		self.denyMinute, self.denyCount = minute, 0
	end
	if self.denyCount >= T.DENY_PER_MINUTE then
		return
	end
	self.denyCount = self.denyCount + 1
	local truth = {
		target = rec.target,
		author = env.me,
		vote = own and own.vote or 0,
		tags = own and own.tags or {},
		-- Newer than the fake, but never further ahead than receivers accept.
		time = math.min(math.max(rec.time, now) + 1, now + T.FUTURE_SLACK),
	}
	env.store:Put(truth, env.me, now)
	-- Collect denials for a moment and send them packed together.
	self.denyPending = self.denyPending or {}
	self.denyPending[#self.denyPending + 1] = truth
	if not self.denyScheduled then
		self.denyScheduled = true
		env.after(1, function()
			self.denyScheduled = false
			local msgs = Codec.Encode("D", self.denyPending)
			self.denyPending = {}
			for i = #msgs, 1, -1 do
				self:Queue(msgs[i], nil, true)
			end
		end)
	end
end

function Sync:OnRecords(sender, kind, recs, now)
	local env = self.env
	local store, trust = env.store, env.trust
	local blocked = trust:SenderBlocked(sender, now)
	for _, rec in ipairs(recs) do
		if rec.author == env.me then
			self:Deny(rec, now)
		elseif kind == "D" then
			if rec.author == sender then
				local old = store:Get(rec.target, rec.author)
				if old and not old.witnessed and old.via and old.via ~= sender and not SameVote(old, rec) and rec.time > old.time then
					trust:NoteDenied(old.via, sender, now)
				end
				if store:Put(rec, sender, now) and env.onChange then
					env.onChange(rec.target)
				end
			end
		elseif rec.author == sender or not blocked then
			-- Batches only: catch-up replies are mostly votes from players who are offline.
			if rec.author ~= sender and kind == "B" then
				trust:NoteForwarded(sender, rec, now)
			end
			if store:Put(rec, sender, now) then
				if kind == "R" then
					self.roundNew = (self.roundNew or 0) + 1
					self.stats.caughtUp = self.stats.caughtUp + 1
				end
				if env.onChange then
					env.onChange(rec.target)
				end
			end
		end
	end
end

function Sync:OnMessage(sender, msg)
	local env = self.env
	if sender == env.me then
		return -- our own message echoed back
	end
	local kind, payload, to = Codec.Decode(msg)
	if not kind then
		self.stats.junk = self.stats.junk + 1
		return
	end
	self.stats.received = self.stats.received + 1
	local now = env.now()
	env.trust:NoteWitnessed(sender, now)
	if kind == "S" then
		self:OnSummary(sender, payload)
		return
	end
	if kind == "R" and to ~= env.me then
		local p = self.replies[to]
		if p and not p.repliers[sender] then
			p.repliers[sender] = true
			p.count = p.count + 1
		end
	end
	self:OnRecords(sender, kind, payload, now)
end

function Sync:Stats()
	return self.stats
end
