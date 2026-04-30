# glucose_assistant

稳啦：面向普通人群的血糖健康管理助手 App。

## Supabase 运行配置

运行 Flutter 时不要把密钥写进源码，使用 Dart Define 传入：

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

数据库结构在 `supabase/migrations/202604290001_initial_health_schema.sql`，菜品识别 Edge Function 在 `supabase/functions/recognize-meal`。百度密钥请配置为 Supabase secrets：`BAIDU_API_KEY` 和 `BAIDU_SECRET_KEY`。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
