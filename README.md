# NBA — 纯 Swift 多平台 NBA 数据应用

iOS / iPadOS / macOS 三端同码（SwiftUI + Swift 6），一个 Xcode target 同时产出三个平台，
使用系统原生控件与 iOS 26 / macOS 26 的 Liquid Glass 设计语言。

数据源：`API-Collect/hupu-api` 整理的虎扑 NBA 接口（免签名、免 key）。

## 运行

```bash
brew install xcodegen          # 只需一次
cd NBA
xcodegen generate              # 由 project.yml 生成 NBA.xcodeproj
open NBA.xcodeproj
```

或在命令行：

```bash
# iOS 模拟器 / iPad 模拟器 / Mac
xcodebuild -scheme NBA -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme NBA -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' build
xcodebuild -scheme NBA -destination 'platform=macOS' build
```

签名默认为 ad-hoc（模拟器 / 本机可直接跑）；要真机或上架，在 Xcode 的
Signing & Capabilities 里选自己的 Team 即可。

### 一键编译出 .app

```bash
./Scripts/build.sh              # 默认 Release，产出 build/apps/NBA.app
./Scripts/build.sh --debug      # Debug 配置
./Scripts/build.sh --with-ios   # 额外产出 iOS 模拟器包（验证移动端用）
```

**`build/apps/NBA.app`** —— macOS 应用包，双击即可运行（产物名带 `.app` 后缀，
Finder 才会识别为应用包）。iOS / iPadOS 代码持续参与编译验证。

增量编译，DerivedData 保留在 `build/DerivedData`；重复编译只重编改动部分。

改动数据层后建议再跑一次接口测试：

```bash
cd Packages/NBAKit && swift test
```

接口对齐验证（需要网络，32 个用例逐个打真实接口并断言关键字段）：

```bash
cd Packages/NBAKit && swift test
```

## 目录结构

```
NBA/
├── project.yml                    XcodeGen 工程定义（唯一需要手写的工程配置）
├── Scripts/build.sh               一键编译出 .app（iOS 模拟器版 + macOS 版）
├── AGENTS.md                      协作规则：改动后必编译、数据层改动必跑测试
├── NBA.xcodeproj                  xcodegen generate 产物，可安全删除重建
├── Assets.xcassets                AccentColor / AppIcon 占位
├── Sources/
│   ├── App/NBAApp.swift           @main + 根标签页（窄屏底栏 / 宽屏顶栏，自动切换）
│   ├── Components/                跨页面复用的原生控件
│   │   ├── Theme.swift            颜色、圆角、排版、卡片容器
│   │   ├── RemoteImage.swift      远程队徽/球员图（内存 + 磁盘两级缓存）
│   │   ├── CommonViews.swift      指标网格、信息行、指标选择条、加载/空态
│   │   ├── StatsTable.swift       数据表格与排名榜
│   │   └── Loader.swift           请求状态机（Loader / PollingLoader）
│   └── Features/                  五个 Tab，各自 View + Model
│       ├── Scores/                比分：赛程日期条、比赛行
│       ├── Standings/             战绩：东西部排名、球队数据榜
│       ├── Teams/                 球队：30 队列表、球队详情
│       ├── Players/               球员：数据榜、搜索、球员详情
│       └── Encyclopedia/          百科：历史选秀、历届荣誉
└── Packages/NBAKit/               数据层（可独立复用/单测）
    ├── Sources/NBAKit/
    │   ├── Network/               配置、接口枚举、客户端、缓存
    │   ├── Models/                 全部数据模型
    │   ├── Registry/               30 队静态表、赛季推断
    │   └── Resources/teams.json    30 队 id / 名称 / 队徽
    └── Tests/NBAKitTests/          32 个真实接口解码测试
```

## 功能

| 页面 | 内容 |
|---|---|
| 比分 | 日期条筛选当日赛程（默认今天）、30s 自动刷新、直播中标记；比赛详情含比分头图（球队主题色渐变）、两队技术统计条形对比、球员 boxscore（趣味标签/首发/在场/正负值）、逐回合文字直播（12s 轮询） |
| 战绩 | 东西部排名（战绩/胜率/主场/客场/连胜，季后赛线标金）、常规赛与季后赛切换；球队数据榜 27 项指标 × 3 个赛季 |
| 球队 | 30 队列表（按当前战绩排序，队徽取自 standings）；球队详情含简介、赛季数据（含联盟排名）、阵容（伤病标记、薪资）、球队荣誉、退役球衣、队史纪录保持者 |
| 球员 | 32 项数据榜（一次请求全取，选中指标时自动补全完整 30 强）、中英文搜索（防抖 280ms）；球员详情含资料/合同/薪资、赛季数据、生涯累计与最高、逐赛季、逐场、荣誉 |
| 百科 | 1970–2026 共 57 届选秀名单（按轮次分组，附生涯数据）、20 类历届荣誉得主 |

## 实现要点

**多平台单 target。** `SDKROOT=auto` + `SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx"`，
一套源码同时编译三个平台。平台差异全部收敛在少量 `#if os(...)` 与修饰符里
（`Theme` 的颜色、`inlineNavigationTitle()`、`pageBackground()`、`RemoteImage` 的 `UIImage`/`NSImage`），
其余代码 100% 共用。

**液态玻璃。** 根标签页用系统 `TabView`：iPhone 走底部 `tabItem`、iPad/Mac 走 `Tab`（顶部玻璃标签栏），
两种形态都由系统渲染 Liquid Glass，无需自己实现毛玻璃。卡片使用系统材质颜色 + 极淡描边，
与系统 App 的视觉一致，并随系统深浅色自动切换。

**数据层。** 虎扑接口有四种响应信封（标准 `result`/`success`、`salary` 的 `status`、`teamBasicInfo`/`teamSeasonStats`
的平铺、`searchPlayer` 的顶层数组），`HupuClient.decode` 统一兼容；字段全部可空，虎扑改字段不会崩。
整条「请求 + 解码」跑在 `Task.detached`，不占主线程。指数退避重试 3 次，
按数据类型设置 TTL（比分 20s、直播 8s、战绩 60s、榜单 300s、阵容 600s、百科 6h）。

**性能。** 32 项球员榜单（163KB）一次取回后按「赛季 + 指标」缓存在内存，切换指标零请求；
球员图/队徽走内存 + 磁盘两级缓存，列表滚动复用同一 actor。
比赛详情一次并发 4 个请求（比分、对比统计、主客 boxscore）。

**正确性由测试保证。** `swift test` 的 32 个用例逐个调用真实接口并断言关键字段，
模型与线上响应不同步会立刻失败。开发中它已经抓到过 4 个真实问题：
`shirtRetiredColors` 是字典不是数组、`playerCareerStats` 的阶段 map 与 `playerSeasonStats` 同名不同层、
`standings` 返回未开赛赛季（30 队全 0-0）、`playerSeasonRank` 的进阶指标只有前 5 名。

## 已知限制

- **数据本身的新鲜度取决于数据源。** 例如 `playerInfo` 返回的年龄/身高可能是旧值（库里返回 38 岁），
  App 不做二次推算，避免引入自己的误差。
- **赛季切换期的战绩。** 新赛季开赛前虎扑会返回新赛季但所有球队 0-0，
  此时 `SeasonProvider` 采信按日期推断的赛季，并在标题标注「尚未开赛」。
- **`pace`（回合数）指标**没有完整榜单，已从球队数据榜菜单中过滤。
- **文字直播只展示最近 40 条**，接口本身返回全场数据。
- 队徽/球员图有部分 `http://` 明文地址，客户端加载时统一升级为 `https://`；
  Info.plist 保留了 ATS 放行项。