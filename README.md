# musicleague-offline-analyser
Slop 'enhanced' music league analyser. offline in that it doesn't use spotify creds/etc and does no web scraping... because it's not that serious

AI slop generated instructions below

## Folder layout

| Path | Purpose |
|---|---|
| `html\` | Saved results pages, one per round (you add these) |
| `rounds\` | One CSV per round, made by `Convert-MusicLeagueRound.ps1` |
| `names.csv` | Optional username to real name lookup |
| `Analyze-MusicLeague.ps1` | Prints the analysis; `-ExportDir` saves it as CSVs (e.g. `analysis\`) |

## 1. Capture a round's results (Firefox)

The results are loaded after the page opens, so "Save page" or "View source" won't include them. Copy the rendered page instead.

1. Open the round's results page on Music League and wait until all songs and votes are showing.
2. Open DevTools: **F12** (or **Ctrl+Shift+I**).
3. Go to the **Console** tab. If Firefox asks, type `allow pasting` first.
4. Run:
   ```js
   copy(document.documentElement.outerHTML)
   ```
5. Paste the clipboard into a new file in the `html\` folder (any name, e.g. `html\7.html`) and save. Keep one file per round.

## 2. Convert the rounds to CSVs

```powershell
.\Convert-MusicLeagueRound.ps1
```

- Converts **every** `.html` file in `html\` and writes `rounds\<round>.csv` (columns: `Song,Submitter,Votes,Voter`), so you can rerun it any time to rebuild everything.
- The round number comes from the "ROUND n" text inside each page, not the file name. If a numeric file name disagrees, it prints a warning and uses the page's number.
- An existing CSV for that round is overwritten. A file that fails to parse is reported and the rest still convert.
- Voters who gave a song 0 points have no row (Music League doesn't list them).
- Options: `-HtmlDir <folder>`, `-OutDir <folder>`, or `-Source <file>` to convert a single file (add `-Round 3` to override the detected round).

Repeat step 1 for each new round, then run the converter.

## 3. Run the analysis

```powershell
.\Analyze-MusicLeague.ps1
```

It reads every `.csv` in `rounds\`, however many there are, and prints:

- Voter pairs who scored the same songs most often
- Voting spectrum: songs scored per round and points per song, for every voter
- Winning songs ranked by points
- Submitter leaderboard (points per eligible voter, wins, best song)
- Taste similarity: most similar and most opposite voter pairs
- Most divisive and most consensus songs
- Rounds each person didn't vote in, and the songs each voter gave nothing to
- Who votes for the best and worst songs the most: per voter, how often they gave points to each round's winner / top 3 and its worst / bottom 3 songs (ties share a place; a voter can't score their own song)
- Points each voter gave to every other submitter

A voter is treated as able to score a song if they voted in that round and didn't submit it. Eligible voters with no row for a song count as 0 points.

Options:

| Option | Effect |
|---|---|
| `-ExportDir out` | Also save the full tables as CSVs in `out\` (including the voter x submitter matrix) |
| `-ListSize 20` | Rows shown in the top/bottom tables (default 10) |
| `-Top 25` | Limit the voter-pairs table (default 0 = show all) |
| `-RoundsDir <folder>` | Read round CSVs from somewhere other than `rounds\` |
| `-NamesFile <file>` | Username-to-real-name lookup (default `names.csv`) |

### Real names

Fill in the `RealName` column of `names.csv` (`Username,RealName`). The analysis then shows real names for both voters and submitters. Rows with a blank `Username` or `RealName`, and usernames not in the file, are ignored and shown as-is; if no row has both values the file is skipped entirely. Add a row for any new participant.

## CSV reference

### Input files

**`rounds\<n>.csv`** (made by the converter, one per round)

| Column | Meaning |
|---|---|
| `Song` | `Title - Artist` |
| `Submitter` | Username of the person who submitted the song |
| `Votes` | Points this voter gave the song (zero-point votes aren't listed) |
| `Voter` | Username of the voter |

**`names.csv`** (optional)

| Column | Meaning |
|---|---|
| `Username` | Name as it appears on Music League |
| `RealName` | Name to show instead. Blank = keep the username |

### Files written by `-ExportDir`

"Eligible" means the voter took part in that round and didn't submit the song. Names are real names when `names.csv` is filled in.

**`winning-songs.csv`**: each round's top song(s); `all-songs-ranked.csv` has the same columns for every song

| Column | Meaning |
|---|---|
| `Round` | Round number |
| `Song`, `Submitter` | Song and who submitted it |
| `Points` | Total points the song received |
| `Voters` | How many people gave it points |
| `TopVotes` | How many of those were 5-point votes |

**`submitter-leaderboard.csv`**: one row per submitter

| Column | Meaning |
|---|---|
| `Submitter` | Person |
| `Songs` | Songs they submitted |
| `Wins` | Rounds where their song had the top score (ties count) |
| `TotalPoints` / `AvgPoints` | Points their songs received in total / per song |
| `AvgPtsPerVoter` | Average points per eligible voter, per song. Fair across rounds with different numbers of voters, and the column the table is sorted by |
| `BestSong` | Their song with the highest points per eligible voter, as `R<round>: <song>` |

**`song-spread.csv`**: one row per song, most divisive first

| Column | Meaning |
|---|---|
| `Round`, `Song`, `Submitter` | As above |
| `Points` | Total points received |
| `Scored` | Eligible voters who gave it points |
| `Zeros` | Eligible voters who gave it nothing |
| `Max` | Highest single score it received |
| `StdDev` | Spread of scores across all eligible voters, zeros included. High = divisive, low = everyone agreed |
| `Eligible` | Number of eligible voters |
| `PtsPerVoter` | `Points / Eligible` |

**`voting-spectrum.csv`**: one row per voter

| Column | Meaning |
|---|---|
| `Voter` | Person |
| `RoundsVoted` | Rounds they gave at least one point in |
| `TotalSongs` | Songs they gave points to, all rounds |
| `AvgSongsPerRound` | `TotalSongs / RoundsVoted`. Low = concentrates points on few songs, high = spreads them |
| `FewestInARound` / `MostInARound` | Fewest / most songs they scored in any single round |
| `AvgPointsPerSong` | Average score they gave each song they scored |

**`voter-round-summary.csv`**: one row per voter per round

| Column | Meaning |
|---|---|
| `Round`, `Voter` | Round and person |
| `SongsVotedFor` | Songs they gave points to that round |
| `TotalPoints` | Points they spent that round |
| `PointsPerSong` | `TotalPoints / SongsVotedFor` |
| `MaxSinglePoint` | Their biggest single score that round |

**`voter-pairs.csv`**: every pair of voters who scored at least one song in common

| Column | Meaning |
|---|---|
| `VoterA`, `VoterB` | The pair |
| `SharedSongs` | Songs both gave points to |
| `AvgPointDiff` | Average gap between their scores on those songs (lower = more alike) |

**`taste-similarity.csv`**: pairs with at least 5 songs they could both score

| Column | Meaning |
|---|---|
| `VoterA`, `VoterB` | The pair |
| `SongsCompared` | Songs both could score (zeros included) |
| `Correlation` | Pearson correlation of their scores, -1 (opposite) to +1 (identical) |

**`voter-to-submitter-tally.csv`**: points given by each voter to each submitter (only pairs with points)

| Column | Meaning |
|---|---|
| `Voter`, `Submitter` | Who gave and who received |
| `TotalPoints` | Points given across all rounds |
| `Songs` | Number of that submitter's songs they scored |

**`voter-to-submitter-matrix.csv`**: the same totals as a grid. One row per voter (`Voter`), then one column per submitter holding the total points that voter gave them (0 = none).

**`voter-zero-scores.csv`**: one row per voter

| Column | Meaning |
|---|---|
| `Voter` | Person |
| `EligibleSongs` | Songs they could score |
| `Scored` | Songs they gave points to |
| `GaveNothing` | `EligibleSongs - Scored` |
| `PctIgnored` | `GaveNothing / EligibleSongs` as a percentage |

**`rounds-not-voted.csv`**: only people who missed a round

| Column | Meaning |
|---|---|
| `Person` | Person |
| `RoundsMissed` | How many rounds they didn't vote in |
| `Rounds` | Which rounds |

**`best-worst-voter-summary.csv`**: one row per voter. Songs are ranked by points within each round, and ties share a place.

| Column | Meaning |
|---|---|
| `Voter` | Person |
| `BestVoted` / `BestPossible` / `BestPoints` | Round winners they gave points to / could have scored / points given to them |
| `Top3Voted` / `Top3Possible` / `Top3Points` | The same for each round's top 3 songs |
| `WorstVoted` / `WorstPossible` / `WorstPoints` | The same for each round's lowest-scoring song |
| `Bottom3Voted` / `Bottom3Possible` / `Bottom3Points` | The same for each round's bottom 3 songs |

The on-screen best/worst tables add `Top3Pct` and `Bottom3Pct` (`Voted / Possible` as a percentage); these are not in the CSV.

## Notes

- If PowerShell blocks the scripts, run `Set-ExecutionPolicy -Scope Process Bypass` first.
- If the converter reports "No song cards found", that html file doesn't contain the loaded results. Redo step 1 after the page has fully loaded.
