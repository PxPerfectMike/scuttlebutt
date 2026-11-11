-- Scuttlebutt: start-up, saved data, wiring and slash commands.

local ADDON, ns = ...

local App = {}
ns.App = App

local T = ns.Tunables
local Names = ns.Names

local DEFAULTS = {
	tooltip = true,
	groupFinder = true,
	nameplates = true,
	excludeGrumps = false,
	network = true,
	quickVote = true,
	minimapAngle = 0,
	minimapHidden = false,
}

local function Print(msg)
	print("|cff88ccffScuttlebutt:|r " .. msg)
end
App.Print = Print

local function Now()
	return GetServerTime()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

App.Settings = {}
local listeners = {}

function App.Settings.Get(name)
	local value = ScuttlebuttDB.settings[name]
	if value == nil then
		return DEFAULTS[name]
	end
	return value
end

function App.Settings.Set(name, value)
	ScuttlebuttDB.settings[name] = value
	for _, fn in ipairs(listeners) do
		pcall(fn, name, value)
	end
end

function App.OnSettingChanged(fn)
	listeners[#listeners + 1] = fn
end

---------------------------------------------------------------------------
-- Scores and votes
---------------------------------------------------------------------------

function App.Score(key)
	return App.trust:Score(key, {
		now = Now(),
		excludeGrumps = App.Settings.Get("excludeGrumps"),
		inCircle = ns.Presence.InCircle,
	})
end

function App.Level()
	return UnitLevel("player") or 0
end

-- Returns true, or false and a reason from Guard ("self", "level", "absent", "sour", "cap") or
-- "offline" when the network is switched off. A change that only takes something away (a like,
-- a dislike or a tag) is always allowed.
function App.CanVote(key, vote, tags)
	if not App.Settings.Get("network") then
		return false, "offline"
	end
	if tags and ns.Guard.IsRemoval(App.store:Get(key, App.me), vote, tags) then
		if key == App.me or App.guard:IsMine(key) then
			return false, "self"
		end
		return true
	end
	return App.guard:CanVote(key, vote, {
		me = App.me,
		level = App.Level(),
		eligible = ns.Presence.IsEligible(key, Now()),
		now = Now(),
	})
end

-- vote: 1, -1 or 0 (no thumbs, tags only or cleared). tags: list of tag ids, at most MAX_TAGS.
function App.Vote(key, vote, tags)
	local good, reason = App.CanVote(key, vote, tags)
	if not good then
		return false, reason
	end
	local now = Now()
	-- One vote per account: clear every vote other characters on this account cast on them.
	for _, other in ipairs(App.guard:AccountVotes(App.store, key, App.me)) do
		if other.vote ~= 0 or #other.tags > 0 then
			App.sync:Vote({ target = key, author = other.author, vote = 0, tags = {}, time = now })
		end
	end
	local current = App.store:Get(key, App.me)
	App.sync:Vote({ target = key, author = App.me, vote = vote, tags = tags or {}, time = now })
	if vote ~= 0 and (not current or current.vote ~= vote) then
		App.guard:Record(vote, now)
	end
	ns.Display.OnChange()
	ns.QuickVote.OnChange(key)
	ns.PlayerFile.OnChange(key)
	return true
end

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------

local active = false
local tickers = {}

local function Changed(target)
	ns.Display.OnChange()
	ns.PlayerFile.OnChange(target)
	ns.QuickVote.OnChange(target)
end

function App.NetworkActive()
	return active
end

function App.StartNetwork()
	if active or not App.Settings.Get("network") or App.Level() < T.MIN_LEVEL then
		return
	end
	active = true
	ns.Channel.Start(function(sender, msg)
		local key = Names.Normalize(sender, App.realm)
		if key then
			App.sync:OnMessage(key, msg)
		end
	end)
	-- Give the channel a moment to join before announcing ourselves.
	C_Timer.After(8, function()
		if active then
			App.sync:Start()
		end
	end)
	tickers[1] = C_Timer.NewTicker(0.5, function()
		if not IsInInstance() and ns.Channel.Joined() then
			App.sync:Pump()
		end
	end)
	tickers[2] = C_Timer.NewTicker(T.TRICKLE_EVERY, function()
		if not IsInInstance() and ns.Channel.Joined() then
			App.sync:Tick()
		end
	end)
end

function App.StopNetwork()
	if not active then
		return
	end
	active = false
	for i, ticker in pairs(tickers) do
		ticker:Cancel()
		tickers[i] = nil
	end
	ns.Channel.Stop()
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

local function SetupData()
	ScuttlebuttDB = ScuttlebuttDB or {}
	local db = ScuttlebuttDB
	-- Version 2 moved the minimap button to the right side of the minimap and brought it back for
	-- everyone who had hidden it, since it now opens your target's file.
	if db.version and db.version < 2 then
		db.settings = db.settings or {}
		db.settings.minimapAngle = nil
		db.settings.minimapHidden = nil
	end
	-- Version 3 fixed our own key (see Start). Before it, every client's own votes looked like
	-- forwards of a player who never sends, so the forger check blocked honest players; drop that
	-- bookkeeping and the blocks it caused.
	if db.version and db.version < 3 and db.trust then
		db.trust.forwards = nil
		db.trust.blocked = nil
		App.upgradedKeys = true
	end
	db.version = 3
	db.created = db.created or Now()
	db.settings = db.settings or {}
	db.store = db.store or {}
	db.guard = db.guard or {}
	db.trust = db.trust or {}
	db.presence = db.presence or {}
	return db
end

-- Moves our votes saved under the old first-name key to our full key. Nothing is sent for the
-- old key: updated clients file its copies under the full key themselves (Store:AdoptShortNames).
local function MoveOwnVotes(from, to)
	local now = Now()
	local moving = {}
	for _, rec in ipairs(App.store:ByAuthor(from)) do
		moving[#moving + 1] = rec
	end
	for _, rec in ipairs(moving) do
		App.store:Remove(rec)
		if (rec.vote ~= 0 or #rec.tags > 0) and not App.store:Get(rec.target, to) then
			App.sync:Vote({ target = rec.target, author = to, vote = rec.vote, tags = rec.tags, time = now })
		end
	end
end

-- Sends our votes again with a fresh time, so they beat any older copy filed under our key.
local function RestampOwnVotes()
	local now = Now()
	local own = {}
	for _, rec in ipairs(App.store:ByAuthor(App.me)) do
		if rec.vote ~= 0 or #rec.tags > 0 then
			own[#own + 1] = rec
		end
	end
	for _, rec in ipairs(own) do
		App.sync:Vote({ target = rec.target, author = App.me, vote = rec.vote, tags = rec.tags, time = now })
	end
end

local function Start()
	local db = SetupData()
	App.realm = GetNormalizedRealmName() or GetRealmName()
	-- On Forever, characters have a surname: UnitName gives "Scrow" but chat senders, nameplates
	-- and every other player's key use the full "Scrow Tumwater". Our key has to match what other
	-- clients see as the sender, or our votes reach them as unconfirmed forwards.
	App.me = Names.Normalize(GetUnitName("player", true) or UnitName("player"), App.realm)
	App.store = ns.Store.New(db.store)
	App.guard = ns.Guard.New(db.guard)
	App.guard:AddCharacter(App.me)
	-- Versions up to 0.1.0 used the first name alone. Treat that key as this account's, so its
	-- votes are moved below and nobody can vote on the old name as someone else.
	local legacy = Names.Normalize(UnitName("player"), App.realm)
	if legacy and legacy ~= App.me then
		App.guard:AddCharacter(legacy)
	end
	App.trust = ns.Trust.New(App.store, db.trust)
	-- Own votes never fade while they say something; fully cleared ones fade like the rest.
	App.store:Prune(Now(), function(rec)
		return App.guard:IsMine(rec.author) and (rec.vote ~= 0 or #rec.tags > 0)
	end)
	App.trust:Prune(Now())
	App.sync = ns.Sync.New({
		me = App.me,
		store = App.store,
		trust = App.trust,
		created = db.created,
		send = ns.Channel.Transmit,
		now = Now,
		random = math.random,
		after = C_Timer.After,
		ownVote = function(rec)
			return App.guard:IsMine(rec.author)
		end,
		onChange = Changed,
	})
	if legacy and legacy ~= App.me then
		MoveOwnVotes(legacy, App.me)
	end
	App.store:AdoptShortNames(function(author, via)
		return Names.IsShortFor(author, via) and not App.trust:WasSeen(author)
	end, Now())
	if App.upgradedKeys then
		-- An unreleased build sent "cleared" copies of moved votes in the same second as the moved
		-- votes themselves; a fresh time makes sure the real vote wins everywhere.
		RestampOwnVotes()
	end
	ns.Presence.Init(db.presence)
	ns.Display.Init()
	ns.Menu.Init()
	ns.QuickVote.Init()
	App.OnSettingChanged(function(name, value)
		if name == "network" then
			if value then
				App.StartNetwork()
			else
				App.StopNetwork()
			end
		elseif name == "nameplates" or name == "excludeGrumps" then
			ns.Display.RefreshPlates()
		end
		ns.QuickVote.Refresh()
		ns.Menu.Refresh()
	end)
	App.StartNetwork()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(_, event, level)
	if event == "PLAYER_LOGIN" then
		Start()
	elseif event == "PLAYER_LEVEL_UP" and (level or 0) >= T.MIN_LEVEL then
		C_Timer.After(1, App.StartNetwork)
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local TOGGLES = {
	tooltip = { "tooltip", "Tooltip scores" },
	nameplates = { "nameplates", "Nameplate scores" },
	quickvote = { "quickVote", "Like and dislike buttons next to your target" },
	groupfinder = { "groupFinder", "Group finder scores" },
	grumps = { "excludeGrumps", "Hide votes from Known Grumps" },
	network = { "network", "Share and receive votes" },
}

local function Status()
	local now = Now()
	local peers = 0
	for _, t in pairs(App.trust.db.seen) do
		if t >= now - 3600 then
			peers = peers + 1
		end
	end
	local stats = App.sync:Stats()
	Print(string.format("%d votes heard, %d players heard from in the last hour.", App.store.count, peers))
	Print(string.format("Messages sent %d, received %d, unreadable %d.", stats.sent, stats.received, stats.junk))
	if App.Level() < T.MIN_LEVEL then
		Print("Sharing starts at level " .. T.MIN_LEVEL .. ". Private notes work now.")
	elseif not App.Settings.Get("network") then
		Print("Sharing is off (/scuttle network).")
	else
		Print("Channel " .. (ns.Channel.Joined() and "joined" or "not joined yet") .. (IsInInstance() and ", paused in this instance." or "."))
	end
	Print("Hide votes from Known Grumps: " .. (App.Settings.Get("excludeGrumps") and "on" or "off"))
end

SLASH_SCUTTLEBUTT1 = "/scuttle"
SLASH_SCUTTLEBUTT2 = "/scuttlebutt"
SlashCmdList.SCUTTLEBUTT = function(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	local word = arg:lower()
	if word == "" then
		ns.Menu.OpenSettings()
	elseif word == "status" then
		Status()
	elseif TOGGLES[word] then
		local setting, label = TOGGLES[word][1], TOGGLES[word][2]
		App.Settings.Set(setting, not App.Settings.Get(setting))
		Print(label .. ": " .. (App.Settings.Get(setting) and "on" or "off"))
	elseif word == "help" then
		Print("/scuttle <name> opens a player's file. /scuttle status, tooltip, nameplates, quickvote, groupfinder, grumps, network.")
	else
		local key = Names.Normalize(arg, App.realm)
		if key then
			ns.PlayerFile.Open(key)
		end
	end
end

_G[ADDON] = ns -- for debugging with /dump Scuttlebutt.App
