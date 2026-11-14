# Windows + iPhone 15 Pro 安装

不需要购买 Mac。编译由 GitHub Actions 的标准 macOS runner 执行；公开仓库的该计算免费。参见 [GitHub 官方说明](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)。

## 获取 IPA

在 GitHub 仓库的 Actions → 最新成功的 **iOS build** → Artifacts 下载 **Lingyue-unsigned-device**，解压出 `Lingyue-unsigned.ipa`。需登录 GitHub 才能下载普通 Actions artifact。

这个文件包含主应用和 `LingyueIsland.appex`，是真机 ARM64 构建，不是模拟器包。它尚未签名，不能直接点开安装，也不是 TestFlight 发布。

## 免费侧载路径

可以使用支持 Windows 和免费 Apple 账号的 [Sideloadly 官方版本](https://sideloadly.io/)。也可以评估 [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore)。先前版本已观察到 Sideloadly 安装完成；每个更新包的签名、扩展和真机交互仍要核对。

1. 按工具当前官方安装说明配置 Windows 端及 Apple 设备驱动；首次用数据线连接 iPhone 并选择信任电脑。
2. 将 `Lingyue-unsigned.ipa` 交给签名工具，Apple 账号与验证码仅在你自己的本地签名工具中输入，不上传至仓库或 CI。
3. **保留 App Extensions / PlugIns**。不要移除 `LingyueIsland.appex`，它承载锁屏与灵动岛界面。官方工具支持移除扩展，因此需检查此项。
4. 如工具自动变更 Bundle ID，应同时正确重签主应用与扩展，并保持扩展 ID 在主应用 ID 的命名空间内。
5. 按 iPhone 系统提示信任开发者并启用 Developer Mode（如要求）；完成后打开泠月喵，先试演示模式，再点“开始灵动岛陪伴”。
6. 长按灵动岛测试“看看状态”；点击“和我聊聊”应回到应用对话页。锁屏也应显示实时活动。

更新时使用上次相同的签名账号与 Bundle ID 配置，有助于覆盖安装并保留登录。对照下载包的 `build-manifest.json` 与 App“我的博客 → 构建版本”；重新签名会改变 IPA 哈希，因此手机上用版本、build 和源码 SHA 核对。新版应用和灵动岛展开区有“结束陪伴”，按下后实时活动立即移除；划掉 App 不保证自动移除系统保留的卡片。

免费个人账号的 provisioning profile 通常 7 天过期，需要续签；每台设备最多安装 3 个此类 App，App ID 也有额度。主应用与扩展各占用一个 App ID；不要把 App ID 额度与安装 App 数量混为一谈。见 [Apple 账号限制](https://developer.apple.com/help/account/basics/about-your-developer-account) 与 [AltStore 扩展说明](https://faq.altstore.io/altstore-classic/app-ids)。

## 首次验收

- CI 对所下载提交显示成功，IPA 内含 `Payload/Lingyue.app/PlugIns/LingyueIsland.appex`。
- 演示模式聊天、诊断和文本卡都可打开；确认演示操作不会连接真实博客。
- 实时活动开启、结束、状态刷新及聊天深链工作正常。
- 五分钟未更新时显示待更新，而不是继续宣称最新状态。
- 登录自己的博客后，管理员可看到真实诊断；普通账号的权限拒绝正常显示。
- 首次仅做只读查询；真实写入需要明确审阅当前服务端确认卡。

免费签名不保证支持所有 Apple 能力。本版未使用 App Group、APNs 等额外能力，以降低首次侧载条件；扩展签名与实时活动仍需在你的 iPhone 上验证。遇到错误时提供错误文案即可，不需要提供密码、token 或验证码。
