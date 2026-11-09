-- Scuttlebutt: the "Scuttlebutt" entry on player right-click menus, the minimap button and the
-- settings panel.

local _, ns = ...

local Menu = {}
ns.Menu = Menu

local ICON = "Interface\\Icons\\INV_Letter_15"
local BUTTON_RIM = 5

local OPTIONS = {
	{ key = "tooltip", label = "Show scores in tooltips" },
	{ key = "nameplates", label = "Show scores on nameplates", note = "Scores on friendly players need friendly player nameplates turned on (Options, Nameplates)." },
	{ key = "groupFinder", label = "Show scores in the group finder" },
	{ key = "excludeGrumps", label = "Hide votes from Known Grumps" },
	{ key = "network", label = "Share and receive votes", note = "Off: nothing is sent or received. Private notes still work." },
	{ key = "minimapHidden", label = "Hide the minimap button" },
}

---------------------------------------------------------------------------
-- Right-click menus
---------------------------------------------------------------------------

local MENU_TAGS = {
	"MENU_UNIT_PLAYER",
	"MENU_UNIT_PARTY",
	"MENU_UNIT_RAID_PLAYER",
	"MENU_UNIT_FRIEND",
	"MENU_UNIT_ENEMY_PLAYER",
	"MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS",
	"MENU_UNIT_GUILD",
	"MENU_UNIT_CHAT_ROSTER",
	"MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
	"MENU_UNIT_COMMUNITIES_MEMBER",
}

local function KeyFromContext(context)
	if not context then
		return nil
	end
	if context.unit then
		local key = ns.Presence.KeyForUnit(context.unit)
		if key then
			return key
		end
	end
	local name = context.name
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if context.server and context.server ~= "" and not name:find("-", 1, true) then
		name = name .. "-" .. context.server
	end
	return ns.Names.Normalize(name, ns.App.realm)
end

local function HookMenus()
	if not (_G.Menu and _G.Menu.ModifyMenu) then
		return
	end
	for _, tag in ipairs(MENU_TAGS) do
		_G.Menu.ModifyMenu(tag, function(_, root, context)
			local key = KeyFromContext(context)
			if not key then
				return
			end
			root:CreateDivider()
			root:CreateButton("Scuttlebutt", function()
				ns.PlayerFile.Open(key)
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- Minimap button (same rim placement as Starfall Trail)
---------------------------------------------------------------------------

local SHAPES = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button, panel, category
local checks = {}

local function PlaceButton()
	local angle = math.rad(ns.App.Settings.Get("minimapAngle") or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local quadrant = 1
	if x < 0 then
		quadrant = quadrant + 1
	end
	if y > 0 then
		quadrant = quadrant + 2
	end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local round = (SHAPES[shape] or SHAPES.ROUND)[quadrant]
	local w = Minimap:GetWidth() / 2 + BUTTON_RIM
	local h = Minimap:GetHeight() / 2 + BUTTON_RIM
	if round then
		x, y = x * w, y * h
	else
		x = math.max(-w, math.min(x * (math.sqrt(2 * w * w) - 10), w))
		y = math.max(-h, math.min(y * (math.sqrt(2 * h * h) - 10), h))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.App.Settings.Set("minimapAngle", math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360)
	PlaceButton()
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Scuttlebutt")
	local now = GetServerTime()
	local peers = 0
	for _, t in pairs(ns.App.trust.db.seen) do
		if t >= now - 3600 then
			peers = peers + 1
		end
	end
	GameTooltip:AddLine(string.format("%d votes heard, %d players in the last hour", ns.App.store.count, peers), 1, 1, 1)
	GameTooltip:AddLine("Click for settings, drag to move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function CreateButton()
	button = CreateFrame("Button", "ScuttlebuttMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(19, 19)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	button:SetScript("OnClick", Menu.OpenSettings)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", DragUpdate)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------

local function CreatePanel()
	panel = CreateFrame("Frame")
	panel.name = "Scuttlebutt"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Scuttlebutt")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetWidth(560)
	sub:SetJustifyH("LEFT")
	sub:SetText("What the realm says about other players, spread by word of mouth. Names of voters aren't shown. Open a player's file by right-clicking them or with /scuttle <name>.")
	local y = -70
	for _, option in ipairs(OPTIONS) do
		local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		check:SetPoint("TOPLEFT", 16, y)
		local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		text:SetPoint("LEFT", check, "RIGHT", 4, 0)
		text:SetText(option.label)
		check:SetScript("OnClick", function(self)
			ns.App.Settings.Set(option.key, self:GetChecked() and true or false)
		end)
		checks[option.key] = check
		y = y - 28
		if option.note then
			local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			note:SetPoint("TOPLEFT", 48, y + 6)
			note:SetWidth(520)
			note:SetJustifyH("LEFT")
			note:SetText(option.note)
			y = y - 16
		end
	end
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "Scuttlebutt")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
	panel:SetScript("OnShow", Menu.Refresh)
end

function Menu.OpenSettings()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

function Menu.Refresh()
	for key, check in pairs(checks) do
		check:SetChecked(ns.App.Settings.Get(key) and true or false)
	end
	if checks.groupFinder and not ns.Display.HasGroupFinder() then
		checks.groupFinder:Disable()
	end
	if button then
		button:SetShown(not ns.App.Settings.Get("minimapHidden"))
	end
end

function Menu.Init()
	HookMenus()
	CreateButton()
	PlaceButton()
	CreatePanel()
	Menu.Refresh()
end
