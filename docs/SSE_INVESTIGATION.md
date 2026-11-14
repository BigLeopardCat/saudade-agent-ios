# SSE / 确认卡调查与复现

## 版本基线（2026-11-14）

- 修复前本地与 GitHub main 均为 `a5d7e155ab60d8868bae0c4f8594bb8a8cd3e142`。
- 之前的 CI 为 run `43557110494`，保存的未签名 IPA SHA256 为 `eb4017284ae277e2dbabf905fdb634d0b359df690ef1e69b20d3c0b57220c5ba`，包含 `LingyueIsland.appex`。
- 旧 IPA 实际 plist 为 **1.0 (1)**，项目 YAML 的 0.1.0 未正确传入生成的 plist，也未嵌入源码 SHA。曾观察到 Sideloadly 安装完成，但仅凭此不能证明手机现在仍是同一二进制；侧载重新签名也会改变文件哈希。不能声称已精准证明手机已安装版本与 main 完全相同。
- 本 PR 的应用/扩展均显式使用 0.2.0、CI run number 与真实 checkout SHA。CI 校验已打包 IPA，附带 build-manifest.json；安装后在“我的博客 → 构建版本”对照。PR 未合并时 main 仍是旧版，这是预期状态。
- 公开后端对照：Agent origin/main `9114d8b531d058db6854377493dda5f37158f989`；Blog origin/cn_sora_blog `0232e1eed7ca2724c108dde76d7d96aee0c8fda5`。这些源码版本不能代表生产服务器部署版本。

## 已由代码与本地隔离测试证明的缺陷

1. 旧 App 批准确认卡时重新生成 turn_id；Rust `src/routes/chat/context.rs` 要求继续原轮次，传入非空且不同 ID 会在转发前返回 409 `turn_replaced`。修复为只传 cid、空 message 与原始 confirm_token，由宿主恢复权威原轮次。测试断言不生成新 turn_id / task_id / resume_task / confirm_pick。
2. 旧 HTTP 层将全部 409 显示为“状态变化或已消费”。这丢失了轮次替换、已使用授权、历史同步、协议版本等区别。现在只识别已知安全错误分类；未知 409 明确未知，不回显不可信响应原文。
3. 旧 catch 会删除已收到确认卡；后续进度帧解析失败也会使卡消失。现在保留卡及完整审阅内容，禁用批准，提供只读重新核对；不会自动重放旧授权。旧批准完成不会清掉期间收到的另一张新卡。
4. 旧解析器拒绝全部未知事件，也不支持结构化 progress、pending、receipts。现在支持 SSE v2 的合法帧、安全扩展无权限忽略，已知畸形帧仍报错。注意宿主当前会内部消费 pending/receipts，因此不能仅凭这个差异推断它就是该次生产断流原因。
5. 旧 transport 收到 done 后还等待 EOF；新实现把 done 当本轮终态，关闭自己拥有的连接，正常结束不标成用户取消。

## 取消路径

| 触发 | 行为 / 可观察证据 |
| --- | --- |
| “停止接收”或“结束陪伴” | user_stop；取消内部 URLSession Task，保留未确认结果，不代表远端业务回滚 |
| 父 Task / 消费者取消 | parent_task / consumer_cancelled；下传到网络；最早取消来源保留 |
| 消费者提前退出 / 句柄释放 | consumer_ended / owner_released；显式清理本轮网络，不牵连概览请求 |
| 已知帧解析失败 | protocol_or_application_error；保留 NSError domain/code 与最后畸形事件名；关闭连接，保留已收到卡 |
| 网络错误 | network_error；保留原始 NSError domain/code，不改写成 user_stop |
| 页面离开 / 前后台切换 | 仅记录可见性、scene，不主动取消；AppStore 由应用根持有 |
| done | completed、receivedDone=true，不主动给正常结束写 cancel source |
| EOF 没有 done / 缓冲溢出 / 服务端 error | 失败；不补造 done，不吞掉错误，不自动重发 |

超时仍是 request 60s / resource 300s。请求超时随新数据重置，资源超时为总时限。iOS 挂起、进程终止、网络变化和代理超时仍可能关闭传输，不能凭服务端 client_disconnect 区分原因。

## 日志与服务端配合字段

在“我的博客”导出本机 JSONL。每轮发送 `X-Request-ID`，记录构建 SHA、请求 ID、允许的 server X-Request-ID、会话/任务 ID、场景与可见性、耗时、状态、取消来源、NSError domain/code、最后事件、事件数、忽略扩展数、是否收到 done。最多 200 行，串行低优先级写盘。无 URL、Authorization、Cookie、token、确认凭据、正文、错误 userInfo 或 localizedDescription。

若复现，请提供同一请求的以下服务端字段（不要发完整载荷或授权）：

- Rust、Python Agent、网关的实际部署 SHA，以及 iOS 构建 SHA / build number。
- X-Request-ID 与宿主 trace_id 的对应；conversation_id、task_id、原始/传入 turn_id（仅编号）。
- HTTP 状态和安全的错误分类；若 409，确认是 turn_replaced、confirm_already_used 还是其他。
- Rust 对客户端输出的事件名称、顺序、时间戳、字节数，最后是否输出并 flush done；Python→Rust 同样的元数据。不要提供 data 原文。
- 断开首先发生在哪一侧、原始异常类型 / errno、取消来源；代理 read/send/idle timeout、总耗时和最后一字节时间。
- 确认执行账只读状态：未提交 / 已接收 / 执行中 / 已成功 / 已失败 / 未知，以及时间与脱敏操作 ID。不清账、不重置、不重发批准来试探。

## 验证范围与剩余不确定性

URLProtocol 隔离测试覆盖正常 done 不等 EOF、手动停止与消费者取消、网络 -1005、确认后畸形 progress、服务端 error、缺 done、HTTP 409、无自动重试、场景观察、句柄释放和缓冲上限。另测人工待办统计/分页 ID/未知数量、头像同源约束、贴纸与代码边界。CI 同时编译主应用和扩展，并校验实际 IPA。

这些证明客户端缺陷与修复路径，不证明用户那次真实 client_disconnect 的唯一原因。需要修复包真机复现及两端关联日志才能定案。真机后台挂起、最低电量、侧载保留扩展及新界面视觉效果还需实际验证。

Apple 参考：[URLSession 超时](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforrequest)、[Live Activity 交互与应用进程](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)、[立即移除已结束实时活动](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/immediate)。系统保留实时活动不等于 App 永久运行；此应用没有后台轮询、音频保活或后台模型循环。
