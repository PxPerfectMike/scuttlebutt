local NOW = 1700000000
local DAY = 86400

local function ctx(over)
	local c = { me = "Me-r", level = 20, eligible = true, now = NOW }
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

local function fresh()
	local g = ns.Guard.New({})
	g:AddCharacter("Me-r")
	return g
end

T("self vote refused", function()
	local g = fresh()
	eq({ g:CanVote("Me-r", 1, ctx()) }, { false, "self" })
	g:AddCharacter("Alt-r")
	eq({ g:CanVote("Alt-r", -1, ctx()) }, { false, "self" })
end)

T("level 8 refused, level 9 allowed", function()
	local g = fresh()
	eq({ g:CanVote("Bob-r", 1, ctx({ level = 8 })) }, { false, "level" })
	eq((g:CanVote("Bob-r", 1, ctx({ level = 9 }))), true)
end)

T("absent refused", function()
	eq({ fresh():CanVote("Bob-r", 1, ctx({ eligible = false })) }, { false, "absent" })
end)

T("16th dislike in a day refused, allowed next day", function()
	local g = fresh()
	-- Mix in likes so the sour streak doesn't trigger first.
	for i = 1, 15 do
		ok(g:CanVote("Bob" .. i .. "-r", -1, ctx()))
		g:Record(-1, NOW)
		for _ = 1, 4 do
			g:Record(1, NOW)
		end
	end
	eq({ g:CanVote("Bob16-r", -1, ctx()) }, { false, "cap" })
	eq((g:CanVote("Bob16-r", 1, ctx())), true, "likes still allowed")
	eq((g:CanVote("Bob16-r", -1, ctx({ now = NOW + DAY }))), true)
end)

T("likes unlimited", function()
	local g = fresh()
	for i = 1, 100 do
		ok(g:CanVote("Bob" .. i .. "-r", 1, ctx()))
		g:Record(1, NOW)
	end
end)

T("sour streak pauses dislikes", function()
	local g = fresh()
	-- 25 dislikes and 5 likes over five days, never more than 5 dislikes a day.
	for d = 0, 4 do
		for _ = 1, 5 do
			g:Record(-1, NOW + d * DAY)
		end
		g:Record(1, NOW + d * DAY)
	end
	local t = NOW + 4 * DAY
	eq({ g:CanVote("Bob-r", -1, ctx({ now = t })) }, { false, "sour" })
	eq((g:CanVote("Bob-r", 1, ctx({ now = t }))), true)
	eq((g:CanVote("Bob-r", -1, ctx({ now = t + ns.Tunables.SOUR_PAUSE + 1 }))), true)
end)

T("clearing a vote is always allowed when eligible", function()
	local g = fresh()
	for i = 1, 30 do
		g:Record(-1, NOW + i)
	end
	eq((g:CanVote("Bob-r", 0, ctx())), true)
end)

T("account vote found from an alt", function()
	local g = fresh()
	g:AddCharacter("Alt-r")
	local s = ns.Store.New({})
	s:Put({ target = "Bob-r", author = "Alt-r", vote = -1, tags = {}, time = NOW }, "Alt-r", NOW)
	local r = g:AccountVote(s, "Bob-r")
	ok(r, "found")
	eq(r.author, "Alt-r")
	eq(g:AccountVote(s, "Cy-r"), nil)
end)

T("own character check", function()
	local g = fresh()
	eq(g:IsMine("Me-r"), true)
	eq(g:IsMine("Bob-r"), false)
end)

T("account votes lists every other character's vote", function()
	local g = fresh()
	g:AddCharacter("Alt-r")
	g:AddCharacter("Alt2-r")
	local s = ns.Store.New({})
	s:Put({ target = "Bob-r", author = "Me-r", vote = 0, tags = {}, time = NOW }, "Me-r", NOW)
	s:Put({ target = "Bob-r", author = "Alt-r", vote = -1, tags = {}, time = NOW }, "Alt-r", NOW)
	s:Put({ target = "Bob-r", author = "Alt2-r", vote = 1, tags = {}, time = NOW }, "Alt2-r", NOW)
	local found = {}
	for _, r in ipairs(g:AccountVotes(s, "Bob-r", "Me-r")) do
		found[r.author] = true
	end
	eq(found, { ["Alt-r"] = true, ["Alt2-r"] = true })
end)

T("removal means nothing is added", function()
	local current = { vote = 1, tags = { 1, 5 } }
	eq(ns.Guard.IsRemoval(current, 0, { 1, 5 }), true, "take back the like, keep tags")
	eq(ns.Guard.IsRemoval(current, 1, { 5 }), true, "drop a tag")
	eq(ns.Guard.IsRemoval(current, 0, {}), true)
	eq(ns.Guard.IsRemoval(current, -1, { 1, 5 }), false, "switching to dislike adds")
	eq(ns.Guard.IsRemoval(current, 1, { 1, 5, 9 }), false, "adding a tag")
	eq(ns.Guard.IsRemoval(nil, 0, {}), true)
	eq(ns.Guard.IsRemoval(nil, 1, {}), false)
end)
