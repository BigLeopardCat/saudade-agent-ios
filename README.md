# 泠月喵 · 灵动岛伴侣

一个轻量原生 iOS 客户端：把泠月喵带到灵动岛，随手聊天、看看博客状态、审阅简单事务。不迁移完整博客。

最低 iOS 17；iPhone 15 Pro 支持灵动岛。默认本地演示，无需登录或模型密钥。演示指标、对话和事务均标记为模拟内容。

## MVP / Alpha 范围

- SwiftUI：陪伴概览、聊天、事务、博客登录。
- ActivityKit：锁屏和灵动岛的紧凑、最小、展开视图，刷新按钮与聊天深链。
- 独立的泠月喵头部 AppIcon 和透明灵动岛头像；不在 Widget 中运行 WebView 或 Live2D。
- 现有博客登录与 Keychain 凭据保存；客户端仅访问 Rust 宿主，不访问内部 Python Agent。
- SSE v2 流式正文、进度、重置、文本确认卡；原生确认和服务端撤销。
- 原生 GFM Markdown、24 张离线贴纸（`:比心:` / `![比心](:比心:)` / `:全部表情:`），代码里的别名保持字面内容。
- 博客风格的日夜登录页；已登录显示本人头像、昵称，切换账号时才显示表单。
- 多会话列表、新建/切换、重命名、置顶和删除；按游标读取更早历史，昵称位于气泡外，消息按五分钟间隔显示时间。
- 管理员诊断：CPU、内存、服务可用性；公开文章；评论、留言审核和额度申请等人工待办。
- 人工待办与暂停的 Agent 执行分别展示；读取待办不会自动批准或驳回。
- 应用、灵动岛展开区和锁屏卡片均可结束陪伴；应用入口同时停止当前接收。
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
bash scripts/prepare_assets.sh
xcodegen generate
open Lingyue.xcodeproj
```

在 Xcode 为应用与扩展设置自己的签名 Team、唯一 Bundle ID，选择 iPhone 15 Pro 模拟器或真机。

## 接入真实博客

应用“我的博客”页点“登录我的博客”，填写自己部署的兼容 Saudade Blog 的 HTTPS 根地址与账号密码。域名和账号不绑定本项目作者。诊断与审核需要管理员权限；普通账号可以聊天和读取本人任务。密码只用于本次登录，登录 token 保存在本机 Keychain。

宿主必须支持 SSE v2，客户端发送 `X-Agent-Stream-Version: 2`。核对过的来源版本与接口见 [项目上下文](docs/PROJECT_CONTEXT.md) 和 [接口映射](docs/ARCHITECTURE.md)。源码版本不代表当前生产部署版本。

## 实时活动的边界

这是手动开始、可结束的值守会话，不是永久常驻桌宠。普通 Live Activity 最长 8 小时；自由聊天输入在应用内。此版使用前台更新与灵动岛按键刷新，尚未接入 APNs，应用挂起后不会主动持续监控服务器。五分钟后旧状态会标记为待更新。

聊天历史保存在博客，可从会话列表重新打开并读取更早历史，也可从事务页恢复暂停任务和当前确认卡。未发送草稿只留在本次运行内。断流不自动重连，不自动重发确认请求；停止接收不代表远端业务停止。

原生端审阅简单文本卡。图片、封面和批量卡保留在博客中审阅；浏览器导航、特效和编辑器命令不会在原生端执行。后台推送和主动提醒尚未实现。当前定位为 MVP / Alpha，建议发布标签 `v0.2.0-alpha.1`，不等同于经过真机长期验证的稳定版。

长回复合并刷新（通常 100ms，超过 32KiB 后 500ms），后台不逐字刷新 Markdown。单轮正文 128KiB，事件缓冲 256 帧，当前历史窗口 200 条 / 8MiB，日志 200 条，图片缓存有数量及字节上限。头像只匿名读取同源 HTTPS，无 Cookie、Authorization 或重定向；Markdown 不联网加载外部图片，不执行 HTML 或脚本。详见 [诊断与版本核对](docs/SSE_INVESTIGATION.md)。

## 许可与验证

代码按 [MIT](LICENSE) 发布。角色美术来自 [BigLeopardCat/saudade-blog-agent](https://github.com/BigLeopardCat/saudade-blog-agent)，按 CC BY-NC-SA 4.0 使用；许可与署名保存在 `Resources/Licenses`。新增图像的生成方式、提示词摘要与贴纸来源见 [Artwork](Artwork/README.md)。

Swift 测试覆盖协议、取消传播、错误保留、确认批准契约、人工待办、用户身份与贴纸边界。CI 对实际 IPA 核对应用/扩展版本、源提交、AppIcon 与 24 张贴纸，生成 `build-manifest.json`。完整编译结果以对应提交的 GitHub Actions 为准；iPhone 侧载签名、真实 SSE、真机灵动岛交互和电量需要单独验证。

“500 条”限制的核实、会话分页与时间规则见 [多会话说明](docs/CONVERSATIONS.md)。
