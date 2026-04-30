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
