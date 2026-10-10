# computer_system

Windows 安装盘制作工具集：`win10\`（Win10 Rufus/Ventoy 安装盘）、`win7\`（Win7 镜像备份/恢复）、`rufus\`、`ventoy\`（公共工具）。

## 在其他机器继续工作

代码走 git，大文件走 pack 包，两边都要同步。

### 1. 代码（小，git push / pull）

```bash
# 本机推送（双击 scripts\push.bat，或指定提交信息）
powershell -File scripts\Push-Git.ps1 -Message "说明"

# 其他机器拉取（双击 scripts\pull.bat）
git clone https://github.com/sanwushaoxia/computer_system.git   # 首次
powershell -File scripts\Pull-Git.ps1                           # 后续更新
```

git 只包含：`scripts\*.ps1`、`*.bat`、`docs\`、`logs\`、`README.md`（详见 `.gitignore`）。
镜像、工具、镜像解压目录全部被忽略，**clone 下来还不能直接制作安装盘**，需执行第 2 步。

### 2. 大文件（约 21GB，pack 包）

**本机导出（二选一）：**

```
双击 scripts\pack.bat                       → 生成 pack\ 目录（ISO 为硬链接，秒完成）
powershell -File scripts\Pack-LargeFiles.ps1 -Zip  → 生成 pack\computer-system-largefiles-<时间>.zip
```

- `pack\` 目录可直接整体上传（网盘/移动硬盘）；zip 模式适合单文件传输
- 上传前不要删除仓库里的源 ISO（硬链接指向同一文件）
- 包内含 `README-restore.txt` 还原对照表

**其他机器导入（自动化）：**

```
把 pack 目录（或 zip）放到仓库根目录旁边，双击 scripts\unpack.bat
或：powershell -File scripts\Unpack-LargeFiles.ps1 [-Source pack\...] [-KeepSource]
```

- 自动识别来源：`pack\` 目录或 `computer-system-largefiles-*.zip`（zip 先解压到临时目录）
- 默认**移动**导入（输入 YES）；回车或加 `-KeepSource` 则复制保留 pack 源
- 导入后自动核对每个条目，最后跑各项目菜单（如 `win10\启动Win10安装盘.bat` 选 1）确认状态

手工方式（备用）：把 pack 包内容按 `README-restore.txt` 放回仓库根目录对应位置：

| 包内条目 | 放置位置 |
|---|---|
| `win10\image\*.iso` | `win10\image\` |
| `win7\image\*`（含 `iso_clean\`） | `win7\image\` |
| `ventoy\` | 仓库根目录 `ventoy\` |
| `rufus\` | 仓库根目录 `rufus\` |

放好后运行各项目菜单确认状态（如 `win10\启动Win10安装盘.bat` → 选 1），齐了就能继续工作。

### 常见遗漏排查

- 制作脚本报「找不到 ventoy-*-windows.zip」→ 没导入 `ventoy\`
- Rufus 菜单报找不到 → 没导入 `rufus\`
- 菜单状态页镜像「找不到」→ 没导入 `win10\image\`