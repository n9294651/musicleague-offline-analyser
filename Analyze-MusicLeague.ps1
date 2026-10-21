[CmdletBinding()]
param(
    [string]$RoundsDir = (Join-Path $PSScriptRoot 'rounds'),
    # Username -> real name lookup; blank RealName entries keep the username
    [string]$NamesFile = (Join-Path $PSScriptRoot 'names.csv'),
    # Limits the voter-pair list; 0 shows every pair
    [int]$Top = 0,
    # Rows shown in the ranked "top/bottom" tables (leaderboards, similarity, divisive songs)
    [int]$ListSize = 10,
    # When set, full (untruncated) results are written here as CSVs
    [string]$ExportDir
)

$ErrorActionPreference = 'Stop'

$files = Get-ChildItem -Path $RoundsDir -Filter '*.csv' | Where-Object { $_.Length -gt 0 }
if (-not $files) { throw "No round CSVs found in $RoundsDir" }

$names = @{}
if (Test-Path $NamesFile) {
    foreach ($n in @(Import-Csv $NamesFile)) {
        $user = "$($n.Username)".Trim(); $real = "$($n.RealName)".Trim()
        if ($user -and $real) { $names[$user] = $real }
    }
}
if ($names.Count) { "Using $($names.Count) real name(s) from $NamesFile" }
function Resolve-Name([string]$user) { if ($names.ContainsKey($user)) { $names[$user] } else { $user } }

$rows = foreach ($f in $files) {
    foreach ($r in (Import-Csv $f.FullName)) {
        [pscustomobject]@{
            Round     = $f.BaseName
            Song      = $r.Song
            Submitter = Resolve-Name $r.Submitter
            Voter     = Resolve-Name $r.Voter
            Votes     = [int]$r.Votes
        }
    }
}
$rounds = $rows | Select-Object -ExpandProperty Round -Unique | Sort-Object { [int]($_ -replace '\D', '0') }
"Loaded $($rows.Count) vote rows from $(@($rounds).Count) round(s): $($rounds -join ', ')"

function Show([string]$title, $data) {
    ''
    "=== $title ==="
    $data | Format-Table -AutoSize | Out-String | Write-Host
}
function Export([string]$name, $data) {
    if ($ExportDir) {
        New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
        $data | Export-Csv -Path (Join-Path $ExportDir "$name.csv") -NoTypeInformation -Encoding UTF8
    }
}

# 1. Voter pairs who scored the same songs most often
$songsByVoter = @{}
foreach ($g in ($rows | Group-Object Voter)) {
    $map = @{}
    foreach ($r in $g.Group) { $map["$($r.Round)|$($r.Song)"] = $r.Votes }
    $songsByVoter[$g.Name] = $map
}
$voters = @($songsByVoter.Keys | Sort-Object)
$pairs = for ($i = 0; $i -lt $voters.Count; $i++) {
    for ($j = $i + 1; $j -lt $voters.Count; $j++) {
        $a = $songsByVoter[$voters[$i]]; $b = $songsByVoter[$voters[$j]]
        $shared = @($a.Keys | Where-Object { $b.ContainsKey($_) })
        if ($shared.Count -eq 0) { continue }
        $diff = ($shared | ForEach-Object { [math]::Abs($a[$_] - $b[$_]) } | Measure-Object -Average).Average
        [pscustomobject]@{
            VoterA       = $voters[$i]
            VoterB       = $voters[$j]
            SharedSongs  = $shared.Count
            AvgPointDiff = [math]::Round($diff, 2)
        }
    }
}
$pairs = $pairs | Sort-Object @{e = 'SharedSongs'; Descending = $true }, AvgPointDiff
$pairsShown = if ($Top -gt 0) { $pairs | Select-Object -First $Top } else { $pairs }
Show 'Voter pairs who voted for the same songs most often' $pairsShown
Export 'voter-pairs' $pairs

# 2 & 3. Per round: fewest / most songs voted for
$perRound = foreach ($g in ($rows | Group-Object Round, Voter)) {
    $pts = ($g.Group | Measure-Object Votes -Sum).Sum
    [pscustomobject]@{
        Round          = $g.Group[0].Round
        Voter          = $g.Group[0].Voter
        SongsVotedFor  = $g.Count
        TotalPoints    = $pts
        PointsPerSong  = [math]::Round($pts / $g.Count, 2)
        MaxSinglePoint = ($g.Group | Measure-Object Votes -Maximum).Maximum
    }
}
Export 'voter-round-summary' $perRound

# Songs voted for per round, averaged across all rounds each voter took part in
$overall = foreach ($g in ($perRound | Group-Object Voter)) {
    $songs = ($g.Group | Measure-Object SongsVotedFor -Sum).Sum
    $pts = ($g.Group | Measure-Object TotalPoints -Sum).Sum
    [pscustomobject]@{
        Voter             = $g.Name
        RoundsVoted       = $g.Count
        TotalSongs        = $songs
        AvgSongsPerRound  = [math]::Round($songs / $g.Count, 2)
        FewestInARound    = ($g.Group | Measure-Object SongsVotedFor -Minimum).Minimum
        MostInARound      = ($g.Group | Measure-Object SongsVotedFor -Maximum).Maximum
        AvgPointsPerSong  = [math]::Round($pts / $songs, 2)
    }
}
$spectrum = $overall | Sort-Object AvgSongsPerRound, @{e = 'AvgPointsPerSong'; Descending = $true }
Show 'Voting spectrum (fewest songs per round at top, most at bottom)' $spectrum
Export 'voting-spectrum' $spectrum

# Song totals per round; winners are the top song(s) of each round
$songs = foreach ($g in ($rows | Group-Object Round, Song)) {
    [pscustomobject]@{
        Round     = $g.Group[0].Round
        Song      = $g.Group[0].Song
        Submitter = $g.Group[0].Submitter
        Points    = ($g.Group | Measure-Object Votes -Sum).Sum
        Voters    = @($g.Group | Select-Object -ExpandProperty Voter -Unique).Count
        TopVotes  = @($g.Group | Where-Object Votes -ge 5).Count
    }
}
$songsByVoters = foreach ($r in $rounds) {
    $rank = 0
    foreach ($s in ($songs | Where-Object Round -eq $r | Sort-Object @{e = 'Voters'; Descending = $true }, @{e = 'Points'; Descending = $true })) {
        $rank++
        [pscustomobject]@{
            Round     = $s.Round
            Rank      = $rank
            Song      = $s.Song
            Submitter = $s.Submitter
            Voters    = $s.Voters
            Points    = $s.Points
        }
    }
}
foreach ($r in $rounds) {
    Show "Round $r songs ranked by number of voters (each voter counts once per song)" ($songsByVoters | Where-Object Round -eq $r)
}
Export 'all-songs-ranked-by-voters' $songsByVoters

$winners = foreach ($r in $rounds) {
    $set = @($songs | Where-Object Round -eq $r)
    $max = ($set | Measure-Object Points -Maximum).Maximum
    $set | Where-Object Points -eq $max
}
$winners = $winners | Sort-Object @{e = 'Points'; Descending = $true }, @{e = 'Voters'; Descending = $true }, Round
Show 'Winning songs ranked by points (ties within a round are all listed)' $winners
Export 'winning-songs' $winners
Export 'all-songs-ranked' ($songs | Sort-Object @{e = 'Points'; Descending = $true }, Round)

# Eligibility: a voter can score a song if they voted in that round and didn't submit it.
# Zero-point votes aren't in the CSVs, so a missing row for an eligible voter means 0.
$roundVoters = @{}
foreach ($r in $rounds) { $roundVoters[$r] = @($rows | Where-Object Round -eq $r | Select-Object -ExpandProperty Voter -Unique) }
$score = @{}
foreach ($r in $rows) { $score["$($r.Round)|$($r.Song)|$($r.Voter)"] = $r.Votes }
$songKeys = @($songs | ForEach-Object { [pscustomobject]@{ Round = $_.Round; Song = $_.Song; Submitter = $_.Submitter } })

# Submitter leaderboard
$songStats = foreach ($s in $songKeys) {
    $elig = @($roundVoters[$s.Round] | Where-Object { $_ -ne $s.Submitter })
    $vals = @($elig | ForEach-Object { [double]$score["$($s.Round)|$($s.Song)|$_"] })
    $total = ($vals | Measure-Object -Sum).Sum
    $mean = $total / [math]::Max($elig.Count, 1)
    $var = (($vals | ForEach-Object { ($_ - $mean) * ($_ - $mean) }) | Measure-Object -Sum).Sum / [math]::Max($elig.Count, 1)
    [pscustomobject]@{
        Round     = $s.Round
        Song      = $s.Song
        Submitter = $s.Submitter
        Points    = $total
        Eligible  = $elig.Count
        Scored    = @($vals | Where-Object { $_ -gt 0 }).Count
        Zeros     = @($vals | Where-Object { $_ -eq 0 }).Count
        Max       = ($vals | Measure-Object -Maximum).Maximum
        StdDev    = [math]::Round([math]::Sqrt($var), 2)
        PtsPerVoter = [math]::Round($mean, 2)
    }
}
$winnerKeys = @{}
foreach ($w in $winners) { $winnerKeys["$($w.Round)|$($w.Song)"] = $true }
$leaderboard = foreach ($g in ($songStats | Group-Object Submitter)) {
    $best = $g.Group | Sort-Object @{e = 'PtsPerVoter'; Descending = $true } | Select-Object -First 1
    [pscustomobject]@{
        Submitter     = $g.Name
        Songs         = $g.Count
        Wins          = @($g.Group | Where-Object { $winnerKeys["$($_.Round)|$($_.Song)"] }).Count
        TotalPoints   = ($g.Group | Measure-Object Points -Sum).Sum
        AvgPoints     = [math]::Round(($g.Group | Measure-Object Points -Average).Average, 2)
        AvgPtsPerVoter = [math]::Round(($g.Group | Measure-Object PtsPerVoter -Average).Average, 2)
        BestSong      = "R$($best.Round): $($best.Song)"
    }
}
$leaderboard = $leaderboard | Sort-Object @{e = 'AvgPtsPerVoter'; Descending = $true }, @{e = 'Wins'; Descending = $true }
Show 'Submitter leaderboard (ranked by average points per eligible voter, which evens out different round sizes)' $leaderboard
Export 'submitter-leaderboard' $leaderboard

# Alternate leaderboard: each eligible voter contributes at most one vote per song.
$voterLeaderboard = foreach ($g in ($songStats | Group-Object Submitter)) {
    $best = $g.Group | Sort-Object @{e = { $_.Scored / [math]::Max($_.Eligible, 1) }; Descending = $true } | Select-Object -First 1
    [pscustomobject]@{
        Submitter       = $g.Name
        Songs           = $g.Count
        TotalVoterVotes = ($g.Group | Measure-Object Scored -Sum).Sum
        AvgVotersPerSong = [math]::Round(($g.Group | Measure-Object Scored -Average).Average, 2)
        AvgVoterPct     = [math]::Round(100 * (($g.Group | ForEach-Object { $_.Scored / [math]::Max($_.Eligible, 1) } | Measure-Object -Average).Average), 2)
        BestSong        = "R$($best.Round): $($best.Song)"
    }
}
$voterLeaderboard = $voterLeaderboard | Sort-Object @{e = 'AvgVoterPct'; Descending = $true }, @{e = 'TotalVoterVotes'; Descending = $true }
Show 'Submitter leaderboard by voter count (ranked by average share of eligible voters supporting each song)' $voterLeaderboard
Export 'submitter-voter-leaderboard' $voterLeaderboard

# Taste similarity: Pearson correlation of scores (zeros included) on songs both voters could score
$sim = for ($i = 0; $i -lt $voters.Count; $i++) {
    for ($j = $i + 1; $j -lt $voters.Count; $j++) {
        $va = $voters[$i]; $vb = $voters[$j]
        $x = [System.Collections.Generic.List[double]]::new(); $y = [System.Collections.Generic.List[double]]::new()
        foreach ($s in $songKeys) {
            if ($s.Submitter -eq $va -or $s.Submitter -eq $vb) { continue }
            if ($roundVoters[$s.Round] -notcontains $va -or $roundVoters[$s.Round] -notcontains $vb) { continue }
            $x.Add([double]$score["$($s.Round)|$($s.Song)|$va"]); $y.Add([double]$score["$($s.Round)|$($s.Song)|$vb"])
        }
        if ($x.Count -lt 5) { continue }
        $mx = ($x | Measure-Object -Average).Average; $my = ($y | Measure-Object -Average).Average
        $sxy = 0.0; $sxx = 0.0; $syy = 0.0
        for ($k = 0; $k -lt $x.Count; $k++) {
            $sxy += ($x[$k] - $mx) * ($y[$k] - $my); $sxx += [math]::Pow($x[$k] - $mx, 2); $syy += [math]::Pow($y[$k] - $my, 2)
        }
        if ($sxx -eq 0 -or $syy -eq 0) { continue }
        [pscustomobject]@{
            VoterA        = $va
            VoterB        = $vb
            SongsCompared = $x.Count
            Correlation   = [math]::Round($sxy / [math]::Sqrt($sxx * $syy), 3)
        }
    }
}
$simSorted = $sim | Sort-Object @{e = 'Correlation'; Descending = $true }
Show "Most similar taste (top $ListSize)" ($simSorted | Select-Object -First $ListSize)
Show "Most opposite taste (bottom $ListSize)" ($simSorted | Select-Object -Last $ListSize | Sort-Object Correlation)
Export 'taste-similarity' $simSorted

# Divisive vs. consensus songs, by spread of scores across every eligible voter
$divisive = $songStats | Sort-Object @{e = 'StdDev'; Descending = $true }, Round
$consensus = $songStats | Where-Object { $_.Points -gt 0 } | Sort-Object StdDev, @{e = 'Points'; Descending = $true }
$cols = 'Round', 'Song', 'Submitter', 'Points', 'Scored', 'Zeros', 'Max', 'StdDev'
Show "Most divisive songs (top $ListSize by score spread)" ($divisive | Select-Object -First $ListSize | Select-Object $cols)
Show "Most consensus songs (lowest $ListSize spread)" ($consensus | Select-Object -First $ListSize | Select-Object $cols)
Export 'song-spread' ($divisive | Select-Object ($cols + @('Eligible', 'PtsPerVoter')))

# Who backs the best and worst songs: top 1 / top 3 and bottom 1 / bottom 3 of each round.
# Ranks are tie-inclusive (every song tied for a place gets that place), and a song's own submitter can't vote for it.
$placed = foreach ($r in $rounds) {
    $set = @($songStats | Where-Object Round -eq $r)
    foreach ($s in $set) {
        $p = $s.Points
        [pscustomobject]@{
            Round      = $r
            Song       = $s.Song
            Submitter  = $s.Submitter
            Points     = $p
            TopRank    = 1 + @($set | Where-Object { $_.Points -gt $p }).Count
            BottomRank = 1 + @($set | Where-Object { $_.Points -lt $p }).Count
        }
    }
}

$bestWorst = foreach ($v in $voters) {
    $mine = @($placed | Where-Object { $_.Submitter -ne $v -and $roundVoters[$_.Round] -contains $v })
    $gave = { param($set) @($set | Where-Object { $score["$($_.Round)|$($_.Song)|$v"] -gt 0 }) }
    $pts = { param($set) [int](@($set | ForEach-Object { [int]$score["$($_.Round)|$($_.Song)|$v"] }) | Measure-Object -Sum).Sum }
    $w1 = @($mine | Where-Object TopRank -le 1);    $w3 = @($mine | Where-Object TopRank -le 3)
    $b1 = @($mine | Where-Object BottomRank -le 1); $b3 = @($mine | Where-Object BottomRank -le 3)
    [pscustomobject]@{
        Voter          = $v
        BestVoted      = (& $gave $w1).Count
        BestPossible   = $w1.Count
        BestPoints     = & $pts $w1
        Top3Voted      = (& $gave $w3).Count
        Top3Possible   = $w3.Count
        Top3Points     = & $pts $w3
        WorstVoted     = (& $gave $b1).Count
        WorstPossible  = $b1.Count
        WorstPoints    = & $pts $b1
        Bottom3Voted   = (& $gave $b3).Count
        Bottom3Possible = $b3.Count
        Bottom3Points  = & $pts $b3
    }
}
$bestWorst = $bestWorst | Sort-Object @{e = 'Top3Voted'; Descending = $true }, @{e = 'BestVoted'; Descending = $true }, Voter
Show 'Who votes for the best songs the most (Voted = songs they gave points to, Possible = songs they could score; Pct = Voted/Possible)' ($bestWorst | Select-Object Voter, BestVoted, BestPossible, BestPoints, Top3Voted, Top3Possible, Top3Points, @{n = 'Top3Pct'; e = { [math]::Round(100 * $_.Top3Voted / [math]::Max($_.Top3Possible, 1), 1) } })
Show 'Who votes for the worst songs the most' ($bestWorst | Sort-Object @{e = 'Bottom3Voted'; Descending = $true }, @{e = 'WorstVoted'; Descending = $true }, Voter | Select-Object Voter, WorstVoted, WorstPossible, WorstPoints, Bottom3Voted, Bottom3Possible, Bottom3Points, @{n = 'Bottom3Pct'; e = { [math]::Round(100 * $_.Bottom3Voted / [math]::Max($_.Bottom3Possible, 1), 1) } })
Export 'best-worst-voter-summary' $bestWorst

# Non-voters: rounds each person sat out, and how often they gave a song nothing
$participants = @(($rows | Select-Object -ExpandProperty Voter) + ($rows | Select-Object -ExpandProperty Submitter) | Sort-Object -Unique)
$missed = foreach ($p in $participants) {
    $miss = @($rounds | Where-Object { $roundVoters[$_] -notcontains $p })
    if ($miss.Count) { [pscustomobject]@{ Person = $p; RoundsMissed = $miss.Count; Rounds = $miss -join ', ' } }
}
if ($missed) { Show 'Rounds a participant did not vote in' $missed } else { '' ; 'Every participant voted in every round.' }
Export 'rounds-not-voted' $missed

$zeroStats = foreach ($v in $voters) {
    $elig = @($songStats | Where-Object { $_.Submitter -ne $v -and $roundVoters[$_.Round] -contains $v })
    $given = @($elig | Where-Object { $score["$($_.Round)|$($_.Song)|$v"] -gt 0 }).Count
    [pscustomobject]@{
        Voter         = $v
        EligibleSongs = $elig.Count
        Scored        = $given
        GaveNothing   = $elig.Count - $given
        PctIgnored    = [math]::Round(100 * ($elig.Count - $given) / [math]::Max($elig.Count, 1), 1)
    }
}
$zeroStats = $zeroStats | Sort-Object @{e = 'PctIgnored'; Descending = $true }
Show 'Songs each voter gave no points to (of songs they could score)' $zeroStats
Export 'voter-zero-scores' $zeroStats

# 4. Points each voter gave to each submitter
$tally = foreach ($g in ($rows | Group-Object Voter, Submitter)) {
    [pscustomobject]@{
        Voter       = $g.Group[0].Voter
        Submitter   = $g.Group[0].Submitter
        TotalPoints = ($g.Group | Measure-Object Votes -Sum).Sum
        Songs       = $g.Count
    }
}
$tally = $tally | Sort-Object @{e = 'TotalPoints'; Descending = $true }, Voter, Submitter
Export 'voter-to-submitter-tally' $tally

# Full matrix: one row per voter, one column per submitter
$submitters = @($rows | Select-Object -ExpandProperty Submitter -Unique | Sort-Object)
$lookup = @{}
$songLookup = @{}
foreach ($t in $tally) {
    $lookup["$($t.Voter)|$($t.Submitter)"] = $t.TotalPoints
    $songLookup["$($t.Voter)|$($t.Submitter)"] = $t.Songs
}

# Every voter, listing every submitter (including those they gave nothing to)
foreach ($v in $voters) {
    $list = foreach ($s in $submitters) {
        if ($s -eq $v) { continue }
        [pscustomobject]@{
            Submitter   = $s
            TotalPoints = [int]$lookup["$v|$s"]
            SongsScored = [int]$songLookup["$v|$s"]
        }
    }
    Show "Points given by $v" ($list | Sort-Object @{e = 'TotalPoints'; Descending = $true }, Submitter)
}
$matrix = foreach ($v in $voters) {
    $o = [ordered]@{ Voter = $v }
    foreach ($s in $submitters) { $o[$s] = [int]$lookup["$v|$s"] }
    [pscustomobject]$o
}
Export 'voter-to-submitter-matrix' $matrix

if ($ExportDir) { "`nFull results exported to $ExportDir" }
else { "`nTip: use -ExportDir <path> to save full tables (including the voter x submitter matrix) as CSVs." }
