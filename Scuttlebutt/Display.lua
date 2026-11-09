-- Scuttlebutt: the score where players see it: tooltips, nameplates and the group finder.
-- FormatScore and TopTags are pure; everything that touches the game starts in Display.Init.

local _, ns = ...

local Display = {}
ns.Display = Display

local TAG_LABEL = {}
for _, tag in ipairs(ns.Tunables.TAGS) do
	TAG_LABEL[tag.id] = tag.label
end

function Display.FormatScore(score)
	if score.likes == 0 and score.dislikes == 0 then
		return "No word yet"
	end
	return string.format("|cff40ff40%d|r / |cffff4040%d|r", score.likes, score.dislikes)
end

-- The labels of the n most common known tags, most common first, ties by tag id.
function Display.TopTags(tags, n)
	local list = {}
	for id, count in pairs(tags) do
		if TAG_LABEL[id] then
			list[#list + 1] = { id = id, count = count }
		end
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = TAG_LABEL[list[i].id]
	end
	return out
end

local function HasVotes(score)
	return score.likes > 0 or score.dislikes > 0
end

---------------------------------------------------------------------------
-- In game
---------------------------------------------------------------------------

local NOTE_MAX = 80

local function AddTooltipLines(tooltip, unit)
	if not ns.App.Settings.Get("tooltip") then
		return
	end
	local key = ns.Presence.KeyForUnit(unit)
	if not key then
		return
	end
	local score = ns.App.Score(key)
	tooltip:AddLine("Scuttlebutt: " .. Display.FormatScore(score), 0.53, 0.8, 1)
	local tags = Display.TopTags(score.tags, 3)
	if #tags > 0 then
		tooltip:AddLine(table.concat(tags, ", "), 1, 1, 1, true)
	end
	if score.grump then
		tooltip:AddLine("Known Grump", 1, 0.55, 0.1)
	end
	local note = ns.App.store:GetNote(key)
	if note then
		if #note > NOTE_MAX then
			note = note:sub(1, NOTE_MAX) .. "..."
		end
		tooltip:AddLine(note, 0.7, 0.7, 0.7, true)
	end
end

local function HookTooltip()
	local function OnUnit(tooltip)
		local good, _, unit = pcall(tooltip.GetUnit, tooltip)
		if not good or not unit then
			return
		end
		local isPlayer = ns.Presence.Readable(function()
			return UnitIsPlayer(unit)
		end)
		if isPlayer then
			pcall(AddTooltipLines, tooltip, unit)
		end
	end
	if TooltipDataProcessor and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnit)
	elseif GameTooltip then
		GameTooltip:HookScript("OnTooltipSetUnit", OnUnit)
	end
end

-- Nameplates: a small score line under player names.
local function PlateText(plate)
	if not plate.ScuttlebuttText then
		local text = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("TOP", plate, "BOTTOM", 0, 2)
		plate.ScuttlebuttText = text
	end
	return plate.ScuttlebuttText
end

local function UpdatePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		return
	end
	local text = PlateText(plate)
	text:Hide()
	if not ns.App.Settings.Get("nameplates") then
		return
	end
	local isPlayer = ns.Presence.Readable(function()
		return UnitIsPlayer(unit)
	end)
	if not isPlayer then
		return
	end
	local key = ns.Presence.KeyForUnit(unit)
	if not key then
		return
	end
	local score = ns.App.Score(key)
	if HasVotes(score) then
		text:SetText(Display.FormatScore(score))
		text:Show()
	end
end

function Display.RefreshPlates()
	if not C_NamePlate then
		return
	end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then
			pcall(UpdatePlate, unit)
		elseif plate.ScuttlebuttText then
			plate.ScuttlebuttText:Hide()
		end
	end
end

-- Group finder (retail-style LFG list), only if this client has it.
local function GroupText(parent, anchor)
	if not parent.ScuttlebuttText then
		local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("RIGHT", anchor or parent, anchor and "LEFT" or "RIGHT", -4, 0)
		parent.ScuttlebuttText = text
	end
	return parent.ScuttlebuttText
end

local function ShowGroupScore(frame, name, anchor)
	local text = GroupText(frame, anchor)
	text:Hide()
	if not ns.App.Settings.Get("groupFinder") or type(name) ~= "string" then
		return
	end
	local key = ns.Names.Normalize(name, ns.App.realm)
	if not key then
		return
	end
	local score = ns.App.Score(key)
	if HasVotes(score) then
		text:SetText(Display.FormatScore(score))
		text:Show()
	end
end

local function HookGroupFinder()
	if not C_LFGList then
		return false
	end
	local hooked = false
	if LFGListSearchEntry_Update then
		hooksecurefunc("LFGListSearchEntry_Update", function(entry)
			pcall(function()
				local info = C_LFGList.GetSearchResultInfo(entry.resultID)
				ShowGroupScore(entry, info and info.leaderName, entry.ActivityName)
			end)
		end)
		hooked = true
	end
	-- Forever's Classic-style group browser (LFGBrowseFrame).
	if LFGBrowseSearchEntry_Update then
		hooksecurefunc("LFGBrowseSearchEntry_Update", function(entry)
			pcall(function()
				local info = C_LFGList.GetSearchResultInfo(entry.resultID)
				ShowGroupScore(entry, info and info.leaderName, entry.Name)
			end)
		end)
		hooked = true
	end
	if LFGListApplicationViewer_UpdateApplicantMember then
		hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember", function(member, appID, memberIdx)
			pcall(function()
				local name = C_LFGList.GetApplicantMemberInfo(appID, memberIdx)
				ShowGroupScore(member, name, member.Role)
			end)
		end)
		hooked = true
	end
	return hooked
end

function Display.HasGroupFinder()
	return Display.groupFinderHooked == true
end

-- Called when records about a player change; refreshes what's on screen.
function Display.OnChange()
	if Display.pending then
		return
	end
	Display.pending = true
	C_Timer.After(0.5, function()
		Display.pending = false
		Display.RefreshPlates()
	end)
end

function Display.Init()
	HookTooltip()
	Display.groupFinderHooked = HookGroupFinder()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
	frame:SetScript("OnEvent", function(_, event, unit)
		if event == "NAME_PLATE_UNIT_ADDED" then
			pcall(UpdatePlate, unit)
		else
			local plate = C_NamePlate.GetNamePlateForUnit(unit)
			if plate and plate.ScuttlebuttText then
				plate.ScuttlebuttText:Hide()
			end
		end
	end)
end
