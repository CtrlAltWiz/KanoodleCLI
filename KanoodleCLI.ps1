#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu','Demo','Solve','Generate','Count')]
    [string]$Mode = 'Menu',
    [string[]]$Board,
    [int]$Seed = 0,
    [long]$Limit = 0,
    [int]$CluePieces = 4,
    [switch]$NoColor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Rows = 5
$script:Cols = 11
$script:PlacementCatalog = $null
$script:Example = @(
    'EEGGGJJJJII'
    'AEEEGCDDDDI'
    'AAALGCHHDII'
    'BBLLLCFHHKK'
    'BBBLCCFFHKK'
)

$script:Colors = [ordered]@{
    A = @(255,140,0); B = @(235,45,45); C = @(45,105,255); D = @(255,182,193)
    E = @(30,180,75); F = @(245,245,245); G = @(105,205,255); H = @(255,75,165)
    I = @(255,220,35); J = @(155,65,210); K = @(135,220,105); L = @(150,150,150)
}
$script:ConsoleColors = [ordered]@{
    A = 'DarkYellow'; B = 'Red'; C = 'Blue'; D = 'Magenta'
    E = 'Green'; F = 'White'; G = 'Cyan'; H = 'DarkMagenta'
    I = 'Yellow'; J = 'DarkCyan'; K = 'DarkGreen'; L = 'Gray'
}

function Get-PieceDefinitions {
    $pieces = [ordered]@{}
    foreach ($letter in $script:Colors.Keys) {
        $cells = [System.Collections.Generic.List[object]]::new()
        for ($r = 0; $r -lt $script:Rows; $r++) {
            for ($c = 0; $c -lt $script:Cols; $c++) {
                if ($script:Example[$r][$c] -eq $letter) { $cells.Add([pscustomobject]@{ R = $r; C = $c }) }
            }
        }
        $minR = ($cells.R | Measure-Object -Minimum).Minimum
        $minC = ($cells.C | Measure-Object -Minimum).Minimum
        $pieces[$letter] = @($cells | ForEach-Object { [pscustomobject]@{ R = $_.R - $minR; C = $_.C - $minC } })
    }
    return $pieces
}

function Get-Orientations([object[]]$Shape) {
    $unique = [ordered]@{}
    foreach ($flip in 0,1) {
        foreach ($rotation in 0..3) {
            $points = foreach ($point in $Shape) {
                $r = [int]$point.R; $c = [int]$point.C
                if ($flip) { $c = -$c }
                if ($rotation -gt 0) {
                    foreach ($step in 1..$rotation) { $oldR = $r; $r = $c; $c = -$oldR }
                }
                [pscustomobject]@{ R = $r; C = $c }
            }
            $minR = ($points.R | Measure-Object -Minimum).Minimum
            $minC = ($points.C | Measure-Object -Minimum).Minimum
            $normalized = @($points | ForEach-Object { [pscustomobject]@{ R = $_.R - $minR; C = $_.C - $minC } } | Sort-Object R,C)
            $key = ($normalized | ForEach-Object { "$($_.R),$($_.C)" }) -join ';'
            $unique[$key] = [pscustomobject]@{ Cells = $normalized }
        }
    }
    return @($unique.Values)
}

function New-PlacementCatalog {
    if ($null -ne $script:PlacementCatalog) { return $script:PlacementCatalog }
    $byPiece = @{}; $byCell = @{}
    foreach ($i in 0..($script:Rows * $script:Cols - 1)) { $byCell[$i] = [System.Collections.Generic.List[object]]::new() }
    foreach ($entry in (Get-PieceDefinitions).GetEnumerator()) {
        $letter = [string]$entry.Key
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($orientation in Get-Orientations $entry.Value) {
            $shape = $orientation.Cells
            $height = (($shape.R | Measure-Object -Maximum).Maximum + 1)
            $width  = (($shape.C | Measure-Object -Maximum).Maximum + 1)
            for ($top = 0; $top -le $script:Rows - $height; $top++) {
                for ($left = 0; $left -le $script:Cols - $width; $left++) {
                    $cells = [int[]]@($shape | ForEach-Object { ($top + $_.R) * $script:Cols + $left + $_.C } | Sort-Object)
                    [uint64]$mask = 0
                    foreach ($cell in $cells) { $mask = $mask -bor ([uint64]1 -shl $cell) }
                    $placement = [pscustomobject]@{ Piece = $letter; Cells = $cells; Mask = $mask }
                    $list.Add($placement)
                    foreach ($cell in $cells) { $byCell[$cell].Add($placement) }
                }
            }
        }
        $byPiece[$letter] = $list
    }
    $script:PlacementCatalog = [pscustomobject]@{ ByPiece = $byPiece; ByCell = $byCell }
    return $script:PlacementCatalog
}

function ConvertTo-Constraint([string[]]$Lines) {
    if (-not $Lines -or $Lines.Count -ne $script:Rows) { throw 'A board must contain exactly 5 rows.' }
    $constraint = New-Object char[] ($script:Rows * $script:Cols)
    for ($r = 0; $r -lt $script:Rows; $r++) {
        $line = $Lines[$r].ToUpperInvariant() -replace '[^A-L.*]',''
        if ($line.Length -ne $script:Cols) { throw "Row $($r + 1) must contain exactly 11 cells (A-L, . or *)." }
        for ($c = 0; $c -lt $script:Cols; $c++) { $constraint[$r * $script:Cols + $c] = $line[$c] }
    }
    return $constraint
}

function Find-KanoodleSolutions {
    param(
        [char[]]$Constraint,
        [long]$MaxSolutions = 1,
        [switch]$Randomize,
        [int]$RandomSeed = 0,
        [switch]$Collect,
        [switch]$ShowSpinner
    )
    $spinner = @('|', '/', '-', '\')
    $state = @{
        Count = [long]0
        Nodes = [long]0
        Occupied = [uint64]0
        SpinnerIndex = 0
        LastSpinnerUpdate = [Diagnostics.Stopwatch]::StartNew()
    }
    if ($ShowSpinner) { Write-Host "`rThinking $($spinner[0]) " -NoNewline -ForegroundColor Cyan }

    $catalog = New-PlacementCatalog
    $eligibleByCell = @{}
    $eligibleByPiece = @{}
    foreach ($i in 0..($script:Rows * $script:Cols - 1)) { $eligibleByCell[$i] = [System.Collections.Generic.List[object]]::new() }
    foreach ($piece in $script:Colors.Keys) {
        $eligibleByPiece[$piece] = [System.Collections.Generic.List[object]]::new()
        $required = [int[]]@(for ($i = 0; $i -lt $Constraint.Length; $i++) { if ($Constraint[$i] -eq $piece) { $i } })
        foreach ($placement in $catalog.ByPiece[$piece]) {
            $valid = $true
            foreach ($cell in $placement.Cells) {
                $clue = $Constraint[$cell]
                if ($clue -ge 'A' -and $clue -le 'L' -and $clue -ne $piece) { $valid = $false; break }
            }
            if ($valid) {
                foreach ($cell in $required) { if ($cell -notin $placement.Cells) { $valid = $false; break } }
            }
            if ($valid) {
                $eligibleByPiece[$piece].Add($placement)
                foreach ($cell in $placement.Cells) { $eligibleByCell[$cell].Add($placement) }
            }
        }
    }
    $used = @{}; foreach ($key in $script:Colors.Keys) { $used[$key] = $false }
    $chosen = [System.Collections.Generic.List[object]]::new()
    $solutions = [System.Collections.Generic.List[object]]::new()
    $rng = if ($RandomSeed) { [Random]::new($RandomSeed) } else { [Random]::new() }
    function Compatible($placement) {
        if ($used[$placement.Piece]) { return $false }
        return (($state.Occupied -band $placement.Mask) -eq 0)
    }

    function Search {
        $state.Nodes++
        if ($ShowSpinner -and $state.LastSpinnerUpdate.ElapsedMilliseconds -ge 100) {
            $state.SpinnerIndex = ($state.SpinnerIndex + 1) % $spinner.Count
            Write-Host "`rThinking $($spinner[$state.SpinnerIndex]) " -NoNewline -ForegroundColor Cyan
            $state.LastSpinnerUpdate.Restart()
        }
        if ($MaxSolutions -gt 0 -and $state.Count -ge $MaxSolutions) { return }
        if ($chosen.Count -eq $script:Colors.Count) {
            $state.Count++
            if ($Collect) { $solutions.Add(@($chosen)) }
            return
        }
        $candidates = $null; $bestCount = [int]::MaxValue
        for ($cell = 0; $cell -lt ($script:Rows * $script:Cols); $cell++) {
            $cellMask = ([uint64]1 -shl $cell)
            if (($state.Occupied -band $cellMask) -ne 0) { continue }
            $validList = [System.Collections.Generic.List[object]]::new()
            foreach ($candidate in $eligibleByCell[$cell]) {
                if ((-not $used[$candidate.Piece]) -and (($state.Occupied -band $candidate.Mask) -eq 0)) {
                    $validList.Add($candidate)
                }
            }
            $valid = $validList.ToArray()
            if ($valid.Count -eq 0) { return }
            if ($valid.Count -lt $bestCount) { $candidates = $valid; $bestCount = $valid.Count }
        }
        # Piece columns are part of exact cover too. Selecting the tightest
        # unused piece often prunes an impossible branch much earlier.
        foreach ($piece in $script:Colors.Keys) {
            if ($used[$piece]) { continue }
            $validList = [System.Collections.Generic.List[object]]::new()
            foreach ($candidate in $eligibleByPiece[$piece]) {
                if (($state.Occupied -band $candidate.Mask) -eq 0) { $validList.Add($candidate) }
            }
            $valid = $validList.ToArray()
            if ($valid.Count -eq 0) { return }
            if ($valid.Count -lt $bestCount) { $candidates = $valid; $bestCount = $valid.Count }
        }
        if ($Randomize) { $candidates = @($candidates | Sort-Object { $rng.Next() }) }
        foreach ($placement in $candidates) {
            $used[$placement.Piece] = $true
            $state.Occupied = $state.Occupied -bor $placement.Mask
            $chosen.Add($placement)
            Search
            $chosen.RemoveAt($chosen.Count - 1)
            $state.Occupied = $state.Occupied -bxor $placement.Mask
            $used[$placement.Piece] = $false
            if ($MaxSolutions -gt 0 -and $state.Count -ge $MaxSolutions) { break }
        }
    }
    Search
    if ($ShowSpinner) {
        $state.LastSpinnerUpdate.Stop()
        Write-Host "`rDone!              " -ForegroundColor Green
    }
    [pscustomobject]@{ Count = $state.Count; Solutions = $solutions }
}

function ConvertFrom-Solution($Solution) {
    $grid = [char[]]::new($script:Rows * $script:Cols)
    for ($i = 0; $i -lt $grid.Length; $i++) { $grid[$i] = '.' }
    foreach ($placement in $Solution) { foreach ($cell in $placement.Cells) { $grid[$cell] = $placement.Piece } }
    @(for ($r = 0; $r -lt $script:Rows; $r++) { -join $grid[($r*$script:Cols)..($r*$script:Cols+$script:Cols-1)] })
}

function Show-Board([string[]]$Lines, [switch]$Labels) {
    foreach ($line in $Lines) {
        for ($c = 0; $c -lt $line.Length; $c++) {
            $piece = [string]$line[$c]
            if ($piece -ge 'A' -and $piece -le 'L') {
                $rgb = $script:Colors[$piece]
                $text = if ($Labels) { $piece } else { [char]0x2022 }
                if ($NoColor) {
                    Write-Host "$text " -NoNewline
                } else {
                    # ConsoleColor works in both Windows PowerShell 5.1 and
                    # PowerShell 7; ANSI true-color escape sequences do not.
                    Write-Host "$text " -NoNewline -ForegroundColor $script:ConsoleColors[$piece]
                }
            } else { Write-Host "$([char]0x00B7) " -NoNewline -ForegroundColor DarkGray }
        }
        Write-Host
    }
}

function Read-Board {
    Write-Host 'Enter 5 rows of 11 cells. Use A-L for fixed piece dots and . for empty holes.'
    $lines = foreach ($r in 1..5) { Read-Host "Row $r" }
    return @($lines)
}

function Invoke-Solve([string[]]$Lines) {
    $constraint = ConvertTo-Constraint $Lines
    $result = Find-KanoodleSolutions -Constraint $constraint -MaxSolutions 1 -Collect -ShowSpinner
    if (-not $result.Count) { Write-Host 'No solution exists for those clues.' -ForegroundColor Red; return }
    Write-Host "`nSolution:" -ForegroundColor Cyan
    Show-Board (ConvertFrom-Solution $result.Solutions[0])
}

function Invoke-Generate {
    $empty = ConvertTo-Constraint (@('...........' ) * 5)
    $result = Find-KanoodleSolutions -Constraint $empty -MaxSolutions 1 -Randomize -RandomSeed $Seed -Collect -ShowSpinner
    $solved = ConvertFrom-Solution $result.Solutions[0]
    $rng = if ($Seed) { [Random]::new($Seed) } else { [Random]::new() }
    $safeClueCount = [Math]::Min(12, [Math]::Max(0, $CluePieces))
    $visible = @($script:Colors.Keys | Sort-Object { $rng.Next() } | Select-Object -First $safeClueCount)
    $puzzle = @($solved | ForEach-Object { $row = $_; -join ($row.ToCharArray() | ForEach-Object { if ($_ -in $visible) { $_ } else { '.' } }) })
    Write-Host "`nRandom puzzle ($($visible.Count) placed pieces):" -ForegroundColor Cyan
    Show-Board $puzzle
    Write-Host
    $reveal = Read-Host 'Enter R to reveal the answer, or press Enter to keep solving'
    if ($reveal.Trim().ToUpperInvariant() -eq 'R') {
        Write-Host "`nAnswer:" -ForegroundColor Cyan
        Show-Board $solved
    } else {
        Write-Host 'Answer hidden.' -ForegroundColor DarkGray
    }
}

function Invoke-Count([string[]]$Lines) {
    $constraint = ConvertTo-Constraint $Lines
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Find-KanoodleSolutions -Constraint $constraint -MaxSolutions $Limit -ShowSpinner
    $watch.Stop()
    $suffix = if ($Limit -gt 0 -and $result.Count -ge $Limit) { '+' } else { '' }
    Write-Host "Solutions found: $($result.Count)$suffix  Time: $([Math]::Round($watch.Elapsed.TotalSeconds,2))s" -ForegroundColor Cyan
    if ($suffix) { Write-Host 'The + means counting stopped at the requested limit.' -ForegroundColor DarkGray }
}

if ($MyInvocation.InvocationName -eq '.') { return }
if ($Mode -eq 'Demo') { Show-Board $script:Example; exit }
if ($Mode -eq 'Solve') { Invoke-Solve $(if ($Board) { $Board } else { Read-Board }); exit }
if ($Mode -eq 'Generate') { Invoke-Generate; exit }
if ($Mode -eq 'Count') { Invoke-Count $(if ($Board) { $Board } else { Read-Board }); exit }

while ($true) {
    Write-Host "`nKanoodleCLI" -ForegroundColor Cyan
    Write-Host '[1] Solve a puzzle  [2] Generate random puzzle  [3] Count solutions  [4] Example  [Q] Quit'
    switch ((Read-Host 'Choose').ToUpperInvariant()) {
        '1' { Invoke-Solve (Read-Board) }
        '2' { Invoke-Generate }
        '3' { Invoke-Count (Read-Board) }
        '4' { Show-Board $script:Example }
        'Q' { return }
        default { Write-Host 'Please choose 1, 2, 3, 4, or Q.' -ForegroundColor Yellow }
    }
}
