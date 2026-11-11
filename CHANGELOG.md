# Changelog

## 0.1.1

- Fix: players have surnames on Forever, and 0.1.0 signed your votes with your first name alone
  while the channel names you in full. Everyone's votes reached others as unconfirmed forwards
  (a quarter weight), and after about 30 of them the forger check blocked honest players for a
  day at a time. Now your key is your full name, votes from 0.1.0 clients are counted as their
  sender's own, saved short-name votes move to the full name, and the blocks are lifted.
- Quick vote: a green thumbs up and a red thumbs down, with the score, beside your target (on its
  nameplate, or next to the target frame) like or dislike in one click. Right-click them for the
  player file. Toggle in the settings or with `/scuttle quickvote`.
- The minimap button is smaller, shows a green thumbs up, sits on the right side of the minimap,
  and opens your target's file (settings when no player is targeted, or on right-click). Existing
  installs get the new position, and the button is shown again even if it was hidden before.

## 0.1.0

- First version: likes and dislikes ("35 / 7"), up to 3 tags per player, and private notes.
- Votes spread by word of mouth over a hidden addon channel; nobody holds the whole picture.
- Names of voters aren't shown. Votes passed along by others count for less until their author's
  own client confirms them.
- Troll guards: 15 dislikes a day, a pause after a sour streak, one vote per account, and the
  public "Known Grump" tag for players who dislike nearly everyone (option to hide their votes).
- Scores in tooltips, on nameplates and in the group finder; player file from the right-click menu
  or /scuttle <name>.
