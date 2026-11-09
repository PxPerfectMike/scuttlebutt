# Scuttlebutt

A World of Warcraft: Forever addon for what the realm says about other players. Like or dislike
players, tag them ("Great Healer", "Ninja Looter") and keep private notes. Votes spread from player
to player over a hidden addon channel, the way gossip does: nobody holds the whole picture, and
every score shows what has reached you.

## What you see

- **Tooltips:** "Scuttlebutt: 35 / 7" (likes in green, dislikes in red), the most common tags,
  "Known Grump" if it applies, and your private note.
- **Nameplates:** the score under player names (friendly player nameplates must be on to see allies).
- **Group finder:** the score next to applicants and group leaders, where the client's group finder
  allows it.
- **Player file:** right-click a player and choose Scuttlebutt, or type `/scuttle <name>`. Like,
  dislike, pick up to 3 tags and write a private note.

## How word of mouth works

- At level 9 the addon joins a hidden channel. When you log in it tells others a short summary of
  what it knows, and a few of them fill in what you're missing. After that, news trickles in.
- Every client passes on a few votes it has heard, so votes reach players who were offline.
- You can rate players who are online near you (targeted, moused over, in your group or guild,
  talking in chat) or who you grouped with in the last day. One vote per account per player.
- Votes from players who stop playing fade after 90 days.

## Privacy

Names of voters aren't shown anywhere in the addon. Each vote does carry its author inside the
addon's messages, because that's how the addon keeps one vote per person and catches fakes, so
someone running a modified addon could read them. Private notes never leave your computer.

## Keeping it honest

- 15 dislikes a day, and dislikes pause for a day after a long sour streak.
- A vote counts fully only when its author's own client sent it; votes passed along by others
  count for a quarter until confirmed. Forged votes are denied by their supposed author, and
  whoever passed them on is ignored for a while.
- Players who dislike nearly everyone get a public **Known Grump** tag, their dislikes stop
  counting, and you can hide all their votes in the settings.

## Limits

- Nothing is sent or received inside dungeons and raids (the game blocks addon messages there).
- Custom channels may be split by faction, so votes may only spread within a faction.
- Someone with several paid WoW accounts can vote once per account.

## Commands

`/scuttle` (or `/scuttlebutt`) opens the settings. `/scuttle <name>` opens a player's file.
`/scuttle status`, and the toggles `tooltip`, `nameplates`, `groupfinder`, `grumps`, `network`.

## Development

Tests run the addon's real Lua in Lua 5.1 through lupa, including a 100-client gossip simulation
and a smoke test of the in-game files against a stubbed WoW API:

```
PYLIBS=<folder with lupa> python tests/run.py
PYLIBS=<folder with lupa> tools/package.sh      # dist/Scuttlebutt-<version>.zip
```

`ScuttlebuttSpike/` is a developer addon that checks the game APIs Scuttlebutt depends on. It is
never packaged.

## License

MIT, see [LICENSE](LICENSE).
