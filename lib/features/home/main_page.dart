import 'package:flutter/material.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0; // 当前选中的底部导航栏索引

  // 这里是我们即将开发的各个核心模块页面的占位符
  final List<Widget> _pages = [
    const Center(
      child: Text('模块2：这里将是【血糖与饮食记录】页面', style: TextStyle(fontSize: 18)),
    ),
    const Center(
      child: Text('模块3：这里将是【数据统计与升糖分析】页面', style: TextStyle(fontSize: 18)),
    ),
    const Center(
      child: Text('模块5：这里将是【健康知识推送】页面', style: TextStyle(fontSize: 18)),
    ),
    const Center(
      child: Text('模块1：这里将是【个人中心】页面', style: TextStyle(fontSize: 18)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex], // 根据索引显示对应的页面
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed, // 固定样式，不使用默认的动画
        selectedItemColor: Colors.teal, // 选中的颜色
        unselectedItemColor: Colors.grey, // 未选中的颜色
        onTap: (index) {
          setState(() {
            _currentIndex = index; // 点击时切换索引并刷新界面
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.edit_document), label: '记录'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '统计'),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb_outline),
            label: '发现',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
