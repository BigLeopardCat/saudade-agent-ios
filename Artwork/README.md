# 泠月喵图像

形象归 BigLeopardCat，继承 `Resources/Licenses/ASSETS-LICENSE.md` 的美术许可（CC BY-NC-SA 4.0），不改变作者署名。代码许可与美术许可独立。

两个独立图像均由本次用户提供的头像参考，经 **built-in image_gen** 编辑/生成：

- `lingyue-island-head-master.png`：透明 RGBA，只保留猫耳、头发、脸部，去掉颈部、身体和外部白色背景。白色头发、耳毛和眼睛高光保留。运行时技术导出为 384 × 384，App 与灵动岛共用。
- `lingyue-app-icon-master.png`：单独生成的应用图标，保留同一头像特征，浅薰衣草色实底，无文字、无预制圆角。AppIcon 按 Apple 格式技术导出为 1024 × 1024、不含 Alpha。
- `upstream-avatar-original.png`：原 Agent 前端头像，保留上游署名，当前界面使用新的头部。
- `sticker-manifest.json`：博客 `cn_sora_blog` 分支 v2 内置贴纸来源、提示词和 SHA256。24 张 256px WebP 校验后嵌入 App；Widget 不打包贴纸。

提示词摘要（以用户参考图作为输入，不重新设计角色）：

1. “Extract only Lingyue's head including cat ears and all hair, preserve white/silver hair, large blue eyes and the original anime line art. Remove white exterior background to true transparent alpha. Remove neck and body; no new text, watermark, accessories, border or shadow. Keep white parts within the character opaque.”
2. “Create a separate square iOS AppIcon of the same Lingyue head, preserving her silver-white cat ears/hair and blue eyes. Head only, centered with safe padding, pale lavender solid opaque background, crisp anime line art, no text, no border and no baked rounded corners.”

母版为工具返回的 1254px 图像；CI 使用 `sips` 只做尺寸技术导出，并用 ImageIO 校验 Alpha、尺寸与全部贴纸可解码性。
