<#
.SYNOPSIS
Copies addons from this repository into the game's AddOns folder, without their tests.

.DESCRIPTION
For each addon, the game's copy is updated in place to match the repository's folder minus its
"tests" folder, which is what a release zip contains. Changed files are copied, and files the
repository no longer has are removed. The addon's folder itself is never deleted, so a file or
folder another program holds open can't leave the addon half-deleted. Only this repository's
three addon folders in the given AddOns folder are touched. The sync refuses a game copy that
is, or contains, a junction or link or a .git folder, and refuses when this repository lies
inside the AddOns folder or inside a game copy.

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
    if ($KnownAddons -notcontains $name) { throw "Not one of this repository's addons: $name" } # guards the removals
    $src = Join-Path $Repo $name
    if (-not (Test-Path -LiteralPath (Join-Path $src "$name.toc") -PathType Leaf)) { throw "Missing $src\$name.toc" }
    $dst = Join-Path $Target $name

    # Never mirror over this repository: /MIR would purge everything the addon folder doesn't have,
    # .git and unpushed work included, if the repository sits inside the game's copy.
    if ($RepoFull.StartsWith($dst.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "${name}: this repository is inside the game's copy ($dst); keep the repository outside the AddOns folder"
    }
    if (Test-Path -LiteralPath (Join-Path $dst '.git')) {
        throw "${name}: the game's copy contains a .git folder ($dst); it looks like a repository, so it isn't mirrored over"
    }
    # Never mirror into or through a junction or symbolic link: removing "extra" files there would
    # delete another folder's files (robocopy's /MIR purge follows a junction inside the copy).
    if (Test-Path -LiteralPath $dst) {
        if ((Get-Item -LiteralPath $dst -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "${name}: the game's copy is a junction or link ($dst); remove it yourself first"
        }
        $link = Get-ChildItem -LiteralPath $dst -Recurse -Force -Attributes ReparsePoint | Select-Object -First 1
        if ($link) { throw "${name}: the game's copy contains a junction or link ($($link.FullName)); remove it yourself first" }
    }
    # /MIR copies changed files and removes files the repository no longer has, in place. The
    # repository's tests folder is excluded; a tests folder already in the game's copy goes below.
    $log = & robocopy $src $dst /MIR /XJ /XD (Join-Path $src 'tests') /R:2 /W:2 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) {
        $log | Write-Host
        throw "robocopy failed for $name (exit code $LASTEXITCODE). The game's copy may be partly updated; run the sync again once whatever holds the files has let go."
    }
    $dstTests = Join-Path $dst 'tests'
    if (Test-Path -LiteralPath $dstTests) {
        try { Remove-Item -LiteralPath $dstTests -Recurse -Force }
        catch { throw "${name}: the addon is synced, but its old tests folder is in use ($dstTests); run the sync again later to remove it" }
    }

    # Verify: every source file outside tests\ arrived with the same size, and nothing else is there.
    $srcFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force |
        Where-Object { $_.FullName.Substring($src.Length + 1) -notmatch '^tests(\\|$)' })
    foreach ($file in $srcFiles) {
        $rel = $file.FullName.Substring($src.Length + 1)
        $copy = Join-Path $dst $rel
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf) -or (Get-Item -LiteralPath $copy -Force).Length -ne $file.Length) {
            throw "${name}: $rel wasn't copied correctly"
        }
    }
    $dstFiles = @(Get-ChildItem -LiteralPath $dst -Recurse -File -Force)
    if ($dstFiles.Count -ne $srcFiles.Count) {
        $expected = @{}
        foreach ($file in $srcFiles) { $expected[$file.FullName.Substring($src.Length + 1)] = $true }
        $extra = @($dstFiles | ForEach-Object { $_.FullName.Substring($dst.Length + 1) } | Where-Object { -not $expected[$_] })
        throw "${name}: expected $($srcFiles.Count) files in the game's copy, found $($dstFiles.Count). Extra: $(($extra | Select-Object -First 5) -join ', ')"
    }
    if (Test-Path -LiteralPath (Join-Path $dst 'tests')) { throw "${name}: the tests folder was copied" }
    Write-Host ("{0}: {1} files in sync at {2}" -f $name, $srcFiles.Count, $dst)
}
