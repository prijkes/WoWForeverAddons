<#
.SYNOPSIS
Copies addons from this repository into the game's AddOns folder, without their tests.

.DESCRIPTION
For each addon, the game's copy is deleted and replaced by the repository's folder minus its
"tests" folder, so it matches what a release zip contains. Only this repository's three addon
folders can be touched.

.EXAMPLE
tools\sync-to-game.ps1 -SetAddOnsPath "<WoW folder>\_classic_beta_\Interface\AddOns"
Saves the AddOns folder for this PC (in the git-ignored tools\sync-to-game.local).

.EXAMPLE
tools\sync-to-game.ps1 -All

.EXAMPLE
tools\sync-to-game.ps1 -Addon ForeverAddonFixes
#>
[CmdletBinding(DefaultParameterSetName = 'One')]
param(
    [Parameter(ParameterSetName = 'One', Mandatory, Position = 0)]
    [ValidateSet('ForeverFlightTimer', 'ForeverInstanceTimer', 'ForeverAddonFixes')]
    [string[]] $Addon,

    [Parameter(ParameterSetName = 'All', Mandatory)]
    [switch] $All,

    [Parameter(ParameterSetName = 'One')]
    [Parameter(ParameterSetName = 'All')]
    [string] $AddOnsPath,

    [Parameter(ParameterSetName = 'Set', Mandatory)]
    [string] $SetAddOnsPath
)

$ErrorActionPreference = 'Stop'
$KnownAddons = @('ForeverFlightTimer', 'ForeverInstanceTimer', 'ForeverAddonFixes')
$Repo = Split-Path -Parent $PSScriptRoot
$LocalFile = Join-Path $PSScriptRoot 'sync-to-game.local'

# Returns the full path of an existing folder that ends in \Interface\AddOns, or throws.
function Resolve-AddOnsFolder([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "AddOns folder not found: $Path" }
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath.TrimEnd('\')
    if ($full -notmatch '\\Interface\\AddOns$') { throw "Not a game AddOns folder (it must end in \Interface\AddOns): $full" }
    return $full
}

if ($PSCmdlet.ParameterSetName -eq 'Set') {
    $full = Resolve-AddOnsFolder $SetAddOnsPath
    Set-Content -LiteralPath $LocalFile -Value $full -Encoding utf8
    Write-Host "Saved the AddOns folder: $full"
    return
}

if (-not $AddOnsPath) {
    if (-not (Test-Path -LiteralPath $LocalFile)) {
        throw "No AddOns folder is set. Run once: tools\sync-to-game.ps1 -SetAddOnsPath '<WoW folder>\_classic_beta_\Interface\AddOns'"
    }
    $AddOnsPath = (Get-Content -LiteralPath $LocalFile -Raw).Trim()
}
$Target = Resolve-AddOnsFolder $AddOnsPath
$RepoFull = (Resolve-Path -LiteralPath $Repo).ProviderPath.TrimEnd('\') + '\'
if (($Target + '\').StartsWith($RepoFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The AddOns folder is inside this repository: $Target"
}
$Names = if ($All) { $KnownAddons } else { $Addon }

foreach ($name in $Names) {
    if ($KnownAddons -notcontains $name) { throw "Not one of this repository's addons: $name" } # guards the delete
    $src = Join-Path $Repo $name
    if (-not (Test-Path -LiteralPath (Join-Path $src "$name.toc") -PathType Leaf)) { throw "Missing $src\$name.toc" }
    $dst = Join-Path $Target $name

    if (Test-Path -LiteralPath $dst) {
        # Never delete through a junction or symbolic link: that could reach another folder's files.
        $item = Get-Item -LiteralPath $dst -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "${name}: the game's copy is a junction or link ($dst); remove it yourself first"
        }
        Remove-Item -LiteralPath $dst -Recurse -Force
    }
    $log = & robocopy $src $dst /E /XD (Join-Path $src 'tests') /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) {
        $log | Write-Host
        throw "robocopy failed for $name (exit code $LASTEXITCODE)"
    }

    # Verify: every source file outside tests\ arrived with the same size, and nothing else is there.
    $srcFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File |
        Where-Object { $_.FullName.Substring($src.Length + 1) -notmatch '^tests(\\|$)' })
    foreach ($file in $srcFiles) {
        $rel = $file.FullName.Substring($src.Length + 1)
        $copy = Join-Path $dst $rel
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf) -or (Get-Item -LiteralPath $copy).Length -ne $file.Length) {
            throw "${name}: $rel wasn't copied correctly"
        }
    }
    $dstCount = @(Get-ChildItem -LiteralPath $dst -Recurse -File).Count
    if ($dstCount -ne $srcFiles.Count) { throw "${name}: expected $($srcFiles.Count) files in the game's copy, found $dstCount" }
    if (Test-Path -LiteralPath (Join-Path $dst 'tests')) { throw "${name}: the tests folder was copied" }
    Write-Host ("{0}: {1} files copied to {2}" -f $name, $srcFiles.Count, $dst)
}
