# 自动化规则

## 每次代码改动后必须编译 .app

任何一次代码修改（App 层或 NBAKit 层）结束后，立即执行：

```bash
cd /Users/mora/Projects/NBA && ./Scripts/build.sh
```

脚本会自动 `xcodegen generate`、编译 **macOS 版**，把带 `.app` 后缀的产物放到
`build/apps/`，并输出成功/失败汇总。出现编译错误时必须修到全绿再回复。
默认 Release 配置 —— 用户只需要这个双击即用的 macOS 包。

可选参数：

- `--debug`    改用 Debug 配置
- `--with-ios` 额外产出 iOS 模拟器包（默认不出）

## 改动数据层后额外跑接口测试

改动 `Packages/NBAKit/` 下的接口、模型或参数后：

```bash
cd /Users/mora/Projects/NBA/Packages/NBAKit && swift test
```

32 个用例逐个调用真实虎扑接口并断言关键字段，有失败必须修复。
这层测试抓出过多次模型与线上响应不一致的问题（字段类型、嵌套层级、赛季语义、榜单分页）。

## 版本号规则（x.x.x 三段）

| 改动类型 | 版本位 | 示例 |
|---|---|---|
| 较大改动、功能重写、平台架构调整 | 中间位 x.**1**.0 | 1.1.0 |
| 小修复、小功能升级 | 最后位 x.x.**1** | 1.1.1 |
| 最大版本号 x.**0**.0 | **仅用户明确要求时**才动 | 2.0.0 |

`MARKETING_VERSION` 在 project.yml 里维护。本轮为较大改动，已升到 **1.3.0**（应用图标、百科历史总数据榜、独立新闻栏目：30 秒轮询实时流 + 正文内置阅读、移动端原生启动图）。

## 启动图只做移动端，且必须用原生机制

macOS 没有系统级启动画面，**不做**遮罩，也不要在应用内自建（`RootView` 上不要再挂 overlay 型 splash）。
移动端用系统原生的 **launch storyboard**：`Resources/LaunchScreen.storyboard` + Info.plist 键
`UILaunchStoryboardName: LaunchScreen`。

为什么不是 `UILaunchScreen`：那个字典的 `UIImageName` 只能按图片**自然尺寸**居中绘制，
iPhone / iPad 一样大，做不到自适应；storyboard 才能用 Auto Layout 按屏幕缩放。

storyboard 里的约束（改尺寸比例就动这里）：

| 约束 | 值 | 说明 |
|---|---|---|
| 高 = 父视图高 × | 0.42 | 优先级 999，可被宽度上限压低 |
| 宽 ≤ 父视图宽 × | 0.35 | 必须满足，避免窄长屏上标志过大 |
| 宽高比 | 239:574 | 与素材一致，写死为 multiplier |
| 位置 | 居中 | 相对父视图中心 |

实测（模拟器截启动帧）：iPhone 17 Pro 402×874pt → 标志版心 ≈139×336pt（宽上限生效，占屏高 36.2%）；
iPad Pro 11 834×1210pt → ≈210×505pt（屏高 42% 生效，占屏高 39.3%）。同一份包、不同屏幕不同尺寸。

素材 `Assets.xcassets/Splash.imageset` 出 1x/2x/3x，自然尺寸 239×574pt（1x 就是 239×574 px）。
自适应后自然尺寸只决定**清晰度**、不再决定显示大小，所以要留足：iPad 会把标志画到 505pt，2x 屏需要 ≥1010px。

编译归属：storyboard 必须只进 iOS。单一多平台 target 下 xcodegen 2.46 的 source 级
`platformFilter` 不生效（已验证：写进 yml 后 pbxproj 里没有该属性），改用按 SDK 的条件构建设置：

```yaml
"EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]": "LaunchScreen.storyboard"
```

漏了这行 macOS 会直接编译失败：`iOS storyboards do not support target device type "mac"`。

## 产物位置

**`build/apps/NBA.app`** —— macOS 应用包，双击即可运行（唯一需要的产物）。

```bash
open build/apps/NBA.app        # 等价于双击
```

iOS/iPadOS 代码仍持续编译验证（`--with-ios`），但默认不产出移动端包。

移动端包（`--with-ios` 产出）：**`build/apps/NBA-iOS-Simulator.app`** —— 模拟器专用（iPhone 17 Pro 等）。

```bash
xcrun simctl install booted build/apps/NBA-iOS-Simulator.app
xcrun simctl launch booted com.littlecodesauce.nba
```

装到真机需要用 Xcode 打开工程并选签名团队（命令行只有 ad-hoc 签名）。

注意：产物名必须带 `.app` 后缀，否则 Finder 当普通文件夹处理，双击打不开。

## 交付前自检清单

- [ ] `./Scripts/build.sh` 全绿
- [ ] 改动数据层时 `swift test` 全绿
- [ ] 改动 UI 时实机/模拟器截图确认渲染正常
- [ ] 临时调试代码（截图路由、日志、环境变量开关）已清除
- [ ] 新增文件已包含在 `project.yml` 覆盖的目录下（否则需 `xcodegen generate`）