-- Many Scuttlebutt clients on one virtual clock, talking over a simulated hidden channel.
-- The bus delivers every sent message to every online client of the same faction, the sender
-- included (the game echoes your own channel messages), and checks the send throttle.

local START = 1700000000
local DAY = 86400
local Tn = ns.Tunables

local function World()
	local w = { clock = START, timers = {}, clients = {}, violations = {}, sends = {} }
	local seed = 12345
	function w.Random(lo, hi)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return lo + math.floor(seed / 65536) % (hi - lo + 1)
	end

	function w.Deliver(sender, msg)
		local log = w.sends[sender.me]
		if not log then
			log = {}
			w.sends[sender.me] = log
		end
		log[#log + 1] = w.clock
		for _, c in ipairs(w.clients) do
			if c.online and c.faction == sender.faction then
				c.sync:OnMessage(sender.me, msg)
			end
		end
	end

	function w.Add(me, opts)
		opts = opts or {}
		local c = { me = me, faction = opts.faction or "A", online = false }
		c.store = ns.Store.New({})
		c.trust = ns.Trust.New(c.store, {})
		c.sync = ns.Sync.New({
			me = me,
			store = c.store,
			trust = c.trust,
			created = START - 2 * DAY,
			send = function(msg)
				w.Deliver(c, msg)
			end,
			now = function()
				return w.clock
			end,
			random = w.Random,
			after = function(seconds, fn)
				w.timers[#w.timers + 1] = { at = w.clock + seconds, fn = fn, owner = c }
			end,
			ownVote = function(rec)
				return rec.author == me
			end,
		})
		c.tickOffset = w.Random(0, Tn.TRICKLE_EVERY - 1)
		w.clients[#w.clients + 1] = c
		return c
	end

	function w.Online(c)
		c.online = true
		c.sync.lastPump = w.clock
		c.sync:Start()
	end

	function w.Run(seconds)
		for _ = 1, seconds do
			w.clock = w.clock + 1
			local due, keep = {}, {}
			for _, t in ipairs(w.timers) do
				if t.at <= w.clock then
					due[#due + 1] = t
				else
					keep[#keep + 1] = t
				end
			end
			w.timers = keep
			table.sort(due, function(a, b)
				return a.at < b.at
			end)
			for _, t in ipairs(due) do
				if t.owner.online then
					t.fn()
				end
			end
			for _, c in ipairs(w.clients) do
				if c.online then
					if (w.clock + c.tickOffset) % Tn.TRICKLE_EVERY == 0 then
						c.sync:Tick()
					end
					c.sync:Pump()
				end
			end
		end
	end

	-- No client sent more than the budget in any second, or more than the refill rate allows over
	-- any 60 seconds.
	function w.CheckThrottle(skip)
		for me, log in pairs(w.sends) do
			if skip and skip[me] then
				log = {}
			end
			local perSecond = {}
			for _, t in ipairs(log) do
				perSecond[t] = (perSecond[t] or 0) + 1
				if perSecond[t] > Tn.SEND_BUDGET then
					error(me .. " sent " .. perSecond[t] .. " in one second")
				end
			end
			local j = 1
			for i = 1, #log do
				while log[i] - log[j] >= 60 do
					j = j + 1
				end
				if i - j + 1 > Tn.SEND_BUDGET + 60 * Tn.SEND_REFILL then
					error(me .. " sent " .. (i - j + 1) .. " in 60 seconds")
				end
			end
		end
	end

	function w.Opts()
		return { now = w.clock, excludeGrumps = false, inCircle = function()
			return false
		end }
	end

	return w
end

local function Vote(c, target, vote, now)
	c.sync:Vote({ target = target, author = c.me, vote = vote, tags = {}, time = now })
end

T("news spreads", function()
	local w = World()
	for i = 1, 60 do
		w.Online(w.Add("P" .. i .. "-r"))
	end
	w.Run(30)
	Vote(w.clients[1], "Hero-r", 1, w.clock)
	local half, most
	for s = 1, 600 do
		w.Run(1)
		local n = 0
		for _, c in ipairs(w.clients) do
			if c.trust:Score("Hero-r", w.Opts()).likes >= 1 then
				n = n + 1
			end
		end
		if not half and n >= 30 then
			half = s
		end
		if not most and n >= 54 then
			most = s
			break
		end
	end
	print(string.format("    news spreads: 50%% after %ss, 90%% after %ss", tostring(half), tostring(most)))
	ok(most, "90% never reached in 10 minutes")
	w.CheckThrottle()
end)

T("login catch-up", function()
	local w = World()
	for i = 1, 40 do
		w.Online(w.Add("P" .. i .. "-r"))
	end
	for i, c in ipairs(w.clients) do
		for k = 1, 10 do
			Vote(c, "T" .. i .. "_" .. k .. "-r", 1, w.clock)
		end
	end
	w.Run(300)
	local union = {}
	for _, c in ipairs(w.clients) do
		for _, r in ipairs(c.store:All()) do
			union[r.author .. ">" .. r.target] = true
		end
	end
	local total = 0
	for _ in pairs(union) do
		total = total + 1
	end
	local late = w.Add("Late-r")
	w.Online(late)
	w.Run(600)
	local have = late.store:Digest().count
	print(string.format("    login catch-up: %d of %d records after 10 minutes", have, total))
	ok(have >= 0.8 * total)
	w.CheckThrottle()
end)

T("login storm", function()
	local w = World()
	for i = 1, 100 do
		local c = w.Add("P" .. i .. "-r")
		for k = 1, 20 do
			c.store:Put({ target = "T" .. i .. "_" .. k .. "-r", author = c.me, vote = 1, tags = {}, time = START - k }, c.me, START)
		end
	end
	-- Count distinct repliers per summary sender by watching the bus.
	local repliers = {}
	local deliver = w.Deliver
	w.Deliver = function(sender, msg)
		local kind, _, to = ns.Codec.Decode(msg)
		if kind == "R" then
			repliers[to] = repliers[to] or {}
			repliers[to][sender.me] = true
		end
		deliver(sender, msg)
	end
	for _, c in ipairs(w.clients) do
		w.Online(c)
	end
	w.Run(90)
	local worst = 0
	for _, set in pairs(repliers) do
		local n = 0
		for _ in pairs(set) do
			n = n + 1
		end
		worst = math.max(worst, n)
	end
	print("    login storm: at most " .. worst .. " repliers to one summary")
	ok(worst <= Tn.REPLY_LIMIT + 2)
	w.CheckThrottle()
end)

T("troll flood", function()
	local w = World()
	for i = 1, 30 do
		w.Online(w.Add("P" .. i .. "-r"))
	end
	local troll = w.Add("Troll-r")
	w.Online(troll)
	-- Layer 1 bypassed: the troll's client votes straight into Sync.
	for i = 1, 60 do
		Vote(troll, "Victim" .. i .. "-r", -1, w.clock)
	end
	w.Run(1200)
	for _, c in ipairs(w.clients) do
		if c ~= troll then
			ok(c.trust:IsGrump("Troll-r", w.clock), c.me .. " doesn't see the troll as a Grump")
			for i = 1, 60 do
				eq(c.trust:Score("Victim" .. i .. "-r", w.Opts()).dislikes, 0)
			end
		end
	end
	w.CheckThrottle()
end)

T("forger framing", function()
	local w = World()
	for i = 1, 30 do
		w.Online(w.Add("P" .. i .. "-r"))
	end
	w.Run(60)
	local forger = w.Add("Forger-r")
	forger.online = true
	-- 300 fake dislikes in the names of 10 honest players, sent one message per second.
	local fakes = {}
	for i = 1, 300 do
		fakes[i] = { target = "Victim" .. i .. "-r", author = "P" .. (i % 10 + 1) .. "-r", vote = -1, tags = {}, time = w.clock }
	end
	local i = 1
	while i <= #fakes do
		local chunk = {}
		for k = i, math.min(i + 5, #fakes) do
			chunk[#chunk + 1] = fakes[k]
		end
		i = i + 6
		w.Deliver(forger, ns.Codec.Encode("B", chunk)[1])
		w.Run(1)
	end
	w.Run(600)
	local blockedBy = 0
	for _, c in ipairs(w.clients) do
		if c ~= forger then
			for k = 1, 10 do
				eq(c.trust:IsGrump("P" .. k .. "-r", w.clock), false)
			end
			if c.trust:SenderBlocked("Forger-r", w.clock) then
				blockedBy = blockedBy + 1
			end
		end
	end
	print("    forger framing: forger blocked by " .. blockedBy .. " of 30")
	ok(blockedBy >= 24)
	w.CheckThrottle({ ["Forger-r"] = true }) -- the forger ignores the limit on purpose
end)

T("faction split", function()
	local w = World()
	for i = 1, 10 do
		w.Online(w.Add("A" .. i .. "-r", { faction = "A" }))
		w.Online(w.Add("H" .. i .. "-r", { faction = "H" }))
	end
	Vote(w.clients[1], "Hero-r", 1, w.clock)
	w.Run(300)
	for _, c in ipairs(w.clients) do
		if c.faction == "H" then
			eq(c.store:Get("Hero-r", "A1-r"), nil)
		end
	end
end)

T("honest relays of offline players' votes are not blocked", function()
	local w = World()
	for i = 1, 30 do
		local c = w.Add("P" .. i .. "-r")
		-- Older votes everyone has heard by now.
		for k = 1, 10 do
			c.store:Put({ target = "Old" .. k .. "-r", author = "Gone" .. i .. "-r", vote = 1, tags = {}, time = START - 3 * DAY }, "Relay-r", START)
		end
		w.Online(c)
	end
	-- Half the realm votes, then logs off.
	for i = 1, 15 do
		for k = 1, 8 do
			Vote(w.clients[i], "Fresh" .. i .. "_" .. k .. "-r", 1, w.clock)
		end
	end
	w.Run(240)
	for i = 1, 15 do
		w.clients[i].online = false
	end
	local late = w.Add("Late-r")
	w.Online(late)
	w.Run(900)
	local blocked = 0
	for i = 16, 30 do
		if late.trust:SenderBlocked("P" .. i .. "-r", w.clock) then
			blocked = blocked + 1
		end
	end
	print("    offline authors: " .. blocked .. " of 15 honest relays blocked by the newcomer, " .. late.store:Digest().count .. " records heard")
	eq(blocked, 0)
	w.CheckThrottle()
end)
