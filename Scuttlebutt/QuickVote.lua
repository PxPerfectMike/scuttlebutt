-- Scuttlebutt: thumbs up and thumbs down buttons and the score next to your target, so voting
-- takes one click.
-- They sit on the target's nameplate when it has one, otherwise beside the target frame.
-- Right-click either button to open the player's file.

local _, ns = ...

local QuickVote = {}
ns.QuickVote = QuickVote

local SIZE = 22
local GAP = 2
local MEDIA = "Interface\\AddOns\\Scuttlebutt\\Media\\"
QuickVote.THUMB_UP = MEDIA .. "ThumbUp"
QuickVote.THUMB_DOWN = MEDIA .. "ThumbDown"

local holder, key, shownName
local buttons = {}
local scoreText

local function Own()
	return key and ns.App.store:Get(key, ns.App.me)
end

-- Your target's key if it's another player you could rate, else nil.
function QuickVote.TargetKey()
	local isPlayer = ns.Presence.Readable(function()
		return UnitIsPlayer("target")
	end)
	if not isPlayer then
		return nil
	end
	local target = ns.Presence.KeyForUnit("target")
	if not target or target == ns.App.me or ns.App.guard:IsMine(target) then
		return nil
	end
	return target
end

-- The target's nameplate, if the game shows one we may touch.
local function TargetPlate()
	if not C_NamePlate then
		return nil
	end
	local good, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not good or not plate then
		return nil
	end
	if plate.IsForbidden and plate:IsForbidden() then
		return nil
	end
	if plate.IsShown and not plate:IsShown() then
		return nil
	end
	return plate
end

local function Layout(vertical)
	local like, dislike = buttons[1], buttons[-1]
	like:ClearAllPoints()
	dislike:ClearAllPoints()
	like:SetPoint("TOPLEFT")
	scoreText:ClearAllPoints()
	if vertical then
		holder:SetSize(SIZE, SIZE * 2 + GAP)
		dislike:SetPoint("TOPLEFT", like, "BOTTOMLEFT", 0, -GAP)
		scoreText:SetPoint("RIGHT", holder, "LEFT", -4, 0)
	else
		holder:SetSize(SIZE * 2 + GAP, SIZE)
		dislike:SetPoint("TOPLEFT", like, "TOPRIGHT", GAP, 0)
		scoreText:SetPoint("LEFT", holder, "RIGHT", 4, 0)
	end
end

local function Place()
	holder:ClearAllPoints()
	local plate = TargetPlate()
	if plate then
		holder:SetParent(plate)
		holder:SetFrameStrata(plate:GetFrameStrata())
		holder:SetFrameLevel(plate:GetFrameLevel() + 10)
		Layout(false)
		holder:SetPoint("LEFT", plate, "RIGHT", -4, 0)
		return true
	end
	if TargetFrame and TargetFrame:IsShown() then
		-- The target frame's mouse area reaches past its art on the left, and its children sit
		-- well above its own level, so the buttons go one strata up to stay clickable.
		holder:SetParent(UIParent)
		holder:SetFrameStrata("MEDIUM")
		holder:SetFrameLevel(TargetFrame:GetFrameLevel() + 50)
		Layout(true)
		holder:SetPoint("RIGHT", TargetFrame, "LEFT", 16, 0)
		return true
	end
	return false
end

local function Paint()
	local own = Own()
	local vote = own and own.vote or 0
	for value, b in pairs(buttons) do
		local on = vote == value
		local r, g, bl = unpack(b.color)
		if on then
			b.icon:SetAlpha(1)
			b:SetBackdropBorderColor(r, g, bl, 1)
			b:SetBackdropColor(r * 0.35, g * 0.35, bl * 0.35, 0.95)
		else
			b.icon:SetAlpha(0.8)
			b:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.9)
			b:SetBackdropColor(0, 0, 0, 0.7)
		end
	end
	local score = ns.App.Score(key)
	scoreText:SetText(string.format("|cff40ff40%d|r / |cffff4040%d|r", score.likes, score.dislikes))
end

local function ShowTooltip(b)
	if not key then
		return
	end
	local name = shownName or key:match("^([^%-]+)") or key
	local own = Own()
	local on = own and own.vote == b.value
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	local word = b.value == 1 and "like" or "dislike"
	if on then
		GameTooltip:AddLine("Take back your " .. word, 1, 1, 1)
	else
		GameTooltip:AddLine((b.value == 1 and "Like " or "Dislike ") .. name, 1, 1, 1)
	end
	GameTooltip:AddLine("Scuttlebutt: " .. ns.Display.FormatScore(ns.App.Score(key)), 0.53, 0.8, 1)
	if not on then
		local good, reason = ns.App.CanVote(key, b.value)
		if not good and ns.PlayerFile.REASONS[reason] then
			GameTooltip:AddLine(ns.PlayerFile.REASONS[reason], 1, 0.3, 0.3, true)
		end
	end
	GameTooltip:AddLine("Right-click to open " .. name .. "'s file", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function OnClick(b, mouse)
	if not key then
		return
	end
	if mouse == "RightButton" then
		ns.PlayerFile.Open(key)
		return
	end
	local own = Own()
	local current = own and own.vote or 0
	local tags = own and own.tags or {}
	local good, reason = ns.App.Vote(key, current == b.value and 0 or b.value, tags)
	if not good then
		ns.App.Print(ns.PlayerFile.REASONS[reason] or "Can't vote right now.")
	end
	QuickVote.Refresh()
	if GameTooltip:IsOwned(b) then
		ShowTooltip(b)
	end
end

local function MakeButton(value, texture, color)
	local b = CreateFrame("Button", nil, holder, "BackdropTemplate")
	b:SetSize(SIZE, SIZE)
	b:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetTexture(texture)
	b.icon:SetPoint("TOPLEFT", 3, -3)
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	b.value = value
	b.color = color
	b:SetScript("OnClick", OnClick)
	b:SetScript("OnEnter", ShowTooltip)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	buttons[value] = b
end

function QuickVote.Refresh()
	if not holder then
		return
	end
	key = nil
	if ns.App.Settings.Get("quickVote") then
		key = QuickVote.TargetKey()
	end
	if not key or not Place() then
		key = nil
		holder:Hide()
		return
	end
	shownName = ns.Presence.Readable(function()
		return UnitName("target")
	end)
	Paint()
	holder:Show()
end

function QuickVote.OnChange(target)
	if holder and target == key then
		Paint()
	end
end

function QuickVote.Init()
	holder = CreateFrame("Frame", "ScuttlebuttQuickVote", UIParent)
	holder:Hide()
	scoreText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	scoreText:SetShadowOffset(1, -1)
	MakeButton(1, QuickVote.THUMB_UP, { 0.25, 1, 0.25 })
	MakeButton(-1, QuickVote.THUMB_DOWN, { 1, 0.25, 0.25 })
	Layout(true)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	events:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_TARGET_CHANGED" or (unit and UnitIsUnit(unit, "target")) then
			-- A plate leaving or arriving moves the buttons; wait a frame so the plate is settled.
			C_Timer.After(0, function()
				pcall(QuickVote.Refresh)
			end)
		end
	end)
end
