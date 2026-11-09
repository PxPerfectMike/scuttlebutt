-- Scuttlebutt Spike: checks the game APIs Scuttlebutt depends on. /sbspike <check>
-- Checks: chan, burst, who, plates, lfg, menu, tip, all. Results print to chat and are kept in
-- ScuttlebuttSpikeLog (printed again with /sbspike log).

local CHANNEL = "ScuttlebuttNet"
local PREFIX = "SBspike"
local log = {}
ScuttlebuttSpikeLog = log -- saved on /reload or logout, so the results can be read from disk

local function Out(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	local line = table.concat(parts, " ")
	log[#log + 1] = line
	print("|cff88ccffSpike:|r " .. line)
end

local function Safe(label, fn)
	local ok, a, b, c, d = pcall(fn)
	if ok then
		Out(label, a, b, c, d)
	else
		Out(label, "ERROR", a)
	end
end

local started = {}
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "ScuttlebuttSpike" then
			ScuttlebuttSpikeLog = log -- replace last session's results
		end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, msg, kind, sender, _, _, _, chanName = ...
		if prefix == PREFIX then
			local t = started[msg:sub(1, 6)]
			Out("got", kind, chanName or "", "len", #msg, "from", sender, t and string.format("after %.2fs", GetTime() - t) or "")
		end
	elseif event == "CHAT_MSG_CHANNEL_JOIN" then
		local _, sender, _, _, _, _, _, _, chanName = ...
		if chanName and chanName:find(CHANNEL) then
			Out("join seen:", sender)
		end
	end
end)

local function ChannelId()
	local id = GetChannelName(CHANNEL)
	return id
end

local function Join()
	JoinTemporaryChannel(CHANNEL)
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local cf = _G["ChatFrame" .. i]
		if cf then
			ChatFrame_RemoveChannel(cf, CHANNEL)
		end
	end
	Out("channel id", ChannelId())
end

local function Send(msg)
	started[msg:sub(1, 6)] = GetTime()
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", ChannelId())
	return ok and tostring(result) or ("ERROR " .. tostring(result))
end

local checks = {}

function checks.chan()
	Out("RegisterAddonMessagePrefix", C_ChatInfo.RegisterAddonMessagePrefix(PREFIX))
	Join()
	C_Timer.After(2, function()
		Out("id after 2s", ChannelId())
		Out("send 255:", Send("A00001" .. string.rep("x", 249)))
		Out("send 256:", Send("A00002" .. string.rep("x", 250)))
		Out("send high bytes:", Send("A00003" .. "Zo\195\171-\200\250~"))
		Out("in instance:", IsInInstance())
	end)
end

function checks.burst()
	if ChannelId() == 0 then
		Join()
	end
	C_Timer.After(1, function()
		for i = 1, 40 do
			Out("burst", i, Send(string.format("B%05d", i)))
		end
	end)
end

function checks.who()
	Safe("mouseover", function()
		return UnitName("mouseover")
	end)
	Safe("target", function()
		return UnitName("target")
	end)
	Safe("UnitFullName target", function()
		return UnitFullName("target")
	end)
	Safe("realm", function()
		return GetNormalizedRealmName(), GetRealmName()
	end)
	Safe("level", function()
		return UnitLevel("player")
	end)
	Out("issecretvalue exists", issecretvalue ~= nil)
	Safe("faction", function()
		return UnitFactionGroup("player")
	end)
end

function checks.plates()
	if not C_NamePlate then
		Out("no C_NamePlate")
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		Safe("plate " .. tostring(unit), function()
			return UnitName(unit), UnitIsPlayer(unit)
		end)
	end
	Out("in instance:", IsInInstance())
end

function checks.lfg()
	Out("C_LFGList", C_LFGList ~= nil, "LFGListFrame", LFGListFrame ~= nil, "PVEFrame", PVEFrame ~= nil, "GroupFinderFrame", GroupFinderFrame ~= nil)
	if C_LFGList then
		Safe("search results", function()
			local n, list = C_LFGList.GetSearchResults()
			return n, list and #list
		end)
		Safe("applicants", function()
			local list = C_LFGList.GetApplicants()
			return list and #list
		end)
		Out("LFGListSearchEntry_Update", LFGListSearchEntry_Update ~= nil, "LFGListApplicationViewer_UpdateApplicantMember", LFGListApplicationViewer_UpdateApplicantMember ~= nil)
	end
	Out("LFGBrowseFrame", LFGBrowseFrame ~= nil, "C_LFGBrowse", C_LFGBrowse ~= nil)
end

-- Maps Forever's group browser: global LFGBrowse* functions, C_LFGList functions, frame children.
function checks.lfg2()
	local names = {}
	for k, v in pairs(_G) do
		if type(k) == "string" and k:find("^LFGBrowse") and type(v) == "function" then
			names[#names + 1] = k
		end
	end
	table.sort(names)
	Out("LFGBrowse functions:", table.concat(names, ", "))
	local api = {}
	for k in pairs(C_LFGList or {}) do
		api[#api + 1] = k
	end
	table.sort(api)
	Out("C_LFGList:", table.concat(api, ", "))
	if LFGBrowseFrame then
		local keys = {}
		for k, v in pairs(LFGBrowseFrame) do
			if type(k) == "string" and type(v) == "table" then
				keys[#keys + 1] = k
			end
		end
		table.sort(keys)
		Out("LFGBrowseFrame children:", table.concat(keys, ", "))
		local box = LFGBrowseFrame.ScrollBox
		Out("ScrollBox", box ~= nil, box and box.ForEachFrame ~= nil)
		if box and box.ForEachFrame then
			box:ForEachFrame(function(entry)
				local ekeys = {}
				for k in pairs(entry) do
					ekeys[#ekeys + 1] = tostring(k)
				end
				table.sort(ekeys)
				Out("entry keys:", table.concat(ekeys, ", "))
				Out("entry resultID", entry.resultID, "GetElementData", entry.GetElementData ~= nil)
				return true
			end)
		end
	end
end

function checks.menu()
	Out("Menu.ModifyMenu", Menu ~= nil and Menu.ModifyMenu ~= nil, "UnitPopup_ShowMenu", UnitPopup_ShowMenu ~= nil)
	if Menu and Menu.ModifyMenu then
		for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET" }) do
			Menu.ModifyMenu(tag, function(_, root)
				root:CreateDivider()
				root:CreateButton("Spike test (" .. tag .. ")", function()
					Out("menu clicked", tag)
				end)
			end)
		end
		Out("menu hooks added: right-click a player")
	end
end

function checks.tip()
	Out("TooltipDataProcessor", TooltipDataProcessor ~= nil, "Settings.RegisterCanvasLayoutCategory", Settings ~= nil and Settings.RegisterCanvasLayoutCategory ~= nil)
	if TooltipDataProcessor and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
			local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
			if ok and unit and UnitIsPlayer(unit) then
				tooltip:AddLine("|cff88ccffSpike tooltip line|r")
			end
		end)
		Out("tooltip hook added: mouse over a player")
	end
end

function checks.all()
	checks.who()
	checks.tip()
	checks.menu()
	checks.lfg()
	checks.plates()
	checks.chan()
end

function checks.log()
	for _, line in ipairs(log) do
		print(line)
	end
end

SLASH_SCUTTLEBUTTSPIKE1 = "/sbspike"
SlashCmdList.SCUTTLEBUTTSPIKE = function(arg)
	local fn = checks[(arg or ""):lower():match("^%s*(%S*)")]
	if fn then
		fn()
	else
		Out("checks: all, chan, burst, who, plates, lfg, lfg2, menu, tip, log")
	end
end
