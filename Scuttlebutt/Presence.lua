-- Scuttlebutt: who is "online now" (seen in the last few minutes), who you grouped with
-- recently, and who is in your circle (friends and guild).

local _, ns = ...

local Presence = {}
ns.Presence = Presence

local T = ns.Tunables

local seen = {} -- [key] = last time seen online
local friends, guild = {}, {}
local db -- saved: db.grouped[key] = last time in a group with them

-- Runs fn and returns its first result, or nil if it errors or returns a hidden (secret) value.
function Presence.Readable(fn)
	local good, value = pcall(fn)
	if not good then
		return nil
	end
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

function Presence.KeyForUnit(unit)
	local name = Presence.Readable(function()
		return GetUnitName(unit, true)
	end)
	if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then
		return nil
	end
	return ns.Names.Normalize(name, ns.App.realm)
end

local function Now()
	return GetServerTime()
end

function Presence.Seen(key, now)
	if key then
		seen[key] = now or Now()
	end
end

local function SeeUnit(unit)
	local isPlayer = Presence.Readable(function()
		return UnitIsPlayer(unit)
	end)
	if isPlayer then
		Presence.Seen(Presence.KeyForUnit(unit))
	end
end

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. i
		end
	else
		for i = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

local function UpdateGroup()
	local now = Now()
	for _, unit in ipairs(GroupUnits()) do
		local key = Presence.KeyForUnit(unit)
		if key and key ~= ns.App.me then
			db.grouped[key] = now
			seen[key] = now
		end
	end
end

local function UpdateFriends()
	friends = {}
	if not (C_FriendList and C_FriendList.GetNumFriends) then
		return
	end
	for i = 1, C_FriendList.GetNumFriends() do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		if info and info.name then
			local key = ns.Names.Normalize(info.name, ns.App.realm)
			if key then
				friends[key] = info.connected and true or false
			end
		end
	end
end

local function UpdateGuild()
	guild = {}
	if not IsInGuild() then
		return
	end
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
		local key = name and ns.Names.Normalize(name, ns.App.realm)
		if key then
			guild[key] = online and true or false
		end
	end
end

function Presence.InCircle(key)
	return friends[key] ~= nil or guild[key] ~= nil
end

function Presence.IsEligible(key, now)
	now = now or Now()
	if (seen[key] or 0) >= now - T.ONLINE_RECENT then
		return true
	end
	if friends[key] or guild[key] then
		return true -- online right now
	end
	return (db.grouped[key] or 0) >= now - T.RECENT_GROUP
end

local CHAT_EVENTS = {
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_SAY",
	"CHAT_MSG_YELL",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
}

function Presence.Init(savedDb)
	db = savedDb
	db.grouped = db.grouped or {}
	-- Forget old group entries.
	local cutoff = Now() - T.RECENT_GROUP
	for key, t in pairs(db.grouped) do
		if t < cutoff then
			db.grouped[key] = nil
		end
	end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	frame:RegisterEvent("FRIENDLIST_UPDATE")
	frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	for _, event in ipairs(CHAT_EVENTS) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, a1, a2)
		if event == "UPDATE_MOUSEOVER_UNIT" then
			SeeUnit("mouseover")
		elseif event == "PLAYER_TARGET_CHANGED" then
			SeeUnit("target")
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			SeeUnit(a1)
		elseif event == "GROUP_ROSTER_UPDATE" then
			UpdateGroup()
		elseif event == "FRIENDLIST_UPDATE" then
			UpdateFriends()
		elseif event == "GUILD_ROSTER_UPDATE" then
			UpdateGuild()
		else
			-- Chat: the second argument is the sender.
			local sender = a2
			if issecretvalue and issecretvalue(sender) then
				return
			end
			if type(sender) == "string" and sender ~= "" then
				Presence.Seen(ns.Names.Normalize(sender, ns.App.realm))
			end
		end
	end)
	UpdateGroup()
	UpdateFriends()
	if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
end
