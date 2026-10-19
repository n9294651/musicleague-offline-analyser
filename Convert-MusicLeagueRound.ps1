[CmdletBinding()]
param(
    # Folder of saved results pages; every .html file in it is converted
    [string]$HtmlDir = (Join-Path $PSScriptRoot 'html'),
    # Convert just this one file instead of the whole folder
    [string]$Source,
    # Only valid with -Source; overrides the round number detected from the page
    [int]$Round,
    [string]$OutDir = (Join-Path $PSScriptRoot 'rounds')
)

$ErrorActionPreference = 'Stop'

function Decode([string]$s) { [System.Net.WebUtility]::HtmlDecode($s).Trim() }
function Csv([string]$s) {
    if ($s -match '[,"\r\n]') { '"' + $s.Replace('"', '""') + '"' } else { $s }
}

function Convert-Page([string]$Path, [int]$RoundOverride) {
    $file = Get-Item -LiteralPath $Path
    $html = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)

    $detected = if ($html -match 'ROUND\s+(\d+)') { [int]$Matches[1] } else { 0 }
    $round = if ($RoundOverride) { $RoundOverride } else { $detected }
    if (-not $round) { throw 'Could not detect round number from the page; use -Source with -Round.' }
    if ($file.BaseName -match '^\d+$' -and [int]$file.BaseName -ne $round) {
        Write-Warning "$($file.Name) contains ROUND $round (file name says $($file.BaseName)); using $round."
    }

    $cards = [regex]::Split($html, '(?=<div class="card mb-4" id="spotify:track:)') |
        Where-Object { $_ -like '<div class="card mb-4" id="spotify:track:*' }
    if (-not $cards) { throw 'No song cards found. Copy the rendered DOM (document.documentElement.outerHTML) after results load.' }

    $lines = @('Song,Submitter,Votes,Voter')
    foreach ($card in $cards) {
        $title = [regex]::Match($card, '(?s)<h6 class="card-title[^"]*">\s*<a [^>]*>(.*?)</a>').Groups[1].Value
        $artist = [regex]::Match($card, '<p class="card-text m-0 text-truncate">(.*?)</p>').Groups[1].Value
        $submitter = [regex]::Match($card, '<h6 class="m-0 text-truncate text-body fw-semibold">(.*?)</h6>').Groups[1].Value
        if (-not $title -or -not $submitter) { throw 'Failed to parse a song card.' }
        $song = '{0} - {1}' -f (Decode $title), (Decode $artist)

        $footerStart = $card.IndexOf('card-footer')
        if ($footerStart -lt 0) { continue }
        $footer = $card.Substring($footerStart)
        foreach ($row in ($footer -split '(?=<div class="row align-items-start gx-3 my-3">)')) {
            $voter = [regex]::Match($row, '<b class="d-block text-truncate text-body"[^>]*>(.*?)</b>')
            $vote = [regex]::Match($row, '<h6 class="m-0">\s*(-?\d+)\s*</h6>')
            # Voters who gave no points have no score element, so they are skipped
            if ($voter.Success -and $vote.Success) {
                $lines += '{0},{1},{2},{3}' -f (Csv $song), (Csv (Decode $submitter)), $vote.Groups[1].Value, (Csv (Decode $voter.Groups[1].Value))
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $out = Join-Path $OutDir "$round.csv"
    [System.IO.File]::WriteAllText($out, ($lines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
    "$($file.Name): round $round, $($cards.Count) songs, $($lines.Count - 1) vote rows -> $out"
}

if ($Round -and -not $Source) { throw '-Round only works together with -Source.' }

if ($Source) {
    Convert-Page (Resolve-Path $Source).Path $Round
    return
}

$pages = @(Get-ChildItem -Path $HtmlDir -Filter '*.html' | Sort-Object { [int]($_.BaseName -replace '\D', '0') }, Name)
if (-not $pages) { throw "No .html files found in $HtmlDir" }

$failed = 0
foreach ($p in $pages) {
    try { Convert-Page $p.FullName 0 }
    catch { $failed++; Write-Warning "$($p.Name): $($_.Exception.Message)" }
}
"Done: $($pages.Count - $failed) of $($pages.Count) file(s) converted."
if ($failed) { exit 1 }

