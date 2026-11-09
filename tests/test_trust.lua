local NOW = 1700000000
local W = ns.Tunables.GRUMP_WEAR_OFF

local function rec(t, a, v, time, tags)
	return { target = t, author = a, vote = v, tags = tags or {}, time = time or NOW }
end

local function setup()
	local store = ns.Store.New({})
	return store, ns.Trust.New(store, {})
end

local function opts(over)
	local o = { now = NOW, excludeGrumps = false, inCircle = function()
		return false
	end }
	for k, v in pairs(over or {}) do
		o[k] = v
	end
	return o
end

-- n dislikes by author on fresh targets, sent by sender.
local function dislikes(store, author, n, sender, time)
	for i = 1, n do
		store:Put(rec("Victim" .. i .. "-r", author, -1, time), sender or author, NOW)
	end
end

T("witnessed counts 1, forwarded 0.25", function()
	local store, trust = setup()
	for i = 1, 4 do
		store:Put(rec("Bob-r", "Fan" .. i .. "-r", 1), "Relay-r", NOW)
	end
	store:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW)
	eq(trust:Score("Bob-r", opts()).likes, 2)
end)

T("grump needs witnessed votes", function()
	local store, trust = setup()
	dislikes(store, "Ann-r", 25, "Relay-r")
	eq(trust:IsGrump("Ann-r", NOW), false)
	local store2, trust2 = setup()
	dislikes(store2, "Ann-r", 25)
	eq(trust2:IsGrump("Ann-r", NOW), true)
end)

T("grump needs enough votes", function()
	local store, trust = setup()
	dislikes(store, "Ann-r", 19)
	eq(trust:IsGrump("Ann-r", NOW), false)
end)

T("mostly likes is not a grump", function()
	local store, trust = setup()
	dislikes(store, "Ann-r", 10)
	for i = 1, 15 do
		store:Put(rec("Pal" .. i .. "-r", "Ann-r", 1), "Ann-r", NOW)
	end
	eq(trust:IsGrump("Ann-r", NOW), false)
end)

T("framing fails", function()
	local store, trust = setup()
	-- A forger forwards 40 dislikes in Ann's name, all on Bob... one per target is the rule, so
	-- spread them: 40 targets, plus Bob.
	dislikes(store, "Ann-r", 40, "Forger-r")
	store:Put(rec("Bob-r", "Ann-r", -1), "Forger-r", NOW)
	eq(trust:IsGrump("Ann-r", NOW), false)
	ok(trust:Score("Bob-r", opts()).dislikes <= 1)
end)

T("grump dislikes count zero, likes still count", function()
	local store, trust = setup()
	dislikes(store, "Grr-r", 25)
	store:Put(rec("Bob-r", "Grr-r", -1), "Grr-r", NOW)
	store:Put(rec("Cy-r", "Grr-r", 1), "Grr-r", NOW)
	eq(trust:Score("Bob-r", opts()).dislikes, 0)
	eq(trust:Score("Cy-r", opts()).likes, 1)
end)

T("excludeGrumps drops likes too", function()
	local store, trust = setup()
	dislikes(store, "Grr-r", 25)
	store:Put(rec("Cy-r", "Grr-r", 1), "Grr-r", NOW)
	eq(trust:Score("Cy-r", opts({ excludeGrumps = true })).likes, 0)
end)

T("grump wears off", function()
	local store, trust = setup()
	dislikes(store, "Grr-r", 25, nil, NOW - W - 1)
	eq(trust:IsGrump("Grr-r", NOW), false)
	eq(trust:IsGrump("Grr-r", NOW - W), true)
end)

T("score shows grump tag for the target", function()
	local store, trust = setup()
	dislikes(store, "Grr-r", 25)
	eq(trust:Score("Grr-r", opts()).grump, true)
	eq(trust:Score("Bob-r", opts()).grump, false)
end)

T("circle and unconfirmed counted", function()
	local store, trust = setup()
	store:Put(rec("Bob-r", "Pal-r", 1), "Pal-r", NOW)
	store:Put(rec("Bob-r", "Guildie-r", 1), "Relay-r", NOW)
	store:Put(rec("Bob-r", "Stranger-r", -1), "Stranger-r", NOW)
	local s = trust:Score("Bob-r", opts({ inCircle = function(k)
		return k == "Pal-r" or k == "Guildie-r"
	end }))
	eq(s.circle, 2)
	eq(s.unconfirmed, 1)
end)

T("tags weighted and rounded", function()
	local store, trust = setup()
	store:Put(rec("Bob-r", "A-r", 1, NOW, { 1, 5 }), "A-r", NOW)
	store:Put(rec("Bob-r", "B-r", 1, NOW, { 1 }), "B-r", NOW)
	store:Put(rec("Bob-r", "C-r", 1, NOW, { 5 }), "Relay-r", NOW)
	local s = trust:Score("Bob-r", opts())
	eq(s.tags[1], 2)
	eq(s.tags[5], 1) -- 1 + 0.25 rounds to 1
end)

T("cleared votes are not counted", function()
	local store, trust = setup()
	store:Put(rec("Bob-r", "A-r", 0), "A-r", NOW)
	local s = trust:Score("Bob-r", opts())
	eq(s.likes, 0)
	eq(s.dislikes, 0)
end)

T("forger sender blocked", function()
	local store, trust = setup()
	for i = 1, 30 do
		trust:NoteForwarded("Forger-r", rec("Bob-r", "Ghost" .. i .. "-r", -1), NOW)
	end
	eq(trust:SenderBlocked("Forger-r", NOW), true)
	eq(trust:SenderBlocked("Forger-r", NOW + ns.Tunables.FORGE_BLOCK + 1), true, "still forging")
end)

T("honest relay not blocked", function()
	local store, trust = setup()
	for i = 1, 30 do
		trust:NoteForwarded("Relay-r", rec("Bob-r", "Real" .. i .. "-r", -1), NOW)
		trust:NoteWitnessed("Real" .. i .. "-r", NOW)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)

T("denials from enough different authors block the sender", function()
	local _, trust = setup()
	for i = 1, ns.Tunables.FORGE_DENIALS do
		trust:NoteDenied("Forger-r", "Victim" .. i .. "-r", NOW)
	end
	eq(trust:SenderBlocked("Forger-r", NOW), true)
end)

T("one author short does not block", function()
	local _, trust = setup()
	for i = 1, ns.Tunables.FORGE_DENIALS - 1 do
		trust:NoteDenied("Relay-r", "Victim" .. i .. "-r", NOW)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)

T("many denials from one author do not block", function()
	local _, trust = setup()
	for _ = 1, 20 do
		trust:NoteDenied("Relay-r", "Liar-r", NOW)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)

T("old denials expire", function()
	local _, trust = setup()
	for i = 1, ns.Tunables.FORGE_DENIALS do
		trust:NoteDenied("Relay-r", "Victim" .. i .. "-r", NOW - ns.Tunables.FORGE_WINDOW - 1)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)

T("old votes from unseen authors are not ghosts", function()
	local _, trust = setup()
	for i = 1, 60 do
		trust:NoteForwarded("Relay-r", rec("Bob-r", "Offline" .. i .. "-r", 1, NOW - 10 * 86400), NOW)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)

T("prune drops old bookkeeping", function()
	local _, trust = setup()
	local old = NOW - ns.Tunables.FORGE_WINDOW - 10
	trust:NoteForwarded("Relay-r", rec("Bob-r", "A-r", 1), old)
	trust:NoteWitnessed("A-r", old)
	trust:NoteDenied("Relay-r", "A-r", old)
	trust.db.blocked["Relay-r"] = old
	trust:Prune(NOW)
	eq(trust.db.forwards["Relay-r"], nil)
	eq(trust.db.seen["A-r"], nil)
	eq(trust.db.denied["Relay-r"], nil)
	eq(trust.db.blocked["Relay-r"], nil)
end)

T("few forwards never block", function()
	local store, trust = setup()
	for i = 1, 29 do
		trust:NoteForwarded("Relay-r", rec("Bob-r", "Ghost" .. i .. "-r", -1), NOW)
	end
	eq(trust:SenderBlocked("Relay-r", NOW), false)
end)
