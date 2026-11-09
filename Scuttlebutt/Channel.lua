-- Scuttlebutt: the hidden channel. Joins it, keeps it out of every chat window, and moves addon
-- messages in and out. The send queue and throttle live in Sync; this only transmits.

local _, ns = ...

local Channel = {}
ns.Channel = Channel

local NAME = "ScuttlebuttNet"
local PREFIX = "Scuttlebutt"

local onMessage
local frame = CreateFrame("Frame")

local function HideEverywhere()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame then
			if ChatFrame_RemoveChannel then
				pcall(ChatFrame_RemoveChannel, chatFrame, NAME)
			elseif chatFrame.RemoveChannel then
				pcall(chatFrame.RemoveChannel, chatFrame, NAME)
			end
		end
	end
end

function Channel.Id()
	local id = GetChannelName(NAME)
	return id or 0
end

function Channel.Joined()
	return Channel.Id() > 0
end

local function Join()
	if not Channel.Joined() then
		JoinTemporaryChannel(NAME)
	end
	HideEverywhere()
end

local THROTTLED = 3 -- Enum.SendAddonMessageResult.AddonMessageThrottle, measured on Forever

-- Sends one message now. Returns true when sent, false when it should be tried again later
-- (throttled, not joined yet, in an instance), or "failed" when the game won't take it at all.
function Channel.Transmit(msg)
	if IsInInstance() then
		return false
	end
	local id = Channel.Id()
	if id == 0 then
		return false
	end
	local good, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "CHANNEL", id)
	if not good then
		return "failed"
	end
	-- Retail returns an Enum.SendAddonMessageResult (0 = success); older clients return a boolean.
	if result == nil or result == true or result == 0 then
		return true
	end
	if result == THROTTLED or result == false then
		return false
	end
	return "failed"
end

function Channel.Start(handler)
	onMessage = handler
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	frame:RegisterEvent("CHAT_MSG_ADDON")
	frame:RegisterEvent("CHANNEL_UI_UPDATE")
	frame:SetScript("OnEvent", function(_, event, prefix, msg, kind, sender)
		if event == "CHANNEL_UI_UPDATE" then
			HideEverywhere()
		elseif prefix == PREFIX and kind == "CHANNEL" and onMessage then
			if issecretvalue and (issecretvalue(msg) or issecretvalue(sender)) then
				return
			end
			onMessage(sender, msg)
		end
	end)
	Join()
	-- Joining right after login can fail quietly; try again a few times.
	for _, delay in ipairs({ 5, 15, 45 }) do
		C_Timer.After(delay, function()
			if onMessage then
				Join()
			end
		end)
	end
end

function Channel.Stop()
	onMessage = nil
	frame:UnregisterAllEvents()
	if Channel.Joined() then
		LeaveChannelByName(NAME)
	end
end
