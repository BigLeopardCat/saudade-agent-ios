# 泠月喵 · 灵动岛伴侣

一个轻量原生 iOS 客户端：把泠月喵带到灵动岛，随手聊天、看看博客状态、审阅简单事务。不迁移完整博客。

最低 iOS 17；iPhone 15 Pro 支持灵动岛。默认本地演示，无需登录或模型密钥。演示指标、对话和事务均标记为模拟内容。

## 已实现的首版范围

- SwiftUI：陪伴概览、聊天、事务、博客登录。
- ActivityKit：锁屏和灵动岛的紧凑、最小、展开视图，刷新按钮与聊天深链。
- 直接复用泠月喵正式头像；不在 Widget 中运行 WebView 或 Live2D。
- 现有博客登录与 Keychain 凭据保存；客户端仅访问 Rust 宿主，不访问内部 Python Agent。
- SSE v2 流式正文、进度、重置、文本确认卡；原生确认和服务端撤销。
- 管理员诊断：CPU、内存、服务可用性；公开文章列表；暂停的 Agent 任务查看和取消。
- 服务错误与未知数据独立展示，不将读取失败当成零待办或服务健康。

## 没有 Mac 怎么编译

仓库自带 [GitHub Actions](.github/workflows/ios.yml)：标准 `macos-15` runner 上执行 Swift 协议测试、模拟器构建和 iPhone 真机构建，输出 `Lingyue-unsigned-device` artifact。

1. 打开 GitHub → Actions → iOS build，查看构建结果。
2. 成功后下载 artifact，解压得到 `Lingyue-unsigned.ipa`。
3. IPA 是 **未签名的真机包**，需要签名才能安装；它不是 TestFlight 包。
4. 无付费开发者账号的 Windows 安装路径见 [安装说明](docs/INSTALL.md)。

公开仓库的标准 GitHub-hosted runner 计算免费；artifact 存储仍有额度，因此仅保留 7 天。当前 workflow 不包含证书、Apple 账号或生产密钥。

如有 macOS，也可以运行：

```sh
brew install xcodegen
swift test
xcodegen generate
open Lingyue.xcodeproj
```

在 Xcode 为应用与扩展设置自己的签名 Team、唯一 Bundle ID，选择 iPhone 15 Pro 模拟器或真机。

## 接入真实博客

应用“连接”页填写博客的 HTTPS 根地址与现有账号密码。服务器诊断需要管理员权限；普通账号依然可以聊天和读取本人任务。密码只用于本次登录，登录 token 保存在本机 Keychain。

宿主必须支持 SSE v2，客户端发送 `X-Agent-Stream-Version: 2`。核对过的来源版本与接口见 [项目上下文](docs/PROJECT_CONTEXT.md) 和 [接口映射](docs/ARCHITECTURE.md)。源码版本不代表当前生产部署版本。

## 实时活动的边界

这是手动开始、可结束的值守会话，不是永久常驻桌宠。普通 Live Activity 最长 8 小时；自由聊天输入在应用内。此版使用前台更新与灵动岛按键刷新，尚未接入 APNs，应用挂起后不会主动持续监控服务器。五分钟后旧状态会标记为待更新。

聊天历史保存在博客，原生界面只维护当前运行内的对话；可从事务页恢复暂停任务的历史和当前确认卡。断流不自动重连，不自动重发确认请求；停止接收不代表远端业务停止。

首版仅在原生审阅简单文本卡。图片、封面和批量卡保留在博客中审阅；浏览器导航、特效和编辑器命令不会在原生端执行。更完整的会话列表、暂停任务接续、后台推送、通知及正式 App Icon 尚待完善。

## 许可与验证

代码按 [MIT](LICENSE) 发布。角色美术来自 [BigLeopardCat/saudade-blog-agent](https://github.com/BigLeopardCat/saudade-blog-agent)，按 CC BY-NC-SA 4.0 使用；原始头像未修改，许可与署名保存在 `Resources/Licenses`，应用“连接”页也可查看来源。

Swift 测试覆盖分帧、UTF-8、协议终态、未知事件、大小边界、确认卡和过期计算。完整编译结果以对应提交的 GitHub Actions 为准；iPhone 侧载签名与真机灵动岛交互需要单独验证。
