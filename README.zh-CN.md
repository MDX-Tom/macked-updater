# Macked Updater

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="assets/app-icon.png" alt="Macked Updater 图标" width="112" height="112">
</p>

**Macked Updater** 是一款围绕 Macked.app 更新流程打造的原生 macOS 更新助手：扫描本机已安装 App，自动在 **Macked.app** 上查找对应条目，对比版本，并把匹配到的更新直接下载到本机。

它的目标是把重复操作自动化：App 列表留在本机，Macked.app 查询使用本机已登录会话，下载文件直接保存到 `~/Downloads`，无需为每个 App 反复打开浏览器页面。

<p align="center">
  <strong>扫描 App → 匹配 Macked.app → 对比版本 → 下载更新</strong>
</p>

| 亮色模式 | 暗色模式 |
| --- | --- |
| ![Macked Updater 亮色模式演示截图](assets/main-window-light.png) | ![Macked Updater 暗色模式演示截图](assets/main-window-dark.png) |

> 截图基于真实 App 界面生成，App 名称和 Bundle ID 均为虚拟演示数据，不包含本机 App 列表。

## Macked.app更新检查

- **自动检查 Macked.app 更新**：扫描本机 macOS App，登录后自动在 Macked.app 上搜索匹配条目。
- **版本对比一眼可见**：同时查看本机版本、官方最新版本和 Macked.app 最新版本。
- **App 内直接下载**：匹配到 Macked.app 条目后，可在 App 内解析下载链路并直接保存到 `~/Downloads`。
- **Macked Included 标志**：已匹配 Macked.app 的 App 会显示醒目的 `Macked Included` 标志。
- **下载队列**：显示已下载大小、总大小、实时速度、完成状态和失败原因。
- **官方来源并排展示**：官方页面、官方下载链接、更新说明与 Macked.app 信息放在同一个详情面板里。
- **本机优先**：扫描结果和缓存默认保存在本机。
- **原生 macOS 体验**：SwiftUI 仪表盘，侧边栏导航、卡片式详情、浅色/深色模式和 macOS 风格控件。

## Macked.app 更新流程

登录一次，Macked Updater 就可以接管围绕 Macked.app 的更新流程：

1. 扫描本机 `.app`；
2. 自动在 Macked.app 上搜索对应页面；
3. 对比本机版本、官方版本和 Macked.app 版本；
4. 为匹配项标记 `Macked Included`；
5. 点击 `Download Macked` 后在 App 内直接完成下载。

### 为 Macked.app 匹配优化的本机扫描

- 扫描 `/Applications`、`~/Applications`、`/System/Applications`。
- 读取 App 名称、Bundle ID、版本、Build、安装路径、修改时间、图标、Sparkle Feed、App Store receipt 线索。
- 自动去重，优先保留用户安装目录中的版本。

## Macked.app 优先，其他来源辅助

Macked Updater 的核心是 Macked.app 匹配和下载。其它来源主要用于补充版本对比和上下文信息：

- 登录后的 Macked.app 搜索、详情解析、版本信息和直接下载链路。
- 官方页面和更新说明，用于辅助对比。
- Sparkle appcast：从 App Bundle 中读取 `SUFeedURL`。
- Homebrew Cask 元数据：本机安装 Homebrew 时可用。
- Mac App Store receipt / lookup 元数据。
- 自托管 JSON Catalog，用于本地调试或私有元数据。
- 无法自动匹配时提供官网搜索入口。

## 系统要求

- macOS 12 或更新版本。
- Xcode 15+ 或 Swift 5.9+。
- 可选：如果需要 Homebrew Cask 检查，请安装 Homebrew。

## 从源码运行

克隆并运行：

```bash
git clone https://github.com/<your-name>/macked-updater.git
cd macked-updater
swift run macked-updater
```

用 Xcode 打开：

```bash
open Package.swift
```

然后运行 `macked-updater` executable target。

## 编译和打包

生成调试 App Bundle：

```bash
./script/build_and_run.sh --verify
```

生成 Release App 和 DMG：

```bash
./script/package_release.sh
```

打包脚本会同时生成 Apple Silicon、Intel 和 Universal 三套产物。每个 DMG 内都包含 `/Applications` 快捷方式，方便拖拽安装。

```text
dist/Macked Updater.app
dist/Macked Updater-universal.app
dist/Macked Updater-arm64.app
dist/Macked Updater-intel.app
dist/MackedUpdater_0.1.0_apple_silicon_aarch64.dmg
dist/MackedUpdater_0.1.0_intel_x64.dmg
dist/MackedUpdater_0.1.0_universal.dmg
```

本地包使用 ad-hoc 签名。如果要公开分发，请使用自己的 Apple Developer 身份签名并公证。

## 自托管 Catalog 部署

你可以通过 JSON Catalog 添加自己的更新来源。

最小结构：

```json
{
  "schemaVersion": 1,
  "sourceName": "Example Update Catalog",
  "generatedAt": "2026-07-05T00:00:00Z",
  "apps": [
    {
      "name": "Nebula Notes",
      "bundleIdentifier": "com.example.nebula-notes",
      "latestVersion": "2.7.0",
      "officialPageURL": "https://updates.example.com/apps/nebula-notes",
      "downloadURL": "https://updates.example.com/downloads/nebula-notes-2.7.0.dmg",
      "releaseNotesURL": "https://updates.example.com/apps/nebula-notes/releases/2.7.0"
    }
  ]
}
```

部署步骤：

1. 编辑 `deploy/authorized-catalog.json`。
2. 上传到你自己的 HTTPS 静态节点。
3. 打开 Macked Updater > Sources。
4. 粘贴 Catalog URL 并添加匹配条目。

本地调试可使用 `file://` Catalog URL。

## 项目结构

```text
App/            App 入口
Models/         App、更新、来源和设置模型
Services/       扫描、更新检查、匹配、下载和命令辅助
Persistence/    本地 JSON 缓存和用户来源存储
Views/          SwiftUI 页面和共享组件
Resources/      macOS App 图标资源
assets/         App 图标和 README 截图
script/         构建、运行、打包和清理脚本
deploy/         自托管 Catalog 示例
Tests/          XCTest 测试
```

## 开发检查

```bash
swift test
swift build -c release
./script/build_and_run.sh --verify
./script/package_release.sh
```

清理本地生成文件，并保留已打包 DMG：

```bash
./script/cleanup_after_run.sh
```

## 隐私说明

- 应用只扫描本机 `.app` 元数据。
- 不上传已安装 App 列表。
- Macked.app 登录状态保存在本机 WebKit website data store。
- 下载仅在用户点击下载按钮后执行。
- 下载文件保存到 `~/Downloads`。
- 应用不会安装、替换或修改已有 App。
