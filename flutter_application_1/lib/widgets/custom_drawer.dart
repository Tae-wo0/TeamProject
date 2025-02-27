import 'package:flutter/material.dart';
import '../pages/login_page.dart';
import '../services/firestore_service.dart';
import '../pages/home_page.dart';
import '../pages/search_page.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const LoginPage(),
                ),
                (route) => false,
              );
            },
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FirestoreService _firestoreService = FirestoreService();
    final userId = _firestoreService.currentUserId;
    final userEmail = _firestoreService.currentUserEmail;
    if (userId == null) throw Exception('로그인이 필요합니다');

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            currentAccountPicture: const CircleAvatar(
              child: Icon(Icons.person),
            ),
            accountName: Text(userEmail ?? ''),
            accountEmail: null,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('홈'),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(initialIndex: 0),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('검색'),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchPage(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('보관함'),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(initialIndex: 2),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('로그아웃'),
            onTap: () {
              Navigator.pop(context);
              _handleLogout(context);
            },
          ),
        ],
      ),
    );
  }
}
