# Win10 安装盘（Ventoy / Rufus）

目标机：老主板（Legacy/UEFI 双模），Kingston DataTraveler 3.0 32GB。

## 当前经验证的稳定方法：Rufus

镜像：`image\Windows_10.iso`

制作方式（任选其一）：

- 双击「启动Win10安装盘.bat」→ 菜单选 `4`（Rufus 制作，默认 UEFI/GPT）
- 手动运行：`rufus\rufus-4.15p.exe -i image\Windows_10.iso`

Rufus 界面设置：

1. 设备：目标 U 盘
2. 分区结构：GPT，目标系统：UEFI（非 CSM）
3. 文件系统：NTFS（默认），点「开始」→ 选「以 ISO 镜像模式写入(推荐)」

已验证：目标机可直接 U 盘启动并完成安装，无「缺少媒体驱动」、无数据损坏。
Rufus 标准模式不经过 Ventoy——没有虚拟光驱、没有 vtoyflt 过滤驱动，PE 直接读盘。

## 有问题的方法（待后续定位解决）

**Ventoy 启动安装：安装阶段从 U 盘读出的数据静默损坏。**

已试组合（均失败）：

| Ventoy 版本 | 数据分区 | 结果 |
|---|---|---|
| 1.1.18 | NTFS | PE 阶段读坏 |
| 1.1.05 | exFAT | PE 阶段读坏 |

（1.1.05 + NTFS 曾短暂存在于盘上，随后被 exFAT 重做覆盖，未单独验证。）

现象：

- WIM 模式（Ctrl+w）能进 PE、能读到 Autounattend.xml，但 Setup 读 `install.wim` 报 `0x8007000D`
- PE 里 `xcopy D:\sources → C:` 800+ 文件全部"成功"、无 I/O 错误，但拷出的 `setup.exe`（大小一致）无法加载 = 数据被静默读坏
- 普通 ISO 模式偶发 `\EFI\Microsoft\Boot\BCD` 0xc000014c；Setup 自动扫描被 Ventoy 虚拟光驱挡住报「缺少媒体驱动」

关键证据：

- 同一根 U 盘在**完整 Windows 下读取完好**：`certutil -hashfile D:\sources\install.wim SHA1` = `2989a3a2f5f612c5837eb1f67512a879f6cea216`，与镜像内文件一致
- ISO 本身完好（与官方尺寸逐字节一致）；U 盘在制机上拷贝完好
- PE 里盘符稳定：F: = Ventoy 虚拟光驱（UDF），D: = Ventoy 数据分区，C: = 内置盘
- Rufus 盘（同样的 U 盘、同样的 PE、同样的目标机）安装正常 → **排除 PE 自身 USB 驱动栈和硬件链路**

结论：元凶在 Ventoy 运行时（vtoyflt 过滤驱动 / 虚拟光驱重映射）与该主板 PE 环境的组合，与 Ventoy 版本、数据分区文件系统无关。

待定位方向（如需恢复 Ventoy）：

1. 老版本 Ventoy（1.0.96 及更早，vtoyflt 构建差异更大）
2. Ventoy 插件控制：禁用虚拟光驱相关行为（`ventoy.json` 的 `auto_memdisk` / 控制插件）
3. 其他主控的 U 盘交叉测试（区分主控特异性）
4. 目标机换 USB 2.0 口复测

相关文件：`ventoy\`（Ventoy 压缩包，1.1.05 / 1.1.18）、`scripts\`（制作与诊断脚本）、`logs\`（make.log）。