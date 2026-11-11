local NOW = 1700000000

local function rec(t, a, v, time, tags)
	return { target = t, author = a, vote = v, tags = tags or {}, time = time or NOW }
end

local function fresh()
	return ns.Store.New({})
end

T("newer replaces older", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1, NOW - 10), "Ann-r", NOW)
	ok(s:Put(rec("Bob-r", "Ann-r", -1, NOW), "Ann-r", NOW))
	local about = s:About("Bob-r")
	eq(#about, 1)
	eq(about[1].vote, -1)
end)

T("older is ignored", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1, NOW), "Ann-r", NOW)
	eq(s:Put(rec("Bob-r", "Ann-r", -1, NOW - 10), "Ann-r", NOW), false)
	eq(s:About("Bob-r")[1].vote, 1)
end)

T("future time clamped", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1, NOW + 3600), "Ann-r", NOW)
	eq(s:About("Bob-r")[1].time, NOW)
end)

T("small future skew kept", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1, NOW + 60), "Ann-r", NOW)
	eq(s:About("Bob-r")[1].time, NOW + 60)
end)

T("witnessed when author sends", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1), "Cy-r", NOW)
	eq(s:About("Bob-r")[1].witnessed, false)
	ok(s:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW), "witnessing counts as a change")
	eq(s:About("Bob-r")[1].witnessed, true)
end)

T("forwarded copy remembers who sent it", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1), "Cy-r", NOW)
	eq(s:About("Bob-r")[1].via, "Cy-r")
	s:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW)
	eq(s:About("Bob-r")[1].via, nil)
end)

T("witness survives a newer forwarded copy", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1, NOW - 10), "Ann-r", NOW)
	s:Put(rec("Bob-r", "Ann-r", -1, NOW), "Cy-r", NOW)
	local r = s:About("Bob-r")[1]
	eq(r.vote, -1)
	eq(r.witnessed, false)
end)

T("self vote rejected", function()
	local s = fresh()
	eq(s:Put(rec("Ann-r", "Ann-r", 1), "Ann-r", NOW), false)
	eq(#s:About("Ann-r"), 0)
end)

T("four tags rejected", function()
	local s = fresh()
	eq(s:Put(rec("Bob-r", "Ann-r", 1, NOW, { 1, 2, 3, 4 }), "Ann-r", NOW), false)
end)

T("bad vote rejected", function()
	local s = fresh()
	eq(s:Put(rec("Bob-r", "Ann-r", 5), "Ann-r", NOW), false)
end)

T("by author", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW)
	s:Put(rec("Cy-r", "Ann-r", -1), "Ann-r", NOW)
	s:Put(rec("Cy-r", "Dee-r", -1), "Dee-r", NOW)
	eq(#s:ByAuthor("Ann-r"), 2)
end)

T("digest matches equal stores", function()
	local a, b = fresh(), fresh()
	for _, s in ipairs({ a, b }) do
		s:Put(rec("Bob-r", "Ann-r", 1, NOW - 5), "Ann-r", NOW)
		s:Put(rec("Cy-r", "Dee-r", -1, NOW), "Cy-r", NOW)
	end
	eq(a:Digest(), b:Digest())
end)

T("missing finds only newer", function()
	local a, b = fresh(), fresh()
	a:Put(rec("Bob-r", "Ann-r", 1, NOW), "Ann-r", NOW)
	a:Put(rec("Cy-r", "Dee-r", -1, NOW - 100), "Dee-r", NOW)
	b:Put(rec("Cy-r", "Dee-r", -1, NOW - 100), "Dee-r", NOW)
	local missing = a:Missing(b:Digest(), 50)
	local found = {}
	for _, r in ipairs(missing) do
		found[r.target] = true
	end
	ok(found["Bob-r"], "the record B lacks is offered")
	-- Records B already has as new are not offered unless they share a bucket with a newer one.
	for _, r in ipairs(missing) do
		ok(r.target == "Bob-r" or r.time >= NOW - 100)
	end
end)

T("missing respects limit and puts newest first", function()
	local a = fresh()
	for i = 1, 20 do
		a:Put(rec("T" .. i .. "-r", "Ann-r", 1, NOW - i), "Ann-r", NOW)
	end
	local missing = a:Missing({ count = 0, buckets = {} }, 5)
	eq(#missing, 5)
	eq(missing[1].time, NOW - 1)
end)

T("sample returns distinct records", function()
	local a = fresh()
	for i = 1, 10 do
		a:Put(rec("T" .. i .. "-r", "Ann-r", 1), "Ann-r", NOW)
	end
	local seed = 0
	local picked = a:Sample(4, function(lo, hi)
		seed = seed + 3
		return lo + seed % (hi - lo + 1)
	end)
	eq(#picked, 4)
	local seen = {}
	for _, r in ipairs(picked) do
		ok(not seen[r.target], "duplicate in sample")
		seen[r.target] = true
	end
end)

T("prune drops faded but keeps own", function()
	local s = fresh()
	local old = NOW - ns.Tunables.FADE - 1
	s:Put(rec("Bob-r", "Ann-r", 1, old), "Ann-r", NOW)
	s:Put(rec("Cy-r", "Me-r", 1, old), "Me-r", NOW)
	s:Prune(NOW, function(r)
		return r.author == "Me-r"
	end)
	eq(#s:About("Bob-r"), 0)
	eq(#s:About("Cy-r"), 1)
end)

T("prune caps count", function()
	local saved = ns.Tunables.MAX_RECORDS
	ns.Tunables.MAX_RECORDS = 10
	local s = fresh()
	for i = 1, 15 do
		s:Put(rec("T" .. i .. "-r", "Ann-r", 1, NOW - i), "Ann-r", NOW)
	end
	s:Prune(NOW, function()
		return false
	end)
	ns.Tunables.MAX_RECORDS = saved
	eq(s:Digest().count, 10)
	eq(#s:About("T15-r"), 0)
	eq(#s:About("T1-r"), 1)
end)

T("notes survive prune and are not records", function()
	local s = fresh()
	s:SetNote("Bob-r", "Healed me through Deadmines")
	s:Prune(NOW + ns.Tunables.FADE * 2, function()
		return false
	end)
	eq(s:GetNote("Bob-r"), "Healed me through Deadmines")
	eq(#s:About("Bob-r"), 0)
	s:SetNote("Bob-r", nil)
	eq(s:GetNote("Bob-r"), nil)
end)

T("reload from saved table", function()
	local db = {}
	local s = ns.Store.New(db)
	s:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW)
	local again = ns.Store.New(db)
	eq(#again:About("Bob-r"), 1)
	eq(#again:ByAuthor("Ann-r"), 1)
end)

T("names must be in normalized form", function()
	local s = fresh()
	eq(s:Put(rec("bob-R", "Ann-r", 1), "Ann-r", NOW), false)
	eq(s:Put(rec("Bob-r", "ANN-r", 1), "ANN-r", NOW), false)
	eq(s:Put(rec("Bob", "Ann-r", 1), "Ann-r", NOW), false)
	ok(s:Put(rec("Bob-r", "Ann-r", 1), "Ann-r", NOW))
end)

T("per-author cap stops new targets but allows updates", function()
	local saved = ns.Tunables.MAX_PER_AUTHOR
	ns.Tunables.MAX_PER_AUTHOR = 5
	local s = fresh()
	for i = 1, 5 do
		ok(s:Put(rec("T" .. i .. "-r", "Spam-r", -1, NOW - 10), "Spam-r", NOW))
	end
	local sixth = s:Put(rec("T6-r", "Spam-r", -1), "Spam-r", NOW)
	local update = s:Put(rec("T1-r", "Spam-r", 1), "Spam-r", NOW)
	ns.Tunables.MAX_PER_AUTHOR = saved
	eq(sixth, false)
	eq(update, true)
end)

T("short-name records move to the full name that sent them", function()
	local s = fresh()
	s:Put(rec("Bob-r", "Scrow-r", 1, NOW - 10), "Scrowtumwater-r", NOW)
	s:Put(rec("Ann-r", "Scrow-r", -1, NOW - 5), "Scrowtumwater-r", NOW)
	s:Put(rec("Ann-r", "Scrowtumwater-r", 1, NOW), "Scrowtumwater-r", NOW)
	s:Put(rec("Cy-r", "Dee-r", 1, NOW), "Eve-r", NOW)
	s:AdoptShortNames(function(author, via)
		return ns.Names.IsShortFor(author, via)
	end, NOW)
	local bob = s:Get("Bob-r", "Scrowtumwater-r")
	ok(bob and bob.witnessed and bob.vote == 1 and bob.time == NOW - 10, "moved and witnessed")
	eq(s:Get("Ann-r", "Scrowtumwater-r").vote, 1) -- the newer full-name vote wins
	eq(s:Get("Bob-r", "Scrow-r"), nil)
	eq(s:Get("Ann-r", "Scrow-r"), nil)
	ok(s:Get("Cy-r", "Dee-r"), "unrelated forward untouched")
	eq(s.count, 3)
end)
