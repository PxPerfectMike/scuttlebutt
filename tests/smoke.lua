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
				if k == "GetFrameLevel" then
					return 5
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
	rawset(f, "Click", function(self, mouse)
		scripts.OnClick(self, mouse)
	end)
	rawset(f, "Script", function(_, s)
		return scripts[s]
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
-- Forever characters have a surname that UnitName leaves out.
function GetUnitName(unit)
	if unit == "player" then
		return "Tester Tumwater"
	end
	return "Bob"
end
function UnitLevel()
	return 20
end
function UnitIsPlayer()
	return true
end
function UnitIsUnit()
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

-- Saved data from 0.1.0, when the key was the first name alone: one like on Cy, a like from
-- another 0.1.0 player that reached us signed with his first name, and a forger block it caused.
ScuttlebuttDB = {
	version = 1,
	trust = { blocked = { ["Dandelion-argentdawn"] = clock + 3600 } },
	created = 1,
	settings = {},
	store = {
		records = {
			["Cy-argentdawn"] = {
				["Tester-argentdawn"] = { target = "Cy-argentdawn", author = "Tester-argentdawn", vote = 1, tags = { 2 }, time = clock - 100, witnessed = true },
				["Dan-argentdawn"] = { target = "Cy-argentdawn", author = "Dan-argentdawn", vote = 1, tags = {}, time = clock - 50, witnessed = false, via = "Dandelion-argentdawn" },
			},
		},
	},
}

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
assert(ns.App.me == "Testertumwater-argentdawn", "me = " .. tostring(ns.App.me))
-- The old first-name key's like moved to the full key; the old copy is cleared.
local moved = ns.App.store:Get("Cy-argentdawn", "Testertumwater-argentdawn")
assert(moved and moved.vote == 1 and moved.tags[1] == 2, "legacy vote not moved")
assert(ns.App.store:Get("Cy-argentdawn", "Tester-argentdawn") == nil, "legacy vote not removed")
local dan = ns.App.store:Get("Cy-argentdawn", "Dandelion-argentdawn")
assert(dan and dan.witnessed and ns.App.store:Get("Cy-argentdawn", "Dan-argentdawn") == nil, "short-name forward not adopted")
assert(not ns.App.trust:SenderBlocked("Dandelion-argentdawn", clock), "upgrade should lift forger blocks")
assert(ns.App.guard:IsMine("Tester-argentdawn"), "legacy key should count as this account")

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
assert(ns.App.store:Get("Bob-argentdawn", ns.App.me).vote == 1)
ns.PlayerFile.Refresh()
ns.App.store:SetNote("Bob-argentdawn", "Great healer")

-- Tooltip and menu hooks run without errors.
tooltipHook(setmetatable({
	GetUnit = function()
		return "Bob", "mouseover"
	end,
}, { __index = Any("Tooltip") }))
menuHooks.MENU_UNIT_PLAYER(nil, Any("Root"), { name = "Bob", server = "ArgentDawn" })

-- Quick vote buttons: a target with a plate, a like, taking it back, right-click, and the minimap
-- button opening the target's file.
for _, f in ipairs(frames) do
	f:Fire("PLAYER_TARGET_CHANGED")
end
for _, fn in ipairs(timers) do
	fn()
end
timers = {}
assert(ns.QuickVote.TargetKey() == "Bob-argentdawn", "target key")
local quickLike
for _, f in ipairs(frames) do
	if rawget(f, "value") == 1 then
		quickLike = f
	end
end
assert(quickLike, "no quick like button")
ns.App.Vote("Bob-argentdawn", 0, { 1, 5 })
quickLike:Click("LeftButton")
local rec = ns.App.store:Get("Bob-argentdawn", ns.App.me)
assert(rec.vote == 1 and #rec.tags == 2, "quick like lost the tags or did not vote")
clock = clock + 1
quickLike:Click("LeftButton")
assert(ns.App.store:Get("Bob-argentdawn", ns.App.me).vote == 0, "second click should take the like back")
quickLike:Click("RightButton")
quickLike:Script("OnEnter")(quickLike)
_G.ScuttlebuttMinimapButton:Click("LeftButton")
_G.ScuttlebuttMinimapButton:Click("RightButton")
_G.ScuttlebuttMinimapButton:Script("OnEnter")(_G.ScuttlebuttMinimapButton)
slash("quickvote")
slash("quickvote")

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
