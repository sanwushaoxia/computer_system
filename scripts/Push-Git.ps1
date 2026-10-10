param(
    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepoRoot

function Git-Line($Output) { ($Output | Where-Object { $_ -ne '' }) -join ' ' }

$branch = Git-Line (& git branch --show-current 2>$null)
if (-not $branch) { throw '当前不在任何 git 分支上。' }

$dirty = & git status --porcelain
if (-not $dirty) {
    Write-Host '没有需要提交的更改。' -ForegroundColor Yellow
}
else {
    if (-not $Message) { $Message = '更新 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') }
    Write-Host ("提交信息：{0}" -f $Message)
    & git add -A
    & git commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw "commit 失败，退出码 $LASTEXITCODE。" }
    Write-Host '已提交。' -ForegroundColor Green
}

Write-Host '正在拉取远程更新（rebase）...'
$pull = & cmd /c "git pull --rebase origin $branch 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host ($pull -join "`n") -ForegroundColor Red
    & git rebase --abort 2>$null
    throw 'pull --rebase 失败，已回退。请手动解决冲突后再推。'
}

Write-Host '正在推送到 GitHub...'
$push = & cmd /c "git push origin $branch 2>&1"
$push | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw "push 失败，退出码 $LASTEXITCODE。" }
Write-Host '推送完成。大文件不随 git 上传，需要同步时另跑 scripts\pack.bat。' -ForegroundColor Green