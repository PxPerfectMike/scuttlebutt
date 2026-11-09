local NOW = 1700000000
local DAY = 86400

-- A client with a fake clock, timers and a seeded random.
local function client(me, created)
	local h = { sent = {}, timers = {}, clock = NOW, seed = 7 }
	local store = ns.Store.New({})
	local env = {
		me = me,
		store = store,
		trust = ns.Trust.New(store, {}),
		created = created or (NOW - 2 * DAY),
		send = function(msg)
			h.sent[#h.sent + 1] = msg
		end,
		now = function()
			return h.clock
		end,
		random = function(lo, hi)
			h.seed = (h.seed * 1103515245 + 12345) % 2147483648
			return lo + h.seed % (hi - lo + 1)
		end,
		after = function(sec, fn)
			h.timers[#h.timers + 1] = { at = h.clock + sec, fn = fn }
		end,
		ownVote = function(rec)
			return rec.author == me
		end,
	}
	h.env = env
	h.sync = ns.Sync.New(env)
	function h.Advance(seconds)
		for _ = 1, seconds do
			h.clock = h.clock + 1
			local due = {}
			for i = #h.timers, 1, -1 do
				if h.timers[i].at <= h.clock then
					due[#due + 1] = table.remove(h.timers, i)
				end
			end
			for i = #due, 1, -1 do
				due[i].fn()
			end
			h.sync:Pump()
		end
	end
	function h.Sent(kind)
		local out = {}
		for _, m in ipairs(h.sent) do
			local k, recs, to = ns.Codec.Decode(m)
			if k == kind then
				out[#out + 1] = { recs = recs, to = to }
			end
		end
		return out
	end
	return h
end

local function rec(t, a, v, time, tags)
	return { target = t, author = a, vote = v, tags = tags or {}, time = time or NOW, }
end

local function batch(...)
	return ns.Codec.Encode("B", { ... })[1]
end

local function fill(h, n)
	for i = 1, n do
		h.env.store:Put(rec("T" .. i .. "-r", "A" .. i .. "-r", 1, NOW - i), "A" .. i .. "-r", NOW)
	end
end

T("start sends a summary", function()
	local h = client("Me-r")
	h.sync:Start()
	h.Advance(1)
	eq(#h.Sent("S"), 1)
end)

T("reply after delay", function()
	local h = client("Me-r")
	fill(h, 5)
	h.sync:OnMessage("Newbie-r", ns.Codec.Encode("S", { count = 0, buckets = {} })[1])
	h.Advance(ns.Tunables.REPLY_DELAY_MAX + 1)
	local replies = h.Sent("R")
	eq(#replies, 1)
	eq(replies[1].to, "Newbie-r")
	eq(#replies[1].recs, 5)
end)

T("no reply when nothing is missing", function()
	local h = client("Me-r")
	h.sync:OnMessage("Newbie-r", ns.Codec.Encode("S", { count = 0, buckets = {} })[1])
	h.Advance(ns.Tunables.REPLY_DELAY_MAX + 1)
	eq(#h.Sent("R"), 0)
end)

T("reply canceled after three others", function()
	local h = client("Me-r")
	fill(h, 5)
	h.sync:OnMessage("Newbie-r", ns.Codec.Encode("S", { count = 0, buckets = {} })[1])
	for i = 1, 3 do
		h.sync:OnMessage("Helper" .. i .. "-r", ns.Codec.Encode("R", { rec("X-r", "Y-r", 1) }, "Newbie-r")[1])
	end
	h.Advance(ns.Tunables.REPLY_DELAY_MAX + 1)
	eq(#h.Sent("R"), 0)
end)

T("records from a batch are stored witnessed only for their author", function()
	local h = client("Me-r")
	h.sync:OnMessage("Ann-r", batch(rec("Bob-r", "Ann-r", 1), rec("Cy-r", "Dee-r", -1)))
	eq(h.env.store:Get("Bob-r", "Ann-r").witnessed, true)
	eq(h.env.store:Get("Cy-r", "Dee-r").witnessed, false)
end)

T("own echo ignored", function()
	local h = client("Me-r")
	h.sync:OnMessage("Me-r", batch(rec("Bob-r", "Ann-r", 1)))
	eq(h.env.store:Get("Bob-r", "Ann-r"), nil)
end)

T("junk message ignored without error", function()
	local h = client("Me-r")
	h.sync:OnMessage("Ann-r", "!!garbage!!")
	h.sync:OnMessage("Ann-r", "")
	eq(h.sync:Stats().junk, 2)
end)

T("own vote goes out within one tick", function()
	local h = client("Me-r")
	h.sync:Vote(rec("Bob-r", "Me-r", 1))
	h.sync:Tick()
	h.Advance(1)
	local found = false
	for _, b in ipairs(h.Sent("B")) do
		for _, r in ipairs(b.recs) do
			found = found or (r.author == "Me-r" and r.target == "Bob-r")
		end
	end
	ok(found)
end)

T("own vote never alone", function()
	local h = client("Me-r")
	fill(h, 20)
	h.sync:Vote(rec("Bob-r", "Me-r", 1))
	h.sync:Tick()
	h.Advance(1)
	local b = h.Sent("B")[1]
	local others, mine = 0, false
	for _, r in ipairs(b.recs) do
		if r.author == "Me-r" then
			mine = true
		else
			others = others + 1
		end
	end
	ok(mine, "own vote included")
	ok(others >= 3, "only " .. others .. " others")
end)

T("vote by another character on the account is stored as witnessed", function()
	local h = client("Me-r")
	h.env.ownVote = function(r)
		return r.author == "Me-r" or r.author == "Alt-r"
	end
	h.sync:Vote(rec("Bob-r", "Alt-r", 0))
	eq(h.env.store:Get("Bob-r", "Alt-r").witnessed, true)
end)

T("two changes in the same second both apply", function()
	local h = client("Me-r")
	h.sync:Vote(rec("Bob-r", "Me-r", 1, NOW, { 1 }))
	h.sync:Vote(rec("Bob-r", "Me-r", 1, NOW, { 1, 5 }))
	eq(h.env.store:Get("Bob-r", "Me-r").tags, { 1, 5 })
end)

T("a send the game refuses is retried later", function()
	local h = client("Me-r")
	local refuse = true
	h.env.send = function(msg)
		if refuse then
			return false
		end
		h.sent[#h.sent + 1] = msg
		return true
	end
	h.sync:Queue("hello")
	h.Advance(1)
	eq(#h.sent, 0)
	refuse = false
	h.Advance(2)
	eq(h.sent, { "hello" })
end)

T("old own vote refreshed", function()
	local h = client("Me-r")
	h.env.store:Put(rec("Bob-r", "Me-r", 1, NOW - 15 * DAY), "Me-r", NOW)
	h.sync:Tick()
	h.Advance(1)
	eq(h.env.store:Get("Bob-r", "Me-r").time, NOW)
	local found = false
	for _, b in ipairs(h.Sent("B")) do
		for _, r in ipairs(b.recs) do
			found = found or (r.author == "Me-r" and r.time == NOW)
		end
	end
	ok(found, "refreshed vote sent")
end)

T("forged record in my name is denied", function()
	local h = client("Me-r")
	h.sync:OnMessage("Forger-r", batch(rec("Bob-r", "Me-r", -1)))
	h.Advance(1)
	local mine = h.env.store:Get("Bob-r", "Me-r")
	eq(mine.vote, 0)
	ok(mine.time > NOW)
	local d = h.Sent("D")
	eq(#d, 1)
	eq(d[1].recs[1].vote, 0)
end)

T("forgery of a real vote restores it", function()
	local h = client("Me-r")
	h.env.store:Put(rec("Bob-r", "Me-r", 1, NOW - 100, { 5 }), "Me-r", NOW)
	h.sync:OnMessage("Forger-r", batch(rec("Bob-r", "Me-r", -1)))
	h.Advance(1)
	local mine = h.env.store:Get("Bob-r", "Me-r")
	eq(mine.vote, 1)
	eq(mine.tags, { 5 })
end)

T("no denial during the grace after a new database", function()
	local h = client("Me-r", NOW)
	h.sync:OnMessage("Relay-r", batch(rec("Bob-r", "Me-r", 1)))
	h.Advance(1)
	eq(#h.Sent("D"), 0)
end)

T("denial strikes the forwarder", function()
	local h = client("Me-r")
	h.sync:OnMessage("Forger-r", batch(rec("Bob-r", "Ann-r", -1)))
	h.sync:OnMessage("Ann-r", ns.Codec.Encode("D", { rec("Bob-r", "Ann-r", 0, NOW + 1) })[1])
	eq(h.env.store:Get("Bob-r", "Ann-r").vote, 0)
	eq(#h.env.trust.db.denied["Forger-r"], 1)
end)

T("denial records must be the sender's own", function()
	local h = client("Me-r")
	h.sync:OnMessage("Ann-r", ns.Codec.Encode("D", { rec("Bob-r", "Cy-r", 0) })[1])
	eq(h.env.store:Get("Bob-r", "Cy-r"), nil)
end)

T("blocked sender's forwards ignored, own votes kept", function()
	local h = client("Me-r")
	for i = 1, ns.Tunables.FORGE_DENIALS do
		h.env.trust:NoteDenied("Forger-r", "Victim" .. i .. "-r", NOW)
	end
	h.sync:OnMessage("Forger-r", batch(rec("Bob-r", "Ann-r", -1), rec("Cy-r", "Forger-r", -1)))
	eq(h.env.store:Get("Bob-r", "Ann-r"), nil)
	ok(h.env.store:Get("Cy-r", "Forger-r"))
end)

T("send queue respects the budget", function()
	local h = client("Me-r")
	for i = 1, 40 do
		h.sync:Queue("x" .. i)
	end
	h.Advance(1)
	ok(#h.sent <= ns.Tunables.SEND_BUDGET)
	local before = #h.sent
	h.Advance(5)
	ok(#h.sent - before <= 5 * ns.Tunables.SEND_REFILL + 1)
end)

T("forged far-future vote in my name is denied with a sendable time", function()
	local h = client("Me-r")
	h.sync:OnMessage("Forger-r", batch(rec("Bob-r", "Me-r", -1, 93 ^ 5 - 1)))
	h.Advance(2)
	local d = h.Sent("D")
	eq(#d, 1)
	ok(d[1].recs[1].time <= NOW + 2 + ns.Tunables.FUTURE_SLACK)
	h.sync:Queue("after")
	h.Advance(3)
	eq(h.sent[#h.sent], "after", "queue still moves")
end)

T("a send that fails for good is dropped", function()
	local h = client("Me-r")
	h.env.send = function(msg)
		if msg == "bad" then
			return "failed"
		end
		h.sent[#h.sent + 1] = msg
	end
	h.sync:Queue("bad")
	h.sync:Queue("good")
	h.Advance(2)
	eq(h.sent, { "good" })
end)

T("a send refused over and over is dropped eventually", function()
	local h = client("Me-r")
	h.env.send = function(msg)
		if msg == "stuck" then
			return false
		end
		h.sent[#h.sent + 1] = msg
	end
	h.sync:Queue("stuck")
	h.sync:Queue("next")
	h.Advance(120)
	eq(h.sent, { "next" })
end)

T("denials are batched", function()
	local h = client("Me-r")
	local list = {}
	for i = 1, 6 do
		list[i] = rec("T" .. i .. "-r", "Me-r", -1)
	end
	h.sync:OnMessage("Forger-r", ns.Codec.Encode("B", list)[1])
	h.Advance(3)
	local d = h.Sent("D")
	ok(#d >= 1 and #d <= 2, #d .. " denial messages")
	local n = 0
	for _, m in ipairs(d) do
		n = n + #m.recs
	end
	eq(n, 6)
end)

T("reply records don't count toward the ghost check", function()
	local h = client("Me-r")
	local list = {}
	for i = 1, 40 do
		list[i] = rec("T" .. i .. "-r", "Unseen" .. i .. "-r", 1)
	end
	for _, m in ipairs(ns.Codec.Encode("R", list, "Me-r")) do
		h.sync:OnMessage("Helper-r", m)
	end
	eq(h.env.trust:SenderBlocked("Helper-r", NOW), false)
end)

T("cleared own votes are not refreshed", function()
	local h = client("Me-r")
	h.env.store:Put(rec("Bob-r", "Me-r", 0, NOW - 15 * DAY), "Me-r", NOW)
	h.sync:Tick()
	h.Advance(1)
	eq(h.env.store:Get("Bob-r", "Me-r").time, NOW - 15 * DAY)
end)
