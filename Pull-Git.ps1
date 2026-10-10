param(
    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot
Set-Location -LiteralPath $RepoRoot

$branch = (& git branch --show-current 2>$null | Where-Object { $_ }) -join ''
if (-not $branch) { throw '当前不在任何 git 分支上。' }

if ($Message) {
    & git add -A
    & git commit -m $Message
}

Write-Host "正在从 GitHub 拉取 $branch ..."
$pull = & git pull --rebase origin $branch 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($pull -join "`n") -ForegroundColor Red
    & git rebase --abort 2>$null
    throw 'pull --rebase 失败，已回退。请手动解决冲突后重试。'
}
Write-Host ($pull -join "`n")
Write-Host '拉取完成。镜像/工具等大文件不在 git 里，需要时把 pack 包放到仓库根目录后双击 unpack.bat。' -ForegroundColor Green