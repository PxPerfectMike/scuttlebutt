# Scuttlebutt

**What the realm says about other players: likes, dislikes and tags, spread by word of mouth.**

Mouse over a stranger and see **35 / 7**: 35 players liked them, 7 didn't, plus "Great Tank, Friendly". Scuttlebutt players like or dislike each other, tag each other, and keep private notes. Votes travel from player to player over a hidden addon channel, the way gossip does. Nobody holds the whole picture, and every score shows what has reached you.

## Features

- **Likes and dislikes** shown as green and red counts, in tooltips, on nameplates and in the group finder.
- **Tags**: Great Tank, Great Healer, Great DPS, Knows the Content, Friendly, Generous, Helpful Guide, Fair Looter, and on the other side Ninja Looter, Left Mid-Dungeon, Toxic, AFK Leecher, Pulls Everything, Scammer. Up to 3 per player.
- **Private notes** that never leave your computer, shown in the tooltip.
- **Player file**: right-click any player and choose Scuttlebutt, or type `/scuttle <name>`.
- **Names of voters aren't shown.** You see the counts, how many came from your friends and guild, and how many are still unconfirmed.

## Keeping it honest

- You can rate players who are online near you, in your group or guild, or who you grouped with in the last day. Your alts can't vote for your main.
- One vote per account per player. Voting starts at level 9.
- 15 dislikes a day, and dislikes pause for a day after a long sour streak.
- Players who dislike nearly everyone get a public **Known Grump** tag and their dislikes stop counting. You can hide Grumps' votes entirely in the settings.
- A vote counts fully only when its author's own addon sent it. Fake votes in someone else's name get denied by that player's addon, and whoever spread them is ignored.

## Good to know

- Nothing is sent or received inside dungeons and raids (the game blocks addon messages there).
- Votes spread among players running Scuttlebutt, so the more people use it, the better the scores.
- To see scores on friendly players' nameplates, turn on friendly player nameplates in the game options.
- Votes from players who stop playing fade after 90 days.

## Commands

`/scuttle` or `/scuttlebutt` opens the settings.

- `/scuttle <name>`: open a player's file
- `/scuttle status`: what you've heard and whether you're connected
- `/scuttle tooltip`, `nameplates`, `groupfinder`, `grumps`, `network`: toggles

## Source

Open source under the MIT license: https://github.com/PxPerfectMike/scuttlebutt
