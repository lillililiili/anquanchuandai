# 安卓文件归档与恢复

2026-09-17 按用户要求，将确认不参与安卓运行和构建的 15 个文件剪切到 `2026-09-17-安卓清理/`，合计 1,746,879 字节。没有永久删除。

## 路径约定

- 原路径统一相对于工作区根目录 `C:/Users/qiyue/Desktop/开发项目`。
- 归档文件保留完整原目录结构，例如原 `android代码/android-launch.png` 现在位于 `垃圾桶/2026-09-17-安卓清理/android代码/android-launch.png`。
- [恢复清单.csv](2026-09-17-安卓清理/恢复清单.csv) 逐项记录原相对路径、归档相对路径、字节数、SHA-256 和移动原因。

## 归档内容

- 1 个空的 `pubspec.lock.restored` 恢复残留。
- 1 个 `.perch-backup` 源码备份；正常 `.dart` 文件保留。
- `android代码/` 根目录下的 10 张历史截图、3 个历史 UI 层级 XML。这些是历史证据归档，不是程序资源；3 个 XML 在旧静态库存 `docs/planning/code-inventory.json` 中有路径记录。

## 恢复方式

在文件管理器中，将文件从本批次目录剪切回工作区内相同相对路径。如果原位置后来已产生同名文件，先对比内容，不要直接覆盖。

例如，恢复 `android-launch.png`：

```powershell
Set-Location 'C:/Users/qiyue/Desktop/开发项目'
$original = 'android代码/android-launch.png'
$archived = '垃圾桶/2026-09-17-安卓清理/android代码/android-launch.png'
if (Test-Path -LiteralPath $original) { throw '原位置已有同名文件，请先比较内容' }
Move-Item -LiteralPath $archived -Destination $original
```

恢复后可用 `Get-FileHash -Algorithm SHA256 -LiteralPath <文件路径>` 与清单核对。

## 保留内容

当前 assets、旧版 `LEGACY_DEMO` 源码、平台目录、插件、SDK、构建缓存以及被交付文档引用的 `build/verification/` 均保留。旧源码 ZIP 与当前工程内容不同，也保留。此次移动的 14 个历史文件原先被 Git 跟踪，因此工作区会显示原路径删除和垃圾桶新增；这不表示文件已丢失。
