# AGIMUS

[![CI](https://github.com/TranswarpDrive/AGIMUS/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/TranswarpDrive/AGIMUS/actions/workflows/ios-ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

中文文档（默认）：`README.md`  
English version: [README_EN.md](README_EN.md)

AGIMUS 是一个原生 iOS 聊天客户端，面向 OpenAI 兼容协议的大语言模型服务商。

它适合希望在本地设备上管理聊天与密钥的用户：可自由切换模型提供商、支持流式输出、可选联网搜索工具，并把 API Key 保存在设备而不是仓库里。

## 纯 AI 项目声明

本项目由以下 AI 工具协作完成：

- Claude Code（Claude Sonnet 4.6）
- Codex（GPT-5.4 与 GPT-5.4-Codex）

仓库内代码不包含人类手写代码成分，是一个纯粹的 AI vibe coding 项目。

## 功能亮点

- 多提供商配置：每个提供商可独立设置 Base URL、模型列表、API Key、推理参数
- 支持流式与非流式回复
- 对支持的模型可展示“思考/推理”内容
- 支持多种可选搜索服务接入
- 本地会话历史存储
- API Key 存储在 iOS Keychain
- 自动生成会话标题
- 支持浅色、深色与跟随系统外观
- 支持应用内中英文界面切换

## 技术栈

- UIKit
- Swift 5
- Xcode 原生工程（应用本体不依赖包管理器）
- iOS 12.0 最低部署版本

## 项目结构

- `AGIMUS/AGIMUS/Models`：会话、消息、提供商、搜索、Token 用量等数据模型
- `AGIMUS/AGIMUS/Services`：网络请求、搜索接入、持久化、设置、Keychain 存储
- `AGIMUS/AGIMUS/ViewControllers`：会话列表、聊天页、设置页、提供商管理页
- `AGIMUS/AGIMUS/Views`：聊天 UI 复用组件
- `AGIMUS/AGIMUS/Utils`：主题、Markdown、通用工具
- `.github`：CI、Issue 模板、PR 模板、发布说明配置

## 快速开始

1. 使用 Xcode 打开 `AGIMUS/AGIMUS.xcodeproj`
2. 选择共享 Scheme：`AGIMUS`
3. 在模拟器或真机上构建运行
4. 进入应用设置页
5. 添加至少一个 OpenAI 兼容提供商
6. 填写 Base URL、API Key、模型
7. 如需联网检索，可选配置搜索服务

## 配置说明

- AGIMUS 主要面向 OpenAI 兼容接口（如 `/chat/completions` 与 `/models`）
- 仓库不会保存 API Key，密钥仅在运行时保存在本地 iOS Keychain
- 搜索服务是可选功能，不配置也可正常聊天
- 聊天记录保存在本地设备

## 开源协作流程

- `main` 为稳定分支
- `develop` 为日常集成分支
- 新功能建议从 feature 分支开发，并向 `develop` 发起 PR
- 版本标签遵循 `vX.Y.Z`

更多协作细节见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 安全与隐私

仓库不应包含任何生产环境密钥。

开源前请确认未提交以下内容：

- 个人 `xcuserdata` 文件
- 本地助手/工具配置
- 包含隐私信息的截图
- 你不希望公开的私有服务地址或密钥

若发现安全问题，请参考 [SECURITY.md](SECURITY.md)。

## 品牌说明

当前应用名称、图标或相关素材可能涉及第三方知识产权。若你要公开分发应用（不仅是源代码），请先确认你拥有相关授权。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
