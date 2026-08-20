# KanoodleCLI

KanoodleCLI is a terminal application that models the 5×11 Kanoodle rectangle using the 12 official pieces. It can solve partial boards, generate random full tilings/puzzles, and count solutions.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 (included with Windows) or PowerShell 7
- Git, only if installing by cloning the repository

No PowerShell modules or third-party packages are required. Colors are mapped to the closest console colors so they work in both PowerShell hosts.

## Install

Clone the repository and enter its directory:

```powershell
git clone https://github.com/CtrlAltWiz/KanoodleCLI.git
Set-Location .\KanoodleCLI
```

Alternatively, download the repository as a ZIP from GitHub, extract it, and open PowerShell in the extracted folder.

If Windows reports that script execution is disabled, unblock only this downloaded script:

```powershell
Unblock-File .\KanoodleCLI.ps1
```

## Run

Start the interactive menu:

```powershell
.\KanoodleCLI.ps1
```

The menu provides options to solve a puzzle, generate a random puzzle, count solutions, or display the example board.

_Example 1:_

<img width="848" height="57" alt="image" src="https://github.com/user-attachments/assets/e49d80b1-44a0-4021-b948-a8f8aa058d7c" />



Useful non-interactive commands:

```powershell
# Show the supplied example using colored dots
.\KanoodleCLI.ps1 -Mode Demo

# Generate a puzzle with four already-placed pieces
.\KanoodleCLI.ps1 -Mode Generate -CluePieces 4 -Seed 42

# Solve a board (dots are unknown cells). From an existing PowerShell session:
& ./KanoodleCLI.ps1 -Mode Solve -Board @(
  '...........','...........','...........','...........','...........'
)

# Count every solution for a board; set -Limit for a quick bounded count
& ./KanoodleCLI.ps1 -Mode Count -Limit 1000 -Board @(
  '...........','...........','...........','...........','...........'
)
```

Board input uses `A` through `L` for dots belonging to a placed piece, and `.` or `*` for empty holes. A clue letter fixes the entire matching piece: include all of that piece's visible dots.

_Example 2:_

<img width="858" height="282" alt="image" src="https://github.com/user-attachments/assets/955c1caa-1fca-4382-b500-0b1f6f4eb9b6" />

Solve, Generate, and Count display a live `Thinking` spinner while their searches run. The placement catalog is cached for the lifetime of the interactive app, so later operations in the same session start faster. The solver also represents the entire board as a single 64-bit occupancy mask for quicker overlap checks.

Generated puzzles keep their answers hidden. Enter `R` at the reveal prompt to show the completed board, or press Enter to return without revealing it.

_Example 3:_

<img width="826" height="219" alt="image" src="https://github.com/user-attachments/assets/1a3119c4-7551-47bb-99ad-fd90b59be5c9" />

Counting a completely blank board is still substantially harder than solving a normal challenge because it must explore every valid completion. Use `-Limit` when you only need a bounded result or performance check; omit it only when you intentionally want exhaustive enumeration.

## Colors
<img width="196" height="76" alt="image" src="https://github.com/user-attachments/assets/c9182612-71c5-4c4b-ae03-79d7483977a1" />

| Letter | Piece color |
|---|---|
| A | Orange |
| B | Red |
| C | Blue |
| D | Light pink |
| E | Green |
| F | White |
| G | Light blue |
| H | Pink |
| I | Yellow |
| J | Purple |
| K | Light green |
| L | Grey |

## Official guide coverage and the number 180

The official 2026 guide contains 228 published challenges:

- D001-D180 are 2D challenges on the 5×11 board supported by this app.
- D181-D228 are 3D pyramid challenges and are outside the current 2D solver's scope.

Sources:

https://www.educationalinsights.com/amfile/file/download/file/13083/product/940/

https://www.educationalinsights.com/amfile/file/download/file/13086/product/940/

Therefore, 180 is the size of the official 2D challenge collection, not the number of possible completed 5×11 arrangements. `Count` enumerates mathematical solutions compatible with the entered clues. Reflections and rotations of the whole rectangular board are counted separately, and differently colored pieces remain distinct physical pieces.

The piece footprints, letter labels, and colors were cross-checked against the official Kanoodle guide and solution booklet. The guide's setup rule also matches the solver: colored pieces shown in a challenge are fixed and cannot be moved while solving.
