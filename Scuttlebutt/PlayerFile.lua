-- Scuttlebutt: the player file. Score, tags, your like or dislike, and your private note.
-- Voters' names are never shown.

local _, ns = ...

local PlayerFile = {}
ns.PlayerFile = PlayerFile

local T = ns.Tunables

local REASONS = {
	self = "You can't rate yourself or your own characters.",
	level = "Reach level 9 to rate players.",
	absent = "You can rate players who are online near you, or who you grouped with in the last day.",
	cap = "Easy there. Even the town crier needs a break.",
	sour = "You've been pretty sour lately. Dislikes are paused for a day.",
	offline = "Sharing is off. Turn it on with /scuttle network.",
	tags = "Up to 3 tags per player.",
}
PlayerFile.REASONS = REASONS

local WIDTH, HEIGHT = 380, 470
local frame, key
local ui = {}

local function Own()
	return ns.App.store:Get(key, ns.App.me)
end

local function OwnTags()
	local own = Own()
	local set = {}
	for _, id in ipairs(own and own.tags or {}) do
		set[id] = true
	end
	return set
end

local function ShowReason(reason)
	ui.reason:SetText(reason and REASONS[reason] or "")
end

local function Cast(vote, tags)
	local good, reason = ns.App.Vote(key, vote, tags)
	ShowReason(not good and reason or nil)
	PlayerFile.Refresh()
end

local function OnThumb(value)
	local own = Own()
	local current = own and own.vote or 0
	local tags = own and own.tags or {}
	Cast(current == value and 0 or value, tags)
end

local function OnTag(check)
	local set = OwnTags()
	set[check.tagId] = check:GetChecked() and true or nil
	local list = {}
	for _, tag in ipairs(T.TAGS) do
		if set[tag.id] then
			list[#list + 1] = tag.id
		end
	end
	if #list > T.MAX_TAGS then
		check:SetChecked(false)
		ShowReason("tags")
		return
	end
	local own = Own()
	Cast(own and own.vote or 0, list)
end

local function MakeButton(parent, label, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(150, 26)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Build()
	frame = CreateFrame("Frame", "ScuttlebuttPlayerFile", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "ScuttlebuttPlayerFile")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	ui.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	ui.title:SetPoint("TOP", 0, -20)
	ui.realm = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	ui.realm:SetPoint("TOP", ui.title, "BOTTOM", 0, -2)

	ui.score = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	ui.score:SetPoint("TOP", ui.realm, "BOTTOM", 0, -10)
	ui.detail = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	ui.detail:SetPoint("TOP", ui.score, "BOTTOM", 0, -6)
	ui.grump = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	ui.grump:SetPoint("TOP", ui.detail, "BOTTOM", 0, -4)
	ui.grump:SetTextColor(1, 0.55, 0.1)
	ui.grump:SetText("Known Grump")

	ui.like = MakeButton(frame, "Like", function()
		OnThumb(1)
	end)
	ui.like:SetPoint("TOPRIGHT", frame, "TOP", -6, -122)
	ui.dislike = MakeButton(frame, "Dislike", function()
		OnThumb(-1)
	end)
	ui.dislike:SetPoint("TOPLEFT", frame, "TOP", 6, -122)

	local tagLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tagLabel:SetPoint("TOPLEFT", 24, -158)
	tagLabel:SetText("Tags (up to 3)")

	ui.tags = {}
	local good, bad = 0, 0
	for _, tag in ipairs(T.TAGS) do
		local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		local row = tag.good and good or bad
		check:SetPoint("TOPLEFT", tag.good and 22 or (WIDTH / 2 + 4), -176 - row * 22)
		local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		text:SetPoint("LEFT", check, "RIGHT", 2, 0)
		text:SetText(tag.label)
		if tag.good then
			text:SetTextColor(0.5, 1, 0.5)
			good = good + 1
		else
			text:SetTextColor(1, 0.5, 0.5)
			bad = bad + 1
		end
		check.tagId = tag.id
		check.count = check:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		check.count:SetPoint("LEFT", text, "RIGHT", 4, 0)
		check:SetScript("OnClick", OnTag)
		ui.tags[#ui.tags + 1] = check
	end

	ui.reason = frame:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
	ui.reason:SetPoint("TOPLEFT", 24, -356)
	ui.reason:SetWidth(WIDTH - 48)
	ui.reason:SetJustifyH("LEFT")

	local noteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	noteLabel:SetPoint("TOPLEFT", 24, -380)
	noteLabel:SetText("Private note (only on this computer)")

	local noteBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	noteBox:SetPoint("TOPLEFT", 20, -398)
	noteBox:SetPoint("BOTTOMRIGHT", -20, 18)
	noteBox:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	noteBox:SetBackdropColor(0, 0, 0, 0.6)

	local scroll = CreateFrame("ScrollFrame", nil, noteBox, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -26, 6)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(WIDTH - 80)
	edit:SetMaxLetters(1000)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and key then
			ns.App.store:SetNote(key, self:GetText())
		end
	end)
	scroll:SetScrollChild(edit)
	noteBox:EnableMouse(true)
	noteBox:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	ui.note = edit
end

local function SetThumb(button, label, on, enabled)
	button:SetText(on and ("|cffffd100" .. label .. "d|r") or label)
	button:SetEnabled(enabled)
end

function PlayerFile.Refresh()
	if not frame or not frame:IsShown() or not key then
		return
	end
	local score = ns.App.Score(key)
	local name, realm = key:match("^([^%-]+)%-(.+)$")
	ui.title:SetText(name or key)
	ui.realm:SetText(realm or "")
	ui.score:SetText(ns.Display.FormatScore(score))
	local parts = { "based on what reached you" }
	if score.circle > 0 then
		parts[#parts + 1] = score.circle .. " from your circle"
	end
	if score.unconfirmed > 0 then
		parts[#parts + 1] = score.unconfirmed .. " unconfirmed"
	end
	ui.detail:SetText(table.concat(parts, " · "))
	ui.grump:SetShown(score.grump)

	local own = Own()
	local vote = own and own.vote or 0
	local canLike, likeReason = ns.App.CanVote(key, 1)
	local canDislike, dislikeReason = ns.App.CanVote(key, -1)
	-- Taking back your own vote is always allowed once you could vote at all.
	SetThumb(ui.like, "Like", vote == 1, canLike or vote == 1)
	SetThumb(ui.dislike, "Dislike", vote == -1, canDislike or vote == -1)
	ShowReason(not canLike and likeReason or (not canDislike and dislikeReason) or nil)

	local mine = OwnTags()
	for _, check in ipairs(ui.tags) do
		check:SetChecked(mine[check.tagId] or false)
		check:SetEnabled(canLike or mine[check.tagId] or false)
		local n = score.tags[check.tagId]
		check.count:SetText(n and ("(" .. n .. ")") or "")
	end
	if not ui.note:HasFocus() then
		ui.note:SetText(ns.App.store:GetNote(key) or "")
	end
end

function PlayerFile.Open(target)
	if not frame then
		Build()
	end
	key = target
	ui.note:SetText(ns.App.store:GetNote(key) or "")
	frame:Show()
	PlayerFile.Refresh()
end

function PlayerFile.OnChange(target)
	if target == key then
		PlayerFile.Refresh()
	end
end
