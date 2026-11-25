# A-Life: Caravans [B42]

<p align="center"><a href="https://boosty.to/lrgpp"><img src="https://raw.githubusercontent.com/druidqwerty/ALifeCaravans/1858d2be2573d322611113e4dd056945862a136b/docs/banner.png" alt="LrgPP mods on Boosty" width="640"></a></p>

专为 Vice 的 [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) 打造的派系车队扩展模组。远离玩家时，车队沿着持久化台账在城镇之间穿行；靠近玩家时，它们会化身为配备 NPC 司机与乘员的实体车队。追上并拦停它们、以物易物、搭便车同行，或在遭遇伏击时掩护车队突围。

[Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3829571361) · [源码 / 发布页 (MIT)](https://github.com/druidqwerty/ALifeCaravans) · [English](README.md) · [Русский](README_RU.md)

免费开源。代码在 AI 辅助下编写，方向把控、测试与时间投入由作者本人完成。[在 Boosty 上支持模组开发](https://boosty.to/lrgpp)。

> **0.8.3 — Project A-Life 1.5.4 稳定性修复：彻底消除控制台重复刷屏报错 `KahluaException: A teammate is no longer loaded.`（`ALifeDrivingCrew.lua:55` / `ALifeDrivingLifecycle.lua:393` / `ALC_Spawn.lua`），加固乘客卸载后的 `S.recrew` 恢复逻辑，并修复非车队载具生成的参数透传。**

## 0.8.3 更新内容

- **消除控制台重复刷屏 `KahluaException: A teammate is no longer loaded.`（`ALC_Spawn.lua`）：**
  - 在 `DrivingLifecycle.create` 钩子中新增前置校验（`S.validateCreateCrew` 与 `findCreateNpc`），当司机或乘客未加载、已死亡、代数过期或座位冲突时平稳返回 `(nil, reason)`，避免触发 `ALifeDrivingCrew.lua:55` 的 `error()` 导致 Kahlua 在控制台持续刷屏。
  - 修复 200ms `DrivingDemo.npcIndex` / `npcMemo` 过期缓存导致的误判未加载问题。
  - 加固 `S.recrew`：在 `S.releaseCar` 前后重新校验乘员存活与加载状态、同步 `boarded` 标记并在创建失败时安全回滚（保留 `restoredRiders` 状态）。
  - 修复 `VehicleArrivalSites.find` 与 `VehicleArrivalVehicle.create` 在非车队载具路径下透传可变参数（`script`、`color`）。
  - 已在 **Project Zomboid 42.22.2 + Project A-Life 1.5.4** 上通过验证（`528/528` 离线断言 + 实机 SP 5 阶段测试，`0` `KahluaException`）。

## 0.8.2 更新内容

- **路边补给投送与易物装备保护修复（`09_ALC_Radio.lua`、`05_ALC_Trade.lua`）：**
  - 修复 `@PriestSmokey` 反馈的严重问题：订购补给箱时不再消耗装备栏/腰带槽位、手持物品、钥匙与钥匙串、背包容器、对讲机/电台、武器、装弹枪械、衣物、书写工具或收藏物品。补给箱自动扣款现仅限现金与安全的非受保护消耗品。
  - 修复 `inspectDevice` 电量判定：没电的对讲机（`power <= 0.001`）不再被误判为有电可用。
- **Project Zomboid 42.22.2 与 Project A-Life 1.5.3 全面适配（`03_ALC_Roads.lua`、`ALC_Spawn.lua`、`04_ALC_Convoy.lua`、`06_ALC_Physics.lua`、`02_ALC_Vehicles.lua`、`ALC_Cargo.lua`）：**
  - 对接 Project A-Life 1.5.2/1.5.3 新模块（`CarSweep`、`CarOffline`、`CarWatchdog`、`CarBrain`、`DrivingBoarding.seatResult`、`DrivingLifecycle.carseatRelease`、`DrivingBrakeRelease`、`HeliModels`），修复高速公路刷新死锁（`cars8_site_rim` / `Cars9.streetSite` / `VehicleArrivals.minSiteTiles`）。
  - 更新 11 个在 Build 42.22.2 中改名或移除的物品/载具 ID（如 `Base.WaterBottle`、`Base.WaterRationCan`、`Base.WalkieTalkie4`、`Base.CigarettePack`、`Base.VanAmbulance` 等），并将路边协助修车加油改为 B42 `FluidContainer` 液位扣油。
- **其他修复与优化（`00_ALC_Core.lua`、`ALC_RadioServer.lua`、`ALC_Director.lua`、`ALC_Interact.lua`、`ALC_Client.lua`、`ALC_RadioWindow.lua`）：**
  - 修复 `NightTravelPenalty` 沙盒数值归一化（`/ 100`）、补给箱领取原子校验、SOS 遇险广播、威胁勒索交物、右键菜单同时显示补给箱与车队、F9 快捷键暂停/菜单/聊天防误触以及电台窗口 500ms 缓存优化。

## 0.8.1 更新内容

- **完整中文本地化（`Translate/CN` 与 `Translate/CH`，EN/RU/CN/CH 全量对齐）：**
  - 为 `IG_UI.json`、`Sandbox.json` 与 `UI.json` 新增完整的简体中文（`CN`）与繁体中文（`CH`）翻译，并新增 [README_CN.md](README_CN.md) 与 Steam 创意工坊简体/繁体中文页面。
  - 原版 Project Zomboid Build 42 自带完整的 `CH` 繁体字库支持，开箱即可正常渲染；`CN` 提供简体中文文本。
  - 相较于 `0.8.0`，所有 `.lua` 运行时脚本均保持不变。

## 0.8.0 更新内容

- **Project A-Life 1.5 / 1.5.1 全面兼容与有组织的多车编队（`ALC_Spawn.lua`、`02_ALC_Vehicles.lua`、`00_ALC_Core.lua`）：**
  - 深度对接 Project A-Life 1.5.1 的 `CarLife`、`CarLifeServer`、`Cars2`、`VehicleEvasion` 与 `RadioReserved` 模块：A-Life 徒步小队在车队路边停靠期间绝不会占领或撬开停放中的车队车辆，车队电台频道也会自动避开 A-Life 保留的频率。
  - 由于单车幸存者现在已由 Project A-Life 1.5 的 `CarLife` 接管，Caravans 默认启用**有组织的 2–4 车编队**（`MinVehicles = 2`、`CrewMin = 4`，可在沙盒选项中调整）。无需安装 Java 组件或 `ZombieBuddy`。
- **101.6 MHz 车队与贸易电台（`09_ALC_Radio.lua`、`ALC_RadioServer.lua`、`ALC_RadioWindow.lua`、`ALC_Map.lua`）：** 将 *A-Life: Airwaves & Contracts* 的核心功能直接并入 Caravans：
  - 在原版 `ZomboidRadio` / `DynamicRadio` 中注册专属 **101.6 MHz 车队与贸易电台**（对讲机、固定电台与车载电台均可收听），配有电台广播日志与头顶 `HaloText` 提示。
  - 新增 3 标签页 **车队电台与补给调度窗口（`ALCRadioWindow`）**：可通过快捷键 **F9**（可在“选项 → 模组”中修改）、右键点击任意电台，或在车队接触窗口点击 **电台调度 (101.6)** 打开。
  - **电台呼叫最近车队：** 在 `101.6 MHz` 呼叫最近的友好贸易车队原地待命（或朝你方向行驶）并广播其坐标。
  - **路边补给投送：** 使用现金或以物易物额度订购 5 类补给箱（**医疗**、**弹药**、**燃料与维修**、**工具**、**口粮**）投送至附近路段。
  - **城镇市场与道路情报 + 自动地图标记：** 通过电台请求区域紧缺物资简报，查看哪些城镇对紧缺物资提供 **+35% 更高收购额度**；随身携带钢笔或铅笔（`Base.Pen`、`Base.Pencil`）时会自动添加 `WorldMapSymbols` 地图标记。

## 0.7.2 更新内容

- **多车车队乘员归属锁定与安全登车（`ALC_Spawn.lua`、`ALC_Crew.lua`、`ALC_Director.lua`、`04_ALC_Convoy.lua`）：**
  - 车队每辆车都会记住各自专属的乘员组（`caravan.carCrews`），避免后车在重新登车时抢占头车的司机或乘客；非战斗路边停靠时各乘员只在各自车辆旁下车；登车/下车期间全车队保持停稳，避免误伤己方成员，短暂碾过路缘或尸体的倾斜不再误触发退出驾驶。
- **装甲载具刷新概率与缴获车辆耐久上限（`02_ALC_Vehicles.lua`、`ALC_Lifecycle.lua`、`sandbox-options.txt`）：**
  - `ArmoredVehicleChance`（`0–100%`，默认 `25%`）：控制装甲与战术载具（如 KI5 装甲车、悍马、SWAT、MRAP、军卡等）的出现概率。
  - `TrophyVehicleCondition`（`10–100%`，默认 `40%`）：限制车队全员阵亡后遗留车辆的部件、电瓶与油量上限，使战后车辆呈战损状态而非完好无损的免费装甲车。

## 0.7.1 更新内容

- **城镇区域供需经济（`07_ALC_Market.lua`、`ALC_Economy.lua`）：** 路网城镇动态追踪医疗、食物、弹药、燃料和工具 5 类物资的紧缺与充裕情况。车队优先驶向紧缺城镇，对紧缺物资提供 **+35% 更高收购额度**，并在实际抵达后补充城镇库存。
- **5 种特殊事件车队（`trade_fair`、`medical_aid`、`supply_drop`、`refugees`、`scavenger_haul`）：** 巡回商队、医疗援助队、补给运输队、难民车队与搜刮运输队各自拥有专属货池、对话、地图图标与路边服务。
- **实体后备箱货物与路边援助服务（`ALC_Cargo.lua`、`ALC_ContactWindow.lua`）：** 车队后备箱生成实体物资（未经交易偷窃会激怒车队）；接触面板提供**协助修车/加油**、**战地医疗包扎**、**捐赠物资**、**保养玩家座驾**与**道路情报**功能。
- **问题修复：** 修复了与 *Collapse - Destructible Buildings* 的 `BodyDamage` 崩溃，恢复了对车内 NPC 的枪械弹道伤害，默认过滤重型主战坦克与工程机械（可通过 `AllowHeavyArmor` 开关控制），并改善了与 *Viewpoint*、*Jeem Extension*、*Living Factions* 共存时的停车停滞问题。

## 主要玩法

- **邂逅多派系车队：** 军方、警方、救援队、商人及掠夺者；拥有命名队长与呼号，3–8 名 NPC 与最多 4 辆载具。自动兼容已加载的模组载具定义（排除残骸与拖车）。
- **地图追踪：** 在世界地图与小地图上以彩色车辆图标显示车队位置、朝向与呼号；图标可见性与标签可在个人选项中独立开关。
- **拦停互动：** 在车队约 18 格范围内右键互动、鸣笛或连续闪烁三次车灯拦停。对方会根据态度作出回应，可询问消息、请求延长停留时间或让其继续出发。
- **以物易物：** 支持现金或物品交易，货品依派系而异并受好感影响。主机校验并执行实际物品交换；客户端同步库存与收据。已装备、收藏、装有物品的背包及装弹枪械均受保护不会被误卖。
- **手柄支持：** 支持车队右键发现菜单与交易窗口全手柄操作；分屏模式下各玩家槽位相互独立。
- **搭便车与护送：** 申请搭乘空位或接受目的地护送合约；载有玩家的车辆受保护不会被常规清理。
- **响应 SOS 求救：** 接取遇袭友好车队的求救任务，跟紧并掩护 NPC 实际驾车突围（默认需撤离 80 格且持续移动至少 30 秒），成功可一次性获得 +3 好感。
- **承担后果：** 威胁平民车队可能迫使其交出物品并逃离；军方、警方与掠夺者则会迎战。向掠夺者支付过路费可换取暂时停火。

## 依赖与安装

- **验证运行环境：** Project Zomboid Build 42.22.2 与 Project A-Life 1.5.3（需开启 NPC 驾驶 `Driving`）。
- **必装前置：** [Project A-Life [ALIFE NPCS]](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183)。
- **可选推荐：** [A-Life: Factions Expanded](https://steamcommunity.com/sharedfiles/filedetails/?id=3813871509) 与 [Project A-Life – Jeem Extension](https://steamcommunity.com/sharedfiles/filedetails/?id=3806944055)。
- 所有玩家与服务器需保持一致的模组版本。加载顺序：`ProjectALifeNPCs;ALifeCaravans`。无需安装 Java 组件或 `ZombieBuddy`。

## 设置与使用

- **主机全局设置：** **沙盒选项 > A-Life: Caravans**（默认 5 支车队、35 km/h 巡航、最多 4 辆车、拦停等待 180 秒、实体化/回收距离 120/200 格，可逐项关闭特性）。
- **个人显示与快捷键：** **选项 > 模组**（支持局内实时调整，无需重启）。
- **世界模拟机制：** 远距离车队沿 Project A-Life 城镇路网在台账中近似推进；近距离则由物理车辆接管，受已加载区块与路障影响；单人由本地、多人由服务器掌握台账与交易权威。

## 验证与当前限制

- **验证报告：** [0.8.0 当前源码验证报告](TEST_0.8.0.md)（`python tools/run_test.py`、`python tools/pz_loadcheck.py` 与 Build 42.21 单人实机联调）。
- **已知限制：** 每支车队最多 4 辆车，不支持拖车牵引；远距离图标沿粗粒度路网移动；暂不支持玩家招募车队成员或自建个人车队；SOS 目前仅指掩护伏击突围。

## 鸣谢

**Vice / Project A-Life：** 提供 NPC、驾驶、路网、Knox County 电台与对话系统。**Minidoracat / MiniMap - AutoDrive for B42 (MIT)：** 参考了寻路、航点与脱困思路（未复制其代码）。本模组开发使用 AI 辅助，由 druid 负责方向把控与测试。

© 2026 druidqwerty. Released under the MIT License. Project A-Life by Vice.
