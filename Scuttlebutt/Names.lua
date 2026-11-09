-- Scuttlebutt: one key per player, "Name-realm".
-- The name gets a capital first letter; the realm loses spaces and apostrophes and is lowercased,
-- so "Bob", "Bob-Argent Dawn" and "bob-argentdawn" are the same player. Only ASCII letters change
-- case.

local _, ns = ...

local Names = {}
ns.Names = Names

-- ASCII-only case changes: string.lower/upper follow the C locale, which can rewrite UTF-8 bytes.
local function Lower(s)
	return (s:gsub("[A-Z]", function(c)
		return string.char(c:byte() + 32)
	end))
end

local function Upper(s)
	return (s:gsub("[a-z]", function(c)
		return string.char(c:byte() - 32)
	end))
end

local function CleanRealm(realm)
	if type(realm) ~= "string" then
		return nil
	end
	realm = Lower(realm:gsub("[%s']", ""))
	if realm == "" then
		return nil
	end
	return realm
end

function Names.Normalize(name, defaultRealm)
	if type(name) ~= "string" then
		return nil
	end
	local base, realm = name:match("^([^%-]*)%-(.*)$")
	if not base then
		base = name
	end
	base = Lower(base:gsub("%s", ""))
	if base == "" then
		return nil
	end
	base = Upper(base:sub(1, 1)) .. base:sub(2)
	realm = CleanRealm(realm) or CleanRealm(defaultRealm)
	if not realm then
		return nil
	end
	return base .. "-" .. realm
end

-- The name part, for display.
function Names.Short(key)
	return (key:match("^([^%-]+)")) or key
end
