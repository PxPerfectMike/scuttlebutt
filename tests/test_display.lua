T("format score colors", function()
	eq(ns.Display.FormatScore({ likes = 35, dislikes = 7 }), "|cff40ff4035|r / |cffff40407|r")
end)

T("format score with no votes", function()
	eq(ns.Display.FormatScore({ likes = 0, dislikes = 0 }), "No word yet")
end)

T("top tags by count, ties by id, at most 3", function()
	local labels = ns.Display.TopTags({ [5] = 2, [1] = 4, [9] = 2, [14] = 1 }, 3)
	eq(labels, { "Great Tank", "Friendly", "Ninja Looter" })
end)

T("top tags skip unknown ids", function()
	eq(ns.Display.TopTags({ [77] = 9, [2] = 1 }, 3), { "Great Healer" })
end)
