# 迁移 Win10 引导到 D 盘所在磁盘

> 目标：C 盘（磁盘 1）装 Win11，D 盘（磁盘 0）装 Win10。目前两套系统的引导都挤在磁盘 1 的 EFI 分区里。
> 本文档把 Win10 的引导迁移到磁盘 0 新建的 EFI 分区，实现双系统引导彻底分离。

## 现状（2026-10 实测）

| 磁盘 | 分区 | 说明 |
|---|---|---|
| 磁盘 0（WD 500GB，GPT） | D（NTFS，整盘一个分区） | Win10 系统盘，**没有 EFI 分区** |
| 磁盘 1（Samsung 1TB，GPT） | Recovery / EFI(100MB) / MSR / C / Recovery | Win11 系统盘，EFI 在这里，两套系统引导共用 |

当前 BCD 中 Win10 条目 `{fe0f9c10-dd96-11ef-950d-a056cfbf63da}` 的 `device` / `osdevice` 已显示 `unknown`，条目本身异常，迁移时会被新引导取代。

## 前提

1. **备份 D 盘重要数据**（涉及压缩分区，虽然一般安全，但先备份）。
2. 全部命令在**管理员** PowerShell 中执行（Win+X → 终端(管理员)）。
3. 执行前拔掉所有 U 盘，避免 diskpart 选错磁盘。

## 第 1 步：确认磁盘编号

```powershell
Get-Disk | Format-Table Number,FriendlyName,PartitionStyle,Size -AutoSize
Get-Partition | Sort-Object DiskNumber,PartitionNumber |
    Format-Table DiskNumber,PartitionNumber,DriveLetter,Type,Size -AutoSize
```

确认：**磁盘 0 = D 盘所在磁盘**。如果编号不同，下文所有 `disk 0` 都要相应替换。

## 第 2 步：磁盘 0 上新建 EFI 分区（diskpart）

```powershell
diskpart
```

diskpart 内依次执行：

```
list disk
select disk 0
list partition
select partition 1
shrink desired=300
create partition efi size=300
format quick fs=fat32 label="System"
assign letter=S
exit
```

说明：
- `shrink desired=300` 从 D 盘尾部压缩 300MB。若报错压缩空间不足（NTFS 存在不可移动文件），先对 D 盘做一次碎片整理后重试，或用磁盘管理压缩后再进 diskpart 只做 `create partition efi`。
- `assign letter=S` 只是临时盘符，方便下一步 `bcdboot`。

## 第 3 步：把 Win10 引导写入新 EFI 分区

```powershell
bcdboot D:\Windows /s S: /f UEFI
```

成功时输出 `已成功创建启动文件。`（Boot files successfully created.）

## 第 4 步：验证 Win10 能独立启动（关键，不要跳过）

1. 重启，按主板启动菜单键（开机时按 F8 / F11，视主板而定）。
2. 启动菜单此时应出现**两个** "Windows Boot Manager"（或一个 Windows Boot Manager + 一个 Hard Drive 条目），逐个尝试，选择来自**磁盘 0** 的条目。
3. 能正常进入 Win10，即验证通过。回到 Win11 继续后续步骤。

> 若固件菜单里看不到磁盘 0 的启动项：进主板 BIOS 手动添加启动项，路径选磁盘 0 的
> `\EFI\Microsoft\Boot\bootmgfw.efi`；或重启一次让固件自动枚举。

## 第 5 步：删除 C 盘 EFI 里的旧 Win10 条目

回到 Win11，管理员 PowerShell 执行：

```powershell
bcdedit /delete "{fe0f9c10-dd96-11ef-950d-a056cfbf63da}"
bcdedit /enum
```

确认只剩 Windows 11 条目。

> **PowerShell 语法注意**：`{GUID}` 必须加引号，否则 PowerShell 会把它解析成脚本块，报
> "指定的删除命令无效"。裸 GUID（不带大括号）也会报 "指定的项标识符无效"。

## 第 6 步：收尾

移除临时盘符（可选）：

```powershell
mountvol S: /d
```

清理 U 盘残留固件条目（可选，之前 `bcdedit /enum firmware` 中发现的 KingstonDataTraveler/USB 条目）：

```powershell
bcdedit /delete "{c6a874dc-c406-11f1-ab4d-806e6f6e6963}" /f
bcdedit /delete "{c6a874dd-c406-11f1-ab4d-806e6f6e6963}" /f
```

之后固件会在下次开机时自动识别磁盘 0 新 EFI 上的第二个 "Windows Boot Manager"，可用 `bcdedit /enum firmware` 核对。

## 回滚方案

如果迁移后想恢复原状（引导回到 C 盘 EFI），在 Win11 管理员 PowerShell 执行：

```powershell
bcdboot D:\Windows /d /addlast
```

这会在系统分区（磁盘 1 的 EFI）重建 Win10 条目。

## 故障排除

| 现象 | 处理 |
|---|---|
| `shrink desired=300` 压缩失败 | 对 D 盘碎片整理后重试；或用磁盘管理"压缩卷"压缩 300MB+ 后，diskpart 里跳过 shrink 直接 create partition efi |
| `bcdboot` 报 "失败， attempting to copy boot files" | 确认 S: 是 FAT32（`Get-Volume S`）、`D:\Windows` 存在；确认用管理员权限 |
| 固件菜单没有磁盘 0 的启动项 | BIOS 手动添加 `\EFI\Microsoft\Boot\bootmgfw.efi`（磁盘 0）；重插一次该盘数据线/重启触发重新枚举 |
| Win10 启动报 0xc000000e 等 | 进 WinRE 或用本目录的 Ventoy 安装盘进恢复环境，执行 `bcdboot D:\Windows /s S: /f UEFI` 重建 |
| 误删条目导致 Win10 无法引导 | 用回滚方案命令重建，或从 WinRE 重建 |