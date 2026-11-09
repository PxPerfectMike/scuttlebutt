local function rec(t, a, v, tags, time)
	return { target = t, author = a, vote = v, tags = tags or {}, time = time or 1700000000 }
end

T("records round-trip", function()
	local list = {
		rec("Bob-realm", "Ann-realm", 1, { 1, 5 }),
		rec("Zoë-draenor", "Ann-realm", -1, { 9, 10, 14 }),
		rec("Cy-realm", "Dee-realm", 0),
	}
	local msgs = ns.Codec.Encode("B", list)
	local back = {}
	for _, m in ipairs(msgs) do
		ok(#m <= ns.Tunables.MSG_MAX, "message too long")
		local kind, recs = ns.Codec.Decode(m)
		eq(kind, "B")
		for _, r in ipairs(recs) do
			back[#back + 1] = r
		end
	end
	eq(back, list)
end)

T("many records split across messages", function()
	local list = {}
	for i = 1, 200 do
		list[i] = rec("Target" .. i .. "-realm", "Author" .. i .. "-realm", 1, { 1 })
	end
	local msgs = ns.Codec.Encode("R", list, "Newbie-realm")
	ok(#msgs > 1)
	local n = 0
	for _, m in ipairs(msgs) do
		ok(#m <= ns.Tunables.MSG_MAX)
		local _, recs = ns.Codec.Decode(m)
		n = n + #recs
	end
	eq(n, 200)
end)

T("names are not plain text in messages", function()
	local m = ns.Codec.Encode("B", { rec("Bobbington-realm", "Annabelle-realm", 1) })[1]
	ok(not m:find("Bobbington", 1, true) and not m:find("Annabelle", 1, true))
end)

T("messages contain no NUL or pipe", function()
	local m = ns.Codec.Encode("B", { rec("Zoë-draenor", "Ann-realm", -1, { 14 }) })[1]
	ok(not m:find("%z") and not m:find("|", 1, true))
end)

T("garbage never raises", function()
	for _, junk in ipairs({ "", "x", "\255\255\255", string.rep("A", 255), "1B", "9B" .. string.rep("z", 40) }) do
		local okCall, kind = pcall(ns.Codec.Decode, junk)
		ok(okCall, "Decode raised on junk")
		eq(kind, nil)
	end
end)

T("truncated real message is rejected", function()
	local m = ns.Codec.Encode("B", { rec("Bob-realm", "Ann-realm", 1, { 1, 2 }) })[1]
	eq((ns.Codec.Decode(m:sub(1, #m - 3))), nil)
end)

T("reply carries its addressee", function()
	local msgs = ns.Codec.Encode("R", { rec("Bob-realm", "Ann-realm", 1) }, "Newbie-realm")
	local kind, recs, to = ns.Codec.Decode(msgs[1])
	eq(kind, "R")
	eq(to, "Newbie-realm")
	eq(#recs, 1)
end)

T("long reply keeps the addressee in every message", function()
	local list = {}
	for i = 1, 50 do
		list[i] = rec("Target" .. i .. "-realm", "Author" .. i .. "-realm", 1, { 1 })
	end
	local msgs = ns.Codec.Encode("R", list, "Newbie-realm")
	ok(#msgs > 1)
	for _, m in ipairs(msgs) do
		ok(#m <= ns.Tunables.MSG_MAX)
		local _, _, to = ns.Codec.Decode(m)
		eq(to, "Newbie-realm")
	end
end)

T("deny kind round-trips", function()
	local kind, recs = ns.Codec.Decode(ns.Codec.Encode("D", { rec("Bob-realm", "Ann-realm", 0) })[1])
	eq(kind, "D")
	eq(recs[1].vote, 0)
end)

T("summary round-trips", function()
	local s = { count = 12, buckets = { [0] = 1700000000, [5] = 1700000500 } }
	local kind, back = ns.Codec.Decode(ns.Codec.Encode("S", s)[1])
	eq(kind, "S")
	eq(back, s)
end)
