# 构建说明

## 还原中文应用源码

需要 Git、Rust 工具链和 macOS Xcode 命令行工具。下列命令在本仓库根目录执行。`work/` 是构建工作目录，不应提交到 Git。

```sh
mkdir -p work
git clone https://github.com/storytold/deckcraft.git work/deckcraft
git -C work/deckcraft checkout --detach 9ec39267931c0163dd5648c879043edcb9603cb8
git -C work/deckcraft apply --check ../../deckcraft-0.11.1-zh-Hans.patch
git -C work/deckcraft apply ../../deckcraft-0.11.1-zh-Hans.patch
git clone https://github.com/storytold/craft-fonts.git work/craft-fonts
git -C work/craft-fonts checkout --detach 43913056ce82a3fdad0ef69f6b88d1dc922a8104
export CRAFT_FONTS_DIR="$PWD/work/craft-fonts"
export CRAFT_FONTS_REQUIRED=1
cargo build --manifest-path work/deckcraft/Cargo.toml --release --locked -p deckcraft
```

补丁包含 65 个修改或新增文件，包括原生应用菜单、中文显示与专项测试。它针对固定的上游提交；不能保证直接应用到新版。字体构建仍执行上游排除规则。

将生成的 `work/deckcraft/target/release/deckcraft` 封装为 macOS App 时，使用本仓库 `DeckCraft-Info.plist`，可执行文件命名为 `Contents/MacOS/DeckCraft`，图标使用上游 `assets/app-icon/deckcraft.icns` 并命名为 `Contents/Resources/DeckCraft.icns`。保留上游 README、两个代码许可证、NOTICE、ATTRIBUTION.md 和实际嵌入字体的许可证。使用 `/usr/bin/codesign --force --sign - --options runtime` 签署完成的应用包，并执行 `codesign --verify --deep --strict`。

编译器和 SDK 变化可能改变二进制哈希。`release-config.json` 记录本次已验证发布的精确哈希。自行重新编译后，应完成验证再更新配置中的中文可执行文件哈希，不能只修改原版匹配哈希或版本号来宣称兼容。

## 构建汉化器

原生界面与安装核心源码分别是 `main.swift`、`Core.swift`；图标由 `icon.swift` 生成。`Tests.swift` 包含文件系统安装测试。

需要 Python 3.11+ 和 Xcode 命令行工具。先运行测试：

```sh
python3 build_localizer.py --tests
```

使用从本仓库 Release 解压得到的已验证中文版作为内置程序：

```sh
python3 build_localizer.py --payload-app "/path/to/DeckCraft 中文版.app"
```

输出位于 `dist/DeckCraft 汉化器.app` 和 `dist/DeckCraft 汉化器-1.0.0.zip`。已有输出不会覆盖；更换 `--output-dir` 后可再次构建。

```sh
python3 build_localizer.py --payload-app "/path/to/DeckCraft 中文版.app" --output-dir dist-next
```

构建脚本会验证内置程序哈希、编译 arm64 工具、生成逐文件资源目录、签名，并执行只读验证。用户运行发布后的 App 不需要上述开发依赖。

## 适配新版本

先在新上游版本合并中文修改并编译、验证，再维护配置和资源。汉化器采用精确版本及哈希匹配，不能直接给未知新版套用旧包。原始发布二进制、源码补丁和适配说明应同时保留，便于核对与回退。
