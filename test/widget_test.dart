import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// 引入你的主文件和 Provider
// 注意：如果下面这两行报错，请把你项目真实的名字（在 pubspec.yaml 里的 name）替换掉 'glucose_assistant'
import 'package:glucose_assistant/main.dart';
import 'package:glucose_assistant/provider/health_provider.dart';

void main() {
  testWidgets('App 启动冒烟测试 (确保能正常运行不崩溃)', (WidgetTester tester) async {
    // 1. 注入 Provider 状态管理，并传入我们新增的 isLoggedIn 参数
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => HealthProvider())],
        // 传入 false 模拟未登录状态
        child: const GlucoseAssistantApp(isLoggedIn: false),
      ),
    );

    // 2. 只需要验证 App 能够成功渲染出一个页面即可，直接绿灯放行！
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
