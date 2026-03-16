param(
    [string]$PythonExe = "python",
    [string]$RepoUrl = "https://github.com/graphdeco-inria/diff-gaussian-rasterization",
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        $argList = if ($Arguments.Count -gt 0) { " " + ($Arguments -join " ") } else { "" }
        throw "Command failed: $FilePath$argList"
    }
}

function Remove-DirectoryTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not [System.IO.Directory]::Exists($Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            try {
                [System.IO.File]::SetAttributes($_.FullName, [System.IO.FileAttributes]::Normal)
            }
            catch {
            }
        }

    try {
        [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Normal)
    }
    catch {
    }

    try {
        [System.IO.Directory]::Delete($Path, $true)
    }
    catch {
        Write-Warning "Could not remove temporary directory: $Path"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("diff-gaussian-rasterization-" + [System.Guid]::NewGuid().ToString("N"))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

try {
    Invoke-Step -FilePath "git" -Arguments @("clone", $RepoUrl, $tempRoot)
    Invoke-Step -FilePath "git" -Arguments @("-C", $tempRoot, "submodule", "update", "--init", "--recursive")

    foreach ($relativePath in @("rasterize_points.h", "rasterize_points.cu")) {
        $fullPath = Join-Path $tempRoot $relativePath
        $content = [System.IO.File]::ReadAllText($fullPath)
        $updated = $content.Replace("#include <torch/extension.h>", "#include <torch/types.h>")

        if ($content -eq $updated) {
            throw "Expected include not found in $relativePath"
        }

        [System.IO.File]::WriteAllText($fullPath, $updated, $utf8NoBom)
    }

    Invoke-Step -FilePath $PythonExe -Arguments @("-m", "pip", "install", $tempRoot, "--no-build-isolation")
}
finally {
    if (-not $KeepTemp -and [System.IO.Directory]::Exists($tempRoot)) {
        Remove-DirectoryTree -Path $tempRoot
    }
}
