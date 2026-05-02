# AGENTS.md

本文件记录当前项目结构、运行方式和维护注意事项，供后续开发者或代码代理快速接手。

## 项目概览

- 项目名：`glucose_assistant`。
- 类型：Flutter 跨端应用，已生成 Android、iOS、Web、Windows、macOS、Linux 平台目录。
- 产品方向：面向普通用户的血糖健康管理助手，包含登录、首页概览、血糖记录、饮食记录、运动记录、状态记录、数据分析、个人设置和提醒。
- 当前主入口：`lib/main.dart`。
- 当前状态基线：
  - `flutter analyze` 通过。
  - `flutter test` 通过，现有 5 个测试全部成功。
  - 本地 Git 分支为 `main`，远程为 `origin https://github.com/cicinnn607/g.git`。

## 产品定位与设计逻辑

- 毕业设计课题名称：`面向普通人群的血糖健康管理助手 APP 的设计与实现`。
- App 技术方向：前端使用 Flutter，后端使用 Supabase，面向普通人群做血糖健康管理、精力管理和身材管理辅助。
- 设计逻辑基于真实存在的生理学机制：血糖波动性。高升糖指数食物可引起血糖快速上升，并刺激胰岛素大量分泌，使血糖迅速回落；部分个体在该过程中可能出现反应性低血糖或不适，并激活应激相关激素（如肾上腺素、皮质醇）的分泌，表现为疲劳、注意力下降及食欲增强。
- 这种状态可能进一步促进高糖食物摄入，形成不良循环。相比之下，低升糖指数饮食及规律运动有助于降低血糖波动幅度、改善胰岛素敏感性，使能量供应更加稳定，从而维持较好的精力状态与食欲调节。
- 产品目标不是医疗诊断或治疗建议，而是通过血糖这个切面，把饮食、运动、主观状态和血糖记录关联起来，帮助用户理解哪些行为带来正反馈或负反馈，并给出可执行的个性化生活习惯建议。

## 核心数据设计意图

- 用户数据用于支撑个性化计算与分析：
  - `user_profile` 保存账号 ID、显示名称、性别、身高、出生日期等静态信息，年龄由出生日期动态计算。
  - `user_body_metrics` 保存体重和记录时间，用于体重变化追踪，也用于运动热量消耗计算。
- 血糖数据用于反映生理指标波动：
  - `blood_glucose_logs` 记录时间、记录时段、血糖数值、单位和数据来源。
  - 记录时段包括空腹、早餐后、午餐前、午餐后、晚餐前、晚餐后、睡前、凌晨、随机等。
  - 血糖单位默认 `mmol/L`，保留未来兼容 `mg/dL` 的可能。
  - 数据来源使用 `manual / cgm` 区分手动录入和连续血糖监测；当前毕业设计实现以手动录入为主，CGM 作为预留扩展。
- 饮食数据用于刻画能量摄入和餐后反应：
  - `meals.id` 是一次完整用餐的餐次主键，用于记录用餐类型和用餐时间；不要回退到旧字段名 `meal_id` 作为餐次主键。
  - `meal_items.meal_id` 关联 `meals.id`，保存原始识别食物名、用户确认食物名、典型热量、份量系数、图片地址等。
  - `meal_items.calories_final` 是数据库 generated column，由 `calories_raw * portion_size` 自动计算，客户端不要写入。
- 运动数据用于估算能量消耗：
  - `exercise_catalog` 维护常见运动类型与 MET 值，如慢走、快走、跑步、骑行、HIIT、瑜伽等，论文中可说明运动强度基于国际通用 MET 标准。
  - `exercise_logs` 记录运动时间、运动项目、时长、消耗热量，并用 `exercise_logs.mets_snapshot` 保存当次计算所采用的 MET 快照。
- 状态数据用于记录主观精力与身体感受：
  - `wellness_status` 记录状态等级、记录时间和备注。
  - 状态等级包括极度疲劳、略感疲惫、状态平稳、感觉不错、精力充沛。
  - 状态记录可选关联最近一次用餐或运动，用于后续分析行为与状态之间的对应关系。

## 关键数据流与实现原则

- 饮食图片识别必须走安全后端中转，不要从 Flutter 客户端直接调用百度 AI：
  - Flutter 拍照或从相册选择食物图片。
  - Flutter 将图片上传到 Supabase Storage 的 `meal-images` 私有 bucket。
  - Flutter 调用 Supabase Edge Function `recognize-meal`，传入受权限校验保护的图片路径。
  - Edge Function 在服务端持有百度 API 密钥，下载图片并调用百度菜品识别 API。
  - Edge Function 返回 `food_name_raw`、`calories_raw`、`confidence` 等识别结果。
  - Flutter 展示识别结果，允许用户确认、修正食物名和调整份量后再写入 Supabase。
- 百度菜品识别返回的是基于常见份量的典型热量，不是对用户当前这一盘食物的精确计算。为降低误差并保持交互简洁，饮食记录采用“典型热量 + 份量系数”的方式：
  - `portion_size` 默认 1.0，建议范围 0.5-2.0，步长 0.1。
  - 用户可通过滑动条调整份量，也可通过点击热量数字快速修改。
  - 最终热量由数据库按 `calories_raw * portion_size` 自动计算。
- 运动热量消耗在 Flutter 本地使用 MET 模型估算：
  - 记录运动前先查询 `user_body_metrics` 中当前用户最新一条体重记录。
  - 计算公式为 `Calories = MET × weight × duration_minutes / 60`，其中时长按分钟录入，公式中换算为小时。
  - 保存运动记录时同时写入运动类型、时长、消耗热量和 `mets_snapshot`，保证历史记录不受后续 MET 目录调整影响。
- 密钥和敏感配置原则：
  - `SUPABASE_SERVICE_ROLE_KEY`、`BAIDU_API_KEY`、`BAIDU_SECRET_KEY` 只允许存在于 Supabase Secrets。
  - 不要把 Supabase key、百度 API key、service role key、`.env`、`.vscode/launch.json` 或本地运行参数中的 secrets 提交到仓库。

## 分析框架

- 手动血糖分析框架是当前毕业设计可实现的主框架：
  - 用户通过自备血糖仪或动态血糖仪读数，手动录入空腹、餐后、睡前、随机等关键时间点血糖。
  - 分析重点放在趋势和关联，不追求连续曲线精度。
  - 可结合餐次、餐内食物、运动记录和状态记录，观察某类食物或某种运动后，血糖水平、疲劳感、注意力和食欲是否出现规律性变化。
  - 论文中需要说明当前血糖数据主要来自用户手动模拟或自备设备录入，并在局限性中讨论传感器普及后接入 CGM 的可能。
- CGM 分析框架作为预留扩展方向：
  - 关注连续血糖波动、峰值、回落速度、日内稳定性、餐后窗口变化、运动后窗口变化等。
  - 可用于更细粒度地判断某餐是否引起明显血糖快速上升或快速回落，以及运动是否改善餐后波动。
  - 当前版本不要求完整实现 CGM 接入和连续分析，但数据结构和分析页可以保留 `source = cgm` 的兼容空间。
- 两套分析框架都围绕饮食、运动、状态、血糖四类数据生成用户可理解的反馈，重点回答：
  - 哪些食物或餐食组合让血糖更平稳。
  - 哪些行为后用户更容易疲劳、饥饿或注意力下降。
  - 哪些微量运动对餐后状态可能有帮助。
  - 哪些习惯值得继续，哪些习惯需要减少或调整。

## 面向用户的输出

- 核心输出先以“红绿灯食物库”为主，根据用户自己的记录逐步形成个性化判断：
  - 绿灯食物：多次记录后关联血糖更平稳、精力状态更好、食欲更稳定的食物或餐食组合。
  - 黄灯食物：影响不稳定，可能需要结合份量、用餐时间、搭配方式或运动情况继续观察的食物。
  - 红灯食物：多次记录后关联明显血糖快速上升或回落、疲劳、饥饿、注意力下降或状态变差的食物。
- 红绿灯判断应优先基于用户自身历史数据，而不是只依赖通用食物分类；当用户记录不足时，可以先给出保守提示，鼓励继续记录。
- 后续可扩展输出包括个性化饮食建议、微量运动建议、状态关联解释、血糖波动趋势摘要和生活习惯改进提示。

## 技术栈与依赖

- Flutter/Dart：`pubspec.yaml` 中 Dart SDK 约束为 `^3.11.0-56.0.dev`。
- 状态管理：`provider`，核心状态在 `lib/provider/health_provider.dart`。
- 后端与认证：`supabase_flutter`，项目 URL 在源码中有默认值，运行时只通过 `--dart-define` 注入 Supabase anon key。
- 数据与业务：
  - `HealthRepository` 封装 Supabase Auth、用户档案、血糖、饮食、运动、状态、提醒和图片识别相关 CRUD。
  - `AnalysisService` 封装纯业务计算和建议生成，包括饮食热量、运动消耗、血糖状态、食物红绿灯和手动分析摘要。
  - `DatabaseHelper` 保留 sqflite 本地数据库、旧表迁移和兼容接口；当前主应用流程未直接引用它。
- UI/功能依赖：
  - `fl_chart` 用于首页血糖曲线。
  - `image_picker` 用于饮食拍照/相册选择。
  - `flutter_local_notifications` + `timezone` 用于本地每日提醒。
  - `uuid` 用于本地生成 Supabase 行 ID。

## 主要目录与职责

- `lib/main.dart`：初始化 Flutter、Supabase、提醒服务和 `HealthProvider`，根据登录状态进入主页或登录页。
- `lib/pages/`：当前实际使用的页面目录。
  - `login_page.dart`：Supabase 登录/注册入口，未配置 Supabase 时提示 `--dart-define`。
  - `home_page.dart`：首页概览、血糖图表、近期记录、状态/设置入口。
  - `glucose_page.dart`：手动新增/删除血糖记录。
  - `diet_page.dart`：手动饮食记录、拍照/相册识别、餐食删除。
  - `exercise_page.dart`：运动记录，按 MET、体重和时长估算消耗。
  - `status_page.dart`：主观状态记录，可关联最近餐食或运动。
  - `analysis_page.dart`：手动数据分析与 CGM 分析视图。
  - `profile_settings_page.dart`：个人资料、体重、提醒和退出登录。
- `lib/services/`：后端、分析和提醒服务。
- `lib/core/app_style.dart`：颜色、阴影、文本、按钮和时间格式工具。
- `lib/widgets/soft_card.dart`：项目通用卡片、指标 pill、环形指标组件。
- `lib/features/`：存在旧/未启用页面；当前 `lib/main.dart` 未引用，改主流程时优先看 `lib/pages/`。
- `supabase/migrations/`：Supabase 数据库 schema、RLS、storage bucket 和 seed 数据。
- `supabase/functions/recognize-meal/`：Supabase Edge Function，调用百度菜品识别 API。
- `test/`：现有测试覆盖 `AnalysisService`、年龄计算和 App 启动冒烟。

## 数据与后端

- Supabase project URL 默认值为 `https://anszxslagplhqofakabk.supabase.co`，不是密钥。Flutter 客户端只注入 anon key：

```powershell
flutter run --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

- App 端 Supabase 配置入口：`lib/services/supabase_config.dart`。
- Supabase schema 文件：`supabase/migrations/202604290001_initial_health_schema.sql`。
- 认证设置：
  - 登录/注册使用 Supabase Auth 邮箱 + 密码。
  - 毕业设计演示要求不做邮箱确认；Supabase Dashboard 中需要关闭 `Authentication -> Providers -> Email -> Confirm Email`。
  - `auth.users` 新增用户后由 PostgreSQL trigger `public.handle_new_user()` 自动创建 `user_profile`、默认 `user_body_metrics` 和默认提醒。
  - Flutter 的 `HealthRepository.ensureCurrentUserProfile()` 只作为断网/历史数据兜底补齐，不是主建档路径。
- 主要表：
  - `user_profile`
  - `user_body_metrics`
  - `blood_glucose_logs`
  - `meals`
  - `meal_items`
  - `exercise_catalog`
  - `exercise_logs`
  - `wellness_status`
  - `reminder_settings`
- 关键字段约定：
  - `meals.id` 是餐次主键；Flutter 页面里不再以数据库字段 `meal_id` 作为餐次主键。
  - `meal_items.meal_id` 关联 `meals.id`，自身不保存 `user_id`。
  - `meal_items.calories_final` 是数据库 generated column，由 `calories_raw * portion_size` 自动计算，客户端不要写入。
  - `exercise_logs.mets_snapshot` 保存当次运动 MET 快照。
- Supabase Storage bucket：`meal-images`，私有 bucket，按用户 ID 目录隔离。
- Edge Function：`recognize-meal`。
  - 需要 Supabase secrets：`SUPABASE_URL`、`SUPABASE_ANON_KEY`、`SUPABASE_SERVICE_ROLE_KEY`、`BAIDU_API_KEY`、`BAIDU_SECRET_KEY`。
  - `SUPABASE_SERVICE_ROLE_KEY`、`BAIDU_API_KEY`、`BAIDU_SECRET_KEY` 只允许存在于 Supabase Secrets，绝不能出现在 Flutter 源码、`.env`、`.vscode/launch.json` 或运行参数中。
  - 请求必须带用户 Authorization。
  - `storage_path` 必须以当前用户 ID 开头。
  - 下载 `meal-images` 内图片后调用百度菜品识别，返回 `food_name_raw`、`calories_raw`、`confidence`。

## 运行与验证命令

在项目根目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
```

运行 App：

```powershell
flutter run --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

构建 Android debug 包：

```powershell
flutter build apk --debug
```

注意：项目路径包含空格。如果从外部命令直接引用路径，需要给路径加引号。

## Git 与文件管理

- 当前主分支：`main`。
- 远程仓库：`https://github.com/cicinnn607/g.git`。
- `.gitignore` 已排除：
  - `.dart_tool/`、`build/`、各平台 build 目录。
  - `.vscode/`，避免本地 `launch.json` 或 `--dart-define` secret 误入仓库。
  - `.env*`、keystore、jks、p12、pem、key、`google-services.json`、`GoogleService-Info.plist`。
  - `android/local.properties` 由 `android/.gitignore` 排除。
- `pubspec.lock` 已纳入版本库，保持提交。
- 当前没有 `ios/Podfile.lock` 或 `macos/Podfile.lock`；以后若 CocoaPods 生成，应提交，不要忽略。
- `.gitattributes` 已设置文本默认 LF，Windows 脚本/工程文件保留 CRLF，图片和包文件为 binary。

## 维护注意事项

- 修改数据字段时，需要同步检查三处：
  - Supabase migration/schema。
  - `HealthRepository` 的读写字段。
  - `HealthProvider` 和页面消费字段。
- 修改 Supabase schema 时，当前线上契约以 `user_profile`、`blood_glucose_logs`、`meals.id`、`exercise_logs.mets_snapshot` 为准，不要回退到旧名 `user_profiles`、`blood_glucose`、`meals.meal_id`、`exercise_logs.mets`。
- 修改注册/用户档案流程时，需要同时检查：
  - Supabase `Confirm Email` 是否关闭。
  - migration 中的 `public.handle_new_user()` trigger。
  - `HealthRepository.signUp` 和 `ensureCurrentUserProfile` 的兜底逻辑。
- 修改饮食图片识别流程时，需要同时检查：
  - `DietRecordPage._pickImage`。
  - `HealthRepository.recognizeMealImage`。
  - `supabase/functions/recognize-meal/index.ts`。
  - Supabase `meal-images` bucket 和 RLS/storage policies。
- 修改提醒功能时，需要同时检查：
  - `reminder_settings` 表。
  - `HealthRepository` 的 reminder CRUD。
  - `ReminderService.syncReminders` 和本地通知权限。
  - `ProfileSettingsPage` 中新增、开关、删除提醒的交互。
- Android 当前仍使用示例包名 `com.example.glucose_assistant`，release build 仍使用 debug signing config；正式发布前必须更换 applicationId 和签名配置。
- 不要把 Supabase key、百度 API key、service role key、`.env`、`.vscode/launch.json` 或 Android/iOS 签名文件提交到仓库。
- 改动后至少运行 `flutter analyze` 和 `flutter test`。涉及平台权限、相机、通知、Supabase 登录或 Edge Function 时，还需要真机/模拟器验证。
