# Scuttlebutt: design

Date: 11/09/2026. Status: draft for approval.

## What it is and why

Scuttlebutt is a World of Warcraft: Forever addon that tracks a player's reputation across the realm,
spread by word of mouth. Every player who runs it can like or dislike other players, tag them
("Great Healer", "Ninja Looter") and keep private notes. Votes and tags spread from addon to addon
over a hidden in-game channel, the way gossip does. Nobody holds the whole picture, and each player
sees what has reached them.

The Forever community has asked for a player-notes addon. Dossier Forever (released 11/2026) covers
the private-notebook side. Scuttlebutt is different because it is social: it shows what the realm
thinks of a player, not only what you think.

Success means a player mouses over a stranger, sees "35 / 7" with "Great Tank, Friendly", and trusts
it enough to invite them. It also means trolls can't wreck the scores.

## Goals

- A public like/dislike score per player, shown as green likes and red dislikes ("35 / 7").
- Public tags from a fixed list, up to 3 per voter per player.
- Private notes that never leave the player's computer.
- Spread through a hidden addon channel with no outside server and no companion app.
- Names hidden in the UI. Ratings are blurred by forwarding, so a sender is usually not the author.
- Troll guards that work without a central authority, including the public "Known Grump" tag.
- Scores shown in the tooltip, the group finder and on nameplates, each with its own toggle.

## Non-goals

- No central database, website, companion app, or upload of data outside the game.
- No mail. The user asked about it, and it was rejected (postage cost, mailbox-only, inbox clutter,
  spam risk).
- No public free-text comments. Public speech is tags only; free text stays in private notes.
- No combat features. Nothing reads combat data, so Forever's combat restrictions don't apply.

## Anti-goals (failure even if it works)

- Calling it "anonymous" anywhere: in the addon, the README or on CurseForge. The wording is "names
  aren't shown". Real anonymity is impossible (see Privacy), and a broken promise would sink the
  project.
- Flooding the channel or getting players disconnected for sending too much.
- Scores that one person with alts, or a modified client, can swing easily.
- Filling the user's SavedVariables without limit over months of play.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Name | Scuttlebutt. Slash commands `/scuttle` and `/scuttlebutt`. |
| Transport | A hidden custom chat channel, addon messages only. No mail. |
| Sync style | Gossip: no one sends their whole list. On login a client announces a short summary, a few random peers fill the gaps, and news trickles in after that. |
| Score format | Likes / dislikes, e.g. "35 / 7", green and red. One vote per voter per player; changing a vote replaces the old one. |
| Who can be voted on | Any player, anywhere, but only players who are online now or who were grouped with the voter recently. This stops alts from voting for the same account's main, since one account has one character online at a time. |
| Minimum level | Level 9 to vote, tag, or take part in the network. |
| Tags | Fixed list, half positive and half negative (below). Up to 3 per voter per player. The tooltip shows the most common. |
| Private notes | Yes, local only. |
| Privacy | Names never shown in the UI. Payloads use a compact encoding that looks like noise. Votes carry author names (needed for honesty); snoopers with modified addons can read them, accepted. |
| Trust shown | Counts and "N from your circle" (friends and guild), never names. |
| Troll guard | Daily dislike cap, sour-streak pause, other clients discounting habitual dislikers, and a public "Known Grump" tag that wears off. |
| Grump option | Settings option "Exclude Grump votes" removes Grump votes from every score the player sees. |
| Display | Tooltip, group finder, nameplates, each with its own on/off toggle. |

### Tag list

- Good: Great Tank, Great Healer, Great DPS, Knows the Content, Friendly, Generous, Helpful Guide,
  Fair Looter
- Bad: Ninja Looter, Left Mid-Dungeon, Toxic, AFK Leecher, Pulls Everything, Scammer

Tags travel as small numeric IDs, so the list can grow later without breaking older clients (unknown
IDs are kept and forwarded but not shown).

## Privacy and trust model

Facts that shape it:

- The game stamps every addon message with the true sender's name. The addon can't hide or fake it.
- Addon messages never appear in anyone's chat window. They reach other addons only through the
  `CHAT_MSG_ADDON` event. A player who joins the channel by hand sees nothing unless they run a
  sniffer. So scrambling buys very little, and **there is no encryption layer**. A compact encoding,
  needed to fit more into each message anyway, is enough to make it look like noise.
- Anything every Scuttlebutt client can read, anyone can read by installing Scuttlebutt and printing
  what it decodes. Addon code must be readable under Blizzard's policy, and the code is public on
  GitHub.

So the protection is the UI, not secrecy:

- **Each vote carries its author** (Name-Realm) inside the payload. Clients need it to keep one vote
  per voter, to run the Grump check and to stop forgeries. The UI never shows it. Anyone running a
  modified addon can read it; that is accepted (pending the user's confirmation, see Open question).
- **Forwarding** still mixes the client's own votes with sampled votes it has heard, because that is
  how news spreads to players the author never meets. It is not a privacy feature, since the author
  field is in every record.

### Fake votes

A modified client could forward votes it made up, in the name of invented players or of real ones.
Defense: **witnessed votes**. The game proves who sent each batch, so:

- A vote is **witnessed** when this client received it in a batch sent by its own author. Witnessed
  votes count at full weight.
- A vote heard only secondhand counts at reduced weight (suggested 0.25) and shows in the player's
  file as "unconfirmed". It becomes witnessed if the author's own batch later carries it.
- Each client re-sends its own votes slowly over time (see Storage and fade), so active voters' votes
  get witnessed by more and more players.
- **Grump status is judged only from witnessed votes.** A troll can't make an innocent player look
  like a Grump by forwarding fake dislikes in their name.
- Per-sender damage limit: a sender whose forwarded records keep failing to be witnessed (records
  attributed to authors who never send them themselves) has its forwarded records ignored for a while.
  The builder sets the threshold.

Counts round to whole numbers in the "35 / 7" display. The builder decides how weights add up; the
guide is that 4 unconfirmed votes about equal 1 witnessed vote.

### One vote per account

The account-wide SavedVariables knows every character on the account that has run Scuttlebutt. The
client allows one vote per account per target: voting on a character replaces any vote another of
your characters cast on that target. Only honest clients enforce this. A person with several paid
WoW accounts can still vote several times; that is accepted.

### Circle

"Your circle" is your friends list plus your guild. The file says "3 of these are from your circle"
and lists circle votes first, without names.

## Troll guards

Layer 1, the voter's own client:

- At most 15 dislikes a day. Likes are unlimited. At the cap the dislike button grays out with a
  playful line ("Easy there. Even the town crier needs a break.").
- Sour streak: if more than 80% of the voter's last 30 votes are dislikes, dislikes pause for 24 hours.
- Eligibility: a vote is allowed only if the target is online now or was grouped with the voter in
  the last 24 hours. "Online now" means the client can see them: target, mouseover, nameplate, in
  the group, raid or guild roster, or they whispered or talked in chat in the last few minutes.
- Level 9 minimum.

A modified client can skip Layer 1, which is why Layer 2 exists.

Layer 2, every receiving client:

- Each client keeps stats per author from the votes it has received: likes, dislikes, timestamps.
- An author whose dislikes are 80% or more of a meaningful sample (suggested at least 20 votes) is a
  **Known Grump** to that client. Their dislikes count for less as the ratio climbs, down to nothing.
- "Known Grump" shows as a tag on that player's own tooltip and file. It says they dislike a lot,
  never whom.
- It wears off after 2 weeks with no new Grump behavior (their recent ratio drops back below the
  line).
- Option "Exclude Grump votes" (default off): when on, all of a Grump's votes, likes too, are
  dropped from every score this player sees.

Because each client judges from what reached it, one player may see someone as a Grump while
another doesn't yet. That's expected.

Every number in this section is a starting guess, kept in one tunables table in code.

## Network protocol

Scope and identity:

- Players are keyed as `Name-Realm`.
- The channel is a custom chat channel joined automatically and hidden from every chat frame. The
  builder picks the name (something unlikely to clash, e.g. `ScuttlebuttNet`). Note: custom
  channels may be split by faction, so Alliance votes about a Horde player may only circulate among
  Alliance players. That's accepted.
- Messages use `C_ChatInfo.SendAddonMessage` with type `CHANNEL` and a registered prefix.
- Nothing is sent or processed inside instances (Forever blocks addon messages there). Queued
  traffic waits until the player is back in the open world.

Records:

- A vote record: target, author, like/dislike/cleared, up to 3 tag IDs, timestamp (server time).
  A newer record from the same author about the same target replaces the old one.
- Compact binary-to-text encoding, several records per message, within the message size limit
  (about 255 bytes; confirmed in the first build).

Sync:

1. On login (and on joining the channel), a client sends a short **summary**: its record count and a
   small digest of its data (for example, newest timestamp per hash bucket). The builder chooses
   the digest.
2. Peers that see a summary wait a random 0–30 seconds. A peer replies only if fewer than K other
   peers have already replied (suggested K = 3). Replies hold records the newcomer seems to lack,
   newest first, capped per reply.
3. Afterward each client trickles out batches on a slow timer: its own new votes mixed with randomly
   sampled forwarded votes (the blur).
4. Sending goes through a single throttled queue (ChatThrottleLib or an equivalent built in). Never
   more than the game allows, and well under it by default.

Storage and fade:

- SavedVariables `ScuttlebuttDB` (account-wide).
- A vote lives as long as its author keeps playing. The author's client re-sends each of its own
  votes now and then (suggested about once every 2 weeks, spread out over time), which refreshes the
  vote's timestamp. A vote whose timestamp is older than 90 days is dropped. So "35 / 7" means the
  votes of players still active in the last 90 days, and a player who quits stops counting.
- A hard cap on stored records (suggested 50,000), dropping the oldest first. Private notes and the
  player's own votes are never dropped.

Versioning: every message starts with a protocol version byte. Clients ignore versions they don't
understand.

## User interface

- **Tooltip** (players only): "Scuttlebutt: 35 / 7" in green and red, the top 2–3 tags, "Known Grump"
  if it applies, and the private note if there is one.
- **Group finder**: "35/7" next to each applicant and listing leader. How depends on what Forever's
  group finder exposes (see Verify first).
- **Nameplates**: small "35/7" under player names, open world. Friendly player nameplates are off by
  default in WoW, so the settings explain how to turn them on. Inside instances player identities may
  be hidden from addons; if so, nameplate scores show only outside.
- **Player file** (opened from the right-click menu on a player, the tooltip hint, or
  `/scuttle <name>`):
  - Like and dislike buttons, the tag picker and the private note box.
  - The score, "based on what reached you", the tag counts, "N from your circle", and an
    "unconfirmed" count.
  - Grayed controls with a reason when voting isn't allowed (below level 9, not online or recently
    grouped, daily cap, sour pause).
- **Settings** (Blizzard settings panel plus `/scuttle` subcommands): toggles for tooltip, group
  finder, nameplates; Exclude Grump votes; an off switch for the network (private notes still work).
- **Minimap button**, matching how Starfall Trail does it.
- Visual style is left to the builder: readable, small and in keeping with the WoW UI.

## Constraints

- WoW Forever client 1.60.1, `## Interface: 16001`.
- No dependencies beyond the game. Embedded libraries are allowed if their licenses allow it.
- Tabs for indentation. American English in all text.
- Lua is checked with real Lua 5.1 (lupa `loadstring`), as in Starfall Trail.
- Forever's addon restrictions (Midnight rules): no combat log, hidden values in combat and in
  instances. Scuttlebutt must not error when a value is hidden; it skips the work instead.
- Released on CurseForge and a public GitHub repo, MIT license, same author identity as Starfall
  Trail. Creating those happens only when the user asks.

## Verify first (spike in the first build)

These are assumptions that the plan's first task checks in the live game before building on them:

1. `SendAddonMessage` with `CHANNEL` works outside instances on 1.60.1, and the exact message size
   and throttle.
2. A custom channel can be joined and hidden from every chat frame without the player seeing it.
3. Whether custom channels are faction-split on Forever.
4. Whether Forever has a group finder, and what an addon can read and draw on in it.
5. Whether player names are readable on nameplates, outside and inside instances.
6. The sources for "online now": mouseover, target, nameplate, group, guild roster, chat events.
7. The player right-click menu can be extended (Menu API or the older dropdown).

If one fails, the matching feature is reduced or dropped, and the user is told.

## Testing

- The gossip protocol, encoding, troll guards and credibility run as plain Lua and are tested
  offline in Lua 5.1 (lupa) with simulated clients: many clients, random joins and leaves, a flood
  of dislikes from one author, fake authors, faction split. The test shows how fast news spreads and
  that the queue stays under the throttle.
- The user has one game client. Live two-client tests need a second account and PC, for example
  a friend's PC or a second WoW license. Single-client checks (UI, eligibility,
  storage) happen in the user's own game.

## Left to the builder

The digest format, the encoding, the exact weights, the queue timings, the channel name, the file
layout and the visual design. Every tunable lives in one table in code.

## Author names on votes (decided)

Every vote carries its author's name for one-vote-per-person, Grump detection and forgery
protection. A player running a modified addon can see who voted what. The user accepted this on
11/09/2026: names stay hidden in the window, and if snooping addons appear, later updates will change
the encoding to break them ("we will cross that bridge when we come to it"). Nothing in the first
version is built for that.

## My calls (not explicitly agreed with the user)

- Private notes work below level 9; the level limit applies to the network side only.
- "Exclude Grump votes" defaults to off.
- "Recently grouped" means within 24 hours.
- Daily dislike cap 15; sour streak 80% of the last 30; Grump wear-off 2 weeks.
- Secondhand (unwitnessed) votes count at a quarter weight; Grump status uses witnessed votes only.
- One vote per account per target, enforced by honest clients.
- Votes stay alive while the author plays (re-sent about every 2 weeks) and expire 90 days after the
  last refresh; 50,000-record cap.
- Tags are numeric IDs so the list can change later.
- No encryption layer; compact encoding only.
