-- Scuttlebutt: records and messages to and from compact strings.
--
-- Message: version digit, kind, then the payload. Kinds: "S" summary, "R" reply to a summary
-- (addressee first), "B" batch, "D" denial (an author's true records, sent when it hears a newer
-- record "by" itself that it never cast).
-- Digits are base 93 over printable ASCII 33..126 without "|" (WoW's escape character).
-- Record: target, author (each a length digit plus scrambled bytes), vote digit (0 = dislike,
-- 1 = cleared, 2 = like), tag count digit and tag digits, time as 5 digits.
-- Summary: record count (3 digits), bucket count (1 digit), then per bucket its index and newest
-- time. Names are scrambled with a reversible byte shuffle so they aren't plain text; it is not
-- encryption and doesn't need to be (addon messages never show in chat).

local _, ns = ...

local Codec = {}
ns.Codec = Codec

local T = ns.Tunables

-- Builds a 0-based list of the bytes lo..hi except "|", and the reverse lookup.
local function Alphabet(lo, hi)
	local list, index, n = {}, {}, 0
	for b = lo, hi do
		if b ~= 124 then
			list[n] = b
			index[b] = n
			n = n + 1
		end
	end
	return list, index, n
end

local DIGIT_BYTES, VALUE, BASE = Alphabet(33, 126) -- 93 digits
local DIGITS = {}
for i = 0, BASE - 1 do
	DIGITS[i] = string.char(DIGIT_BYTES[i])
end
local TIME_WIDTH = 5

-- Bytes a scrambled name may use: 32..255 without "|". Names never contain control bytes or "|".
local SAFE, SAFE_INDEX, SAFE_COUNT = Alphabet(32, 255)

local function Num(n, width)
	local out = {}
	for i = width, 1, -1 do
		out[i] = DIGITS[n % BASE]
		n = math.floor(n / BASE)
	end
	if n > 0 then
		error("number too large")
	end
	return table.concat(out)
end

local function Scramble(s, back)
	local out = {}
	for i = 1, #s do
		local idx = SAFE_INDEX[s:byte(i)]
		if not idx then
			error("unsafe byte in name")
		end
		local shift = (i * 37 + 11) % SAFE_COUNT
		if back then
			shift = -shift
		end
		out[i] = string.char(SAFE[(idx + shift) % SAFE_COUNT])
	end
	return table.concat(out)
end

local function Str(s)
	if #s >= BASE then
		error("name too long")
	end
	return DIGITS[#s] .. Scramble(s)
end

local VOTE_DIGIT = { [-1] = 0, [0] = 1, [1] = 2 }

local function EncodeRecord(rec)
	local tags = rec.tags or {}
	local parts = { Str(rec.target), Str(rec.author), DIGITS[VOTE_DIGIT[rec.vote]], DIGITS[#tags] }
	for _, id in ipairs(tags) do
		parts[#parts + 1] = DIGITS[id]
	end
	parts[#parts + 1] = Num(rec.time, TIME_WIDTH)
	return table.concat(parts)
end

local function Header(kind)
	return DIGITS[T.PROTOCOL] .. kind
end

-- Returns a list of messages. Records that can't be encoded are skipped. Kind "R" (a reply to
-- someone's summary) takes the addressee as `to` and repeats it at the start of every message.
function Codec.Encode(kind, payload, to)
	if kind == "S" then
		local parts = { Header("S"), Num(math.min(payload.count or 0, BASE ^ 3 - 1), 3) }
		local idx = {}
		for i in pairs(payload.buckets or {}) do
			idx[#idx + 1] = i
		end
		table.sort(idx)
		parts[#parts + 1] = DIGITS[#idx]
		for _, i in ipairs(idx) do
			parts[#parts + 1] = DIGITS[i] .. Num(payload.buckets[i], TIME_WIDTH)
		end
		return { table.concat(parts) }
	end
	local head = Header(kind)
	if kind == "R" then
		head = head .. Str(to)
	end
	local msgs, current = {}, head
	local empty = current
	for _, rec in ipairs(payload) do
		local good, encoded = pcall(EncodeRecord, rec)
		if good then
			if #current + #encoded > T.MSG_MAX then
				msgs[#msgs + 1] = current
				current = empty
			end
			current = current .. encoded
		end
	end
	if current ~= empty then
		msgs[#msgs + 1] = current
	end
	return msgs
end

-- Reader over one message; every read raises on bad input, Decode catches it.
local function Reader(msg)
	local pos = 1
	local r = {}
	function r.Digit()
		local v = VALUE[msg:byte(pos) or -1]
		if not v then
			error("bad digit")
		end
		pos = pos + 1
		return v
	end
	function r.Num(width)
		local n = 0
		for _ = 1, width do
			n = n * BASE + r.Digit()
		end
		return n
	end
	function r.Str()
		local len = r.Digit()
		if len == 0 or pos + len - 1 > #msg then
			error("bad string")
		end
		local s = msg:sub(pos, pos + len - 1)
		pos = pos + len
		return Scramble(s, true)
	end
	function r.Done()
		return pos > #msg
	end
	function r.Char()
		local c = msg:sub(pos, pos)
		pos = pos + 1
		return c
	end
	return r
end

local DIGIT_VOTE = { [0] = -1, [1] = 0, [2] = 1 }

local function DecodeRecord(r)
	local rec = { target = r.Str(), author = r.Str() }
	rec.vote = DIGIT_VOTE[r.Digit()]
	if not rec.vote then
		error("bad vote")
	end
	local n = r.Digit()
	if n > T.MAX_TAGS then
		error("too many tags")
	end
	rec.tags = {}
	for i = 1, n do
		local id = r.Digit()
		if id == 0 then
			error("bad tag")
		end
		rec.tags[i] = id
	end
	rec.time = r.Num(TIME_WIDTH)
	return rec
end

local function DecodeBody(msg)
	local r = Reader(msg)
	if r.Digit() ~= T.PROTOCOL then
		error("unknown version")
	end
	local kind = r.Char()
	if kind == "S" then
		local s = { count = r.Num(3), buckets = {} }
		for _ = 1, r.Digit() do
			local i = r.Digit()
			if i >= T.SUMMARY_BUCKETS then
				error("bad bucket")
			end
			s.buckets[i] = r.Num(TIME_WIDTH)
		end
		if not r.Done() then
			error("trailing data")
		end
		return kind, s
	elseif kind == "R" or kind == "B" or kind == "D" then
		local to = kind == "R" and r.Str() or nil
		local recs = {}
		repeat
			recs[#recs + 1] = DecodeRecord(r)
		until r.Done()
		return kind, recs, to
	end
	error("unknown kind")
end

-- Returns kind, payload (and the addressee for "R"), or nil and a reason. Never raises.
function Codec.Decode(msg)
	if type(msg) ~= "string" or #msg < 3 or #msg > T.MSG_MAX then
		return nil, "bad length"
	end
	local good, kind, payload, to = pcall(DecodeBody, msg)
	if not good then
		return nil, tostring(kind)
	end
	return kind, payload, to
end
