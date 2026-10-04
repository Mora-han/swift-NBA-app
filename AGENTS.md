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

`MARKETING_VERSION` 在 project.yml 里维护。本轮为较大改动，已升到 **1.1.0**。

## 产物位置

**`build/apps/NBA.app`** —— macOS 应用包，双击即可运行（唯一需要的产物）。

```bash
open build/apps/NBA.app        # 等价于双击
```

iOS/iPadOS 代码仍持续编译验证（`--with-ios`），但默认不产出移动端包。

注意：产物名必须带 `.app` 后缀，否则 Finder 当普通文件夹处理，双击打不开。

## 交付前自检清单

- [ ] `./Scripts/build.sh` 全绿
- [ ] 改动数据层时 `swift test` 全绿
- [ ] 改动 UI 时实机/模拟器截图确认渲染正常
- [ ] 临时调试代码（截图路由、日志、环境变量开关）已清除
- [ ] 新增文件已包含在 `project.yml` 覆盖的目录下（否则需 `xcodegen generate`）