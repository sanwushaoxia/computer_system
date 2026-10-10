# Win7 安装盘镜像：备份与恢复

双击 **`启动Win7备份恢复.bat`**。弹出用户账户控制时选「是」。

## 菜单

| 项 | 作用 |
|----|------|
| 1 查看状态 | 镜像大小、记录的哈希、oscdimg / bootsect / Rufus、当前 U 盘 |
| 2 从 U 盘备份 | 只读取 U 盘，做成不含 `System Volume Information` 的可启动 ISO，并更新 `SHA256.txt` |
| 3 校验 ISO | 计算 SHA256，并检查 `bootmgr`、`install.wim`、是否还有 `System Volume Information` |
| 4 写入 U 盘 | 把 ISO 做成 **FAT32 + MBR** 安装盘。会清空所选 U 盘 |
| 5 重建干净 ISO | 从现有 ISO 去掉 `System Volume Information` 后重新打包 |
| 6 打开 Rufus | 图形界面备用。做成 FAT32 请用第 4 项 |

写入时只列出 USB 磁盘。需要输入磁盘号，再输入大写 `YES`。系统盘不在可选范围内。

日志在 `logs\`：`backup.log`、`verify.log`、`restore.log`、`rebuild.log`。

## 当前镜像

| 项 | 说明 |
|----|------|
| 文件 | `image\win7_install_usb.iso` |
| 大小 | 约 3.59 GB（3852859392 字节） |
| SHA256 | `AD6677A5D02F41EB0D2D30C88CD179BC1DED465F9E388B23CEB103652516D53A` |
| 上一份 | `image\win7_install_usb.iso.bak` |

只有约 3.6GB，是因为打包的是安装文件，不含 U 盘空白扇区。

备份或重建成功后，旧的 ISO 会改名为 `image\win7_install_usb.iso.bak`（只保留上一份），`image\SHA256.txt` 会写成新哈希。

## 写入 U 盘

- 使用 **8GB 到 32GB** 的 U 盘。大于 32GB 时，Windows 自带工具通常无法格式化成 FAT32
- 卷标 `WIN7USB`，分区为 MBR，活动分区，并写入 `bootsect /nt60 /mbr`
- 复制时跳过 `System Volume Information`
- 完成后用 **USB 2.0** 接口，在 BIOS 中启用 **Legacy/CSM** 启动

## 注意

- 第 4 项会清空所选 U 盘
- 选盘时只认 USB 磁盘；仍要核对名称和容量后再输入 `YES`
- 镜像里若有大于等于 4GB 的文件，不能写入 FAT32，程序会在清空 U 盘之前停下来
- 请再复制一份本目录到移动硬盘

## 目录

| 路径 | 作用 |
|------|------|
| `启动Win7备份恢复.bat` | 入口，留在根目录 |
| `scripts\` | 菜单和备份、校验、写入、重建脚本 |
| `image\` | `win7_install_usb.iso`、`.bak`、`SHA256.txt`、`iso_clean\` |
| `tools\Rufus\` | Rufus 程序和它的配置 |
| `docs\` | 本说明 |
| `logs\` | 运行日志 |

`scripts\make_win7_usb_fat32.ps1` 和 `scripts\rebuild_clean_iso.ps1` 会转到上面的新脚本。
