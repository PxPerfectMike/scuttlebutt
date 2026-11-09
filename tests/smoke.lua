-- Loads every addon file the way the game does, against a stubbed WoW API, then logs in and
-- drives the slash commands, the player file and two chat messages. Run by tests/run.py --smoke.
-- It catches nil calls and typos in the game-facing files; it can't tell whether the real API
-- behaves the way the stubs do.

local calls = {}
local function Any(name)
	local obj = {}
	return setmetatable(obj, {
		__index = function(_, k)
			return function(...)
				calls[#calls + 1] = name .. ":" .. tostring(k)
				if k == "GetChecked" or k == "HasFocus" or k == "IsShown" then
					return true
				end
				if k == "GetText" then
					return ""
				end
				if k == "GetWidth" or k == "GetHeight" or k == "GetEffectiveScale" then
					return 140
				end
				if k == "GetCenter" then
					return 100, 100
				end
				if k == "GetID" then
					return 1
				end
				if k == "CreateTexture" or k == "CreateFontString" then
					return Any(name .. "." .. k)
				end
				return nil
			end
		end,
	})
end

local frames = {}
function CreateFrame(kind, name)
	local f = Any("Frame")
	local scripts, events = {}, {}
	rawset(f, "SetScript", function(_, s, fn)
		scripts[s] = fn
	end)
	rawset(f, "RegisterEvent", function(_, e)
		events[e] = true
	end)
	rawset(f, "Fire", function(self, e, ...)
		if events[e] and scripts.OnEvent then
			scripts.OnEvent(self, e, ...)
		end
	end)
	rawset(f, "Click", function(self)
		scripts.OnClick(self)
	end)
	rawset(f, "IsShown", function()
		return true
	end)
	frames[#frames + 1] = f
	if name then
		_G[name] = f
	end
	return f
end

local timers = {}
C_Timer = {
	After = function(_, fn)
		timers[#timers + 1] = fn
	end,
	NewTicker = function(_, fn)
		timers[#timers + 1] = fn
		return { Cancel = function() end }
	end,
}
local clock = 1700000000
function GetServerTime()
	return clock
end
function GetNormalizedRealmName()
	return "ArgentDawn"
end
function GetRealmName()
	return "Argent Dawn"
end
function UnitName(unit)
	if unit == "player" then
		return "Tester"
	end
	return "Bob"
end
function GetUnitName()
	return "Bob"
end
function UnitLevel()
	return 20
end
function UnitIsPlayer()
	return true
end
function IsInInstance()
	return false
end
function IsInRaid()
	return false
end
function GetNumSubgroupMembers()
	return 1
end
function GetNumGroupMembers()
	return 1
end
function IsInGuild()
	return true
end
function GetNumGuildMembers()
	return 1
end
function GetGuildRosterInfo()
	return "Guildie-ArgentDawn", nil, nil, nil, nil, nil, nil, nil, true
end
C_GuildInfo = { GuildRoster = function() end }
C_FriendList = {
	GetNumFriends = function()
		return 1
	end,
	GetFriendInfoByIndex = function()
		return { name = "Pal", connected = true }
	end,
}
local sent = {}
local channelId = 5
C_ChatInfo = {
	RegisterAddonMessagePrefix = function()
		return true
	end,
	SendAddonMessage = function(prefix, msg, kind, id)
		sent[#sent + 1] = msg
		return 0
	end,
}
function GetChannelName()
	return channelId
end
function JoinTemporaryChannel() end
function LeaveChannelByName() end
function ChatFrame_RemoveChannel() end
NUM_CHAT_WINDOWS = 2
ChatFrame1, ChatFrame2 = Any("ChatFrame1"), Any("ChatFrame2")
UISpecialFrames = {}
tinsert = table.insert
UIParent = Any("UIParent")
Minimap = Any("Minimap")
GameTooltip = Any("GameTooltip")
ChatFontNormal = {}
function GetCursorPosition()
	return 0, 0
end
function GetMinimapShape()
	return "ROUND"
end
function hooksecurefunc() end
issecretvalue = function()
	return false
end
Enum = { TooltipDataType = { Unit = 2 } }
local tooltipHook
TooltipDataProcessor = {
	AddTooltipPostCall = function(_, fn)
		tooltipHook = fn
	end,
}
local menuHooks = {}
Menu = {
	ModifyMenu = function(tag, fn)
		menuHooks[tag] = fn
	end,
}
Settings = {
	RegisterCanvasLayoutCategory = function()
		return Any("Category")
	end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function() end,
}
C_NamePlate = {
	GetNamePlates = function()
		return { setmetatable({ namePlateUnitToken = "nameplate1" }, { __index = Any("Plate") }) }
	end,
	GetNamePlateForUnit = function()
		return setmetatable({}, { __index = Any("Plate") })
	end,
}
SlashCmdList = {}

-- Load the addon in .toc order.
local ns = {}
for _, file in ipairs(ADDON_FILES) do
	local fn = assert(loadstring(ADDON_SOURCE[file], "@Scuttlebutt/" .. file))
	fn("Scuttlebutt", ns)
end

-- Log in.
for _, f in ipairs(frames) do
	f:Fire("PLAYER_LOGIN")
end
for _ = 1, 3 do
	local pending = timers
	timers = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end
assert(ns.App.me == "Tester-argentdawn", "me = " .. tostring(ns.App.me))

-- Slash commands.
local slash = SlashCmdList.SCUTTLEBUTT
for _, cmd in ipairs({ "", "status", "help", "tooltip", "tooltip", "grumps", "nameplates", "groupfinder", "Bob" }) do
	slash(cmd)
end

-- Vote through the app as the player file would.
for _, f in ipairs(frames) do
	f:Fire("UPDATE_MOUSEOVER_UNIT")
end
local good, reason = ns.App.Vote("Bob-argentdawn", 1, { 1, 5 })
assert(good, "vote failed: " .. tostring(reason))
assert(ns.App.store:Get("Bob-argentdawn", "Tester-argentdawn").vote == 1)
ns.PlayerFile.Refresh()
ns.App.store:SetNote("Bob-argentdawn", "Great healer")

-- Tooltip and menu hooks run without errors.
tooltipHook(setmetatable({
	GetUnit = function()
		return "Bob", "mouseover"
	end,
}, { __index = Any("Tooltip") }))
menuHooks.MENU_UNIT_PLAYER(nil, Any("Root"), { name = "Bob", server = "ArgentDawn" })

-- Network: pump sends our summary and the vote; a message from someone else is read.
ns.App.sync:Start()
ns.App.sync:Tick()
ns.App.sync:Pump()
assert(#sent > 0, "nothing sent")
local frameWithAddon
for _, f in ipairs(frames) do
	f:Fire("CHAT_MSG_ADDON", "Scuttlebutt", ns.Codec.Encode("B", {
		{ target = "Cy-argentdawn", author = "Dee-argentdawn", vote = -1, tags = { 9 }, time = clock },
	})[1], "CHANNEL", "Dee-ArgentDawn")
end
assert(ns.App.store:Get("Cy-argentdawn", "Dee-argentdawn"), "channel message not stored")
ns.Display.RefreshPlates()

-- Network off and on again.
slash("network")
slash("network")
print("smoke: " .. #sent .. " messages sent, " .. ns.App.store.count .. " records, all steps ran")
