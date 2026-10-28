# DeckCraft 简体中文 · macOS

DeckCraft 0.11.1 的非官方简体中文构建，以及可以双击运行的 **DeckCraft 汉化器 1.0.0**。

**[下载汉化器和中文版](https://github.com/1247970482/deckcraft-zh-cn/releases/latest)**

目前发布的程序适用于 **Apple Silicon Mac（M 系列芯片，arm64）**。此仓库没有 Windows、Linux 或 Intel Mac 安装包。

## 下载哪个文件

| 文件 | 用途 |
| --- | --- |
| `DeckCraft-Localizer-1.0.0-macos-arm64.zip` | 推荐：解压后双击「DeckCraft 汉化器」，检查已安装的 DeckCraft，再安装简体中文 |
| `DeckCraft-0.11.1-zh-Hans-macos-arm64.zip` | 独立中文版，解压后得到「DeckCraft 中文版.app」 |
| `SHA256SUMS.txt` | 两个下载包的 SHA-256 校验值 |

汉化器内置中文应用，离线运行。使用者不需要安装 Python、Rust 或 Xcode。

## 使用汉化器

1. 保存演示文稿并退出 DeckCraft。
2. 解压汉化器 ZIP，双击「DeckCraft 汉化器.app」。
3. 默认检测 `/Applications/DeckCraft.app`；也可以选择其他位置的 DeckCraft 应用。
4. 确认版本兼容后，点击「安装简体中文」。
5. 安装成功后打开 DeckCraft。

安装前会完整备份原应用。安装过程只替换选中的应用包，个人设置和演示文稿不在替换范围内。程序会核对版本、原可执行文件 SHA-256、中文资源逐文件 SHA-256 和本地代码签名；安装失败时尝试恢复原应用。再次检测到相同中文版时不会重复安装或备份。

**版本匹配是必须的：** 当前只适配已验证的官方 DeckCraft 0.11.1 arm64 构建。相同版本的其他构建、未知版本和后续新版都会停止处理。以后官方更新可能覆盖汉化，需要针对新版重新适配；本工具不会把新版强行降级为 0.11.1。

程序是本地编译并使用 ad-hoc 签名的社区构建，未获得 Apple Developer ID 签名或公证。macOS 可能提示无法验证开发者；请先核对来源与校验值，再使用系统提供的应用打开流程。本工具不会关闭系统安全保护或修改隔离属性。

## 恢复原版

在汉化器中打开备份目录，或在 Finder 前往：

```text
~/Library/Application Support/DeckCraft 汉化器/Backups/
```

退出 DeckCraft，将当前应用移到其他位置保留，再把对应备份里的 `DeckCraft-安装前.app` 复制回原安装位置并改名为 `DeckCraft.app`。请按备份记录选择与本次安装对应的目录。

## 汉化范围

首页、菜单、macOS 应用菜单、功能区、命令搜索、设置、对话框、格式面板、放映，以及形状、图标、SmartArt、图表和动画的显示名称。品牌、字体名称和技术标识保留原文。用户演示文稿、模板和示例正文不自动翻译。

稳定命令 ID、文件格式与序列化键保留兼容。界面中文显示使用 macOS 已安装的苹方简体；没有打包分发 Apple 系统字体。程序内置的开源字体保留相应许可。

## 源码、验证与来源

- [构建说明](BUILD.md)：包含完整中文补丁和原生汉化器源码。
- [验证范围](VALIDATION.md)：13 项汉化器测试、原生安装与回退验收，以及中文应用专项验证的范围。
- DeckCraft 上游：[storytold/deckcraft](https://github.com/storytold/deckcraft)，基于提交 `9ec39267931c0163dd5648c879043edcb9603cb8`（0.11.1）。
- 字体输入：[storytold/craft-fonts](https://github.com/storytold/craft-fonts)，固定提交 `43913056ce82a3fdad0ef69f6b88d1dc922a8104`。

这是独立社区汉化发布，与 DeckCraft / ArtCraft 官方没有隶属关系。DeckCraft 原作者、贡献者及第三方资产的权利与署名保留。代码按 **MIT OR Apache-2.0** 分发，见 [LICENSE-MIT](LICENSE-MIT)、[LICENSE-APACHE](LICENSE-APACHE)、[NOTICE](NOTICE)、[资产署名](ATTRIBUTION.md) 和 [字体署名](FONT-ATTRIBUTION.md)。ArtCraft 品牌素材另见 [品牌条款](LICENSE-brand.txt)，只用于识别原项目。

## English

Unofficial Simplified Chinese localization of DeckCraft 0.11.1 and an offline native macOS localizer. Release binaries are **Apple Silicon / arm64 only**. The localizer verifies the exact supported build, backs up the original app, and installs the bundled Chinese build. Unknown or newer versions are rejected. These community builds are ad-hoc signed and are not Apple notarized. Source patches and build instructions are included; upstream and third-party licenses are preserved.
