# glucose_assistant

稳啦：面向普通人群的血糖健康管理助手 App。

## Supabase 运行配置

项目 URL 默认使用 `https://anszxslagplhqofakabk.supabase.co`。运行 Flutter 时不要把密钥写进源码，只使用 Dart Define 传入 anon key：

```powershell
flutter run --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

数据库结构在 `supabase/migrations/202604290001_initial_health_schema.sql`，菜品识别 Edge Function 在 `supabase/functions/recognize-meal`。`SUPABASE_SERVICE_ROLE_KEY`、`BAIDU_API_KEY` 和 `BAIDU_SECRET_KEY` 只配置为 Supabase secrets，不进入 Flutter 客户端。

注册流程使用邮箱 + 密码，并按毕业设计演示需求关闭邮箱确认：在 Supabase Dashboard 的 `Authentication -> Providers -> Email` 中关闭 `Confirm Email`。数据库 trigger `public.handle_new_user()` 会在 `auth.users` 新增用户时自动创建默认 `user_profile`、`user_body_metrics` 和提醒。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
