# 多会话与聊天时间

2026-11-14 核对：Blog `cn_sora_blog` = `0232e1eed7ca2724c108dde76d7d96aee0c8fda5`；Agent `main` = `f77856381d6694b620b9caa9c35c8a5c9a3f11ed`。线上部署可能不同。

## 500 的含义

- **500 是普通账号默认累计聊天额度**，按用户累计，由 `CHAT_QUOTA_LIMIT` 配置；管理员不限额，确认批准不额外扣一轮，新建会话不会重置额度。[quota.rs](https://github.com/BigLeopardCat/Saudade-Blog/blob/0232e1eed7ca2724c108dde76d7d96aee0c8fda5/src/quota.rs#L16)
- 历史 API **一页 50 条**，用 before_id 向前翻页，按数据库 ID 升序返回。没有找到单个会话到 500 条就封顶或清理旧记录的规则。[chat.rs](https://github.com/BigLeopardCat/Saudade-Blog/blob/0232e1eed7ca2724c108dde76d7d96aee0c8fda5/src/routes/chat.rs#L258)
- 会话列表最多 **200 个**，按置顶、活动时间、ID 排序。[conversation.rs](https://github.com/BigLeopardCat/Saudade-Blog/blob/0232e1eed7ca2724c108dde76d7d96aee0c8fda5/src/routes/conversation.rs)
- Agent 网页本地镜像 **50 条**，存储失败时降为 30 条，完整历史从数据库读取。[chat-engine.js](https://github.com/BigLeopardCat/saudade-blog-agent/blob/f77856381d6694b620b9caa9c35c8a5c9a3f11ed/frontend/public/live2d-widgets/chat-engine.js#L642)
- 宿主 bootstrap 最近历史 **20 条**，Agent API history schema 上限 **60 条**；模型记忆还受 checkpoint、上下文预算和摘要管理，不等于数据库历史上限。[chat_context.rs](https://github.com/BigLeopardCat/Saudade-Blog/blob/0232e1eed7ca2724c108dde76d7d96aee0c8fda5/src/routes/chat_context.rs#L11)、[schemas.py](https://github.com/BigLeopardCat/saudade-blog-agent/blob/f77856381d6694b620b9caa9c35c8a5c9a3f11ed/agent/api/schemas.py#L22)

## iOS 会话

聊天页左上角打开会话列表，支持新建、切换、标题搜索、重命名、置顶和删除。新会话首次发送时才创建；初次打开聊天读取最近活跃会话。标题搜索只搜索当前加载的标题，不宣称支持全文命中定位。

同时只接收一个会话的回复；接收中可打开列表，但需结束或主动停止后再切换。切换本身不取消流、不发聊天、不自动批准。历史响应校验 conversation_id、排序和 before_id；迟到的旧账号/域名列表不能覆盖新来源。恢复会话只读核对当前确认卡，失败时保留只读卡，不盲目重放授权。

草稿按会话分开，只留内存（最多 20 份）；确认投影只留内存（最多 8 份）。切换账号/域名全部清空。演示最多保留 20 个会话，真实会话在博客数据库保存。删除需要用户再次确认，收到 success:true 才更新界面；整理、删除、聊天和批准不自动重试。

历史一页 50 条，当前渲染窗口最多 200 条 / 8 MiB 文本；超过时释放窗口较新部分，仍可继续向更早翻页，不在 500 条处截断。旧历史模式收起输入和当前批准卡，回到最新后继续聊天。历史前插尽量保留阅读锚点，不强制跳到底部。

单条历史正文最多显示 128 KiB，与流式正文上限一致；过长时明确标记节选并提供博客入口。确认卡完整审阅内容不走正文节选。历史下载最多 12 MiB（宿主可能带 8 MiB 图片），类型化解码只读取文字、ID、时间和图片数量，不保留 base64 图片；其他普通 API 仍限制 2 MiB。

## 昵称与时间

昵称在气泡外上方，头像在一侧。用户昵称来自已认证 profile；泠月喵显示固定昵称。时间独立居中，沿用 [Agent 规则](https://github.com/BigLeopardCat/saudade-blog-agent/blob/f77856381d6694b620b9caa9c35c8a5c9a3f11ed/frontend/public/live2d-widgets/chat-core.js#L112)：

- 首条有效时间、相邻间隔严格超过五分钟时显示。
- 今天 HH:mm；昨天“昨天 HH:mm”；本年 M月d日 HH:mm；跨年加年份。
- 按设备时区和日历日界处理午夜及夏令时，不用粗略的 24 小时差。
- 服务端时间为 Unix 毫秒；0、缺失、非有限值不显示，不补造当前时间或 1970。
- 实时消息创建时记录一次本地时间，不随字块刷新；done 后只读同步数据库历史。同步失败保留当前回复并提示，不把已完成 SSE 改成失败。

没有为时间显示和会话列表增加后台定时器或轮询。
