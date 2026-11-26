import 'dart:async';
import 'package:flutter/material.dart';
import 'bookings.dart';
import 'sections.dart';
import 'ui.dart';
import 'misc.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0, unread = 0;
  Timer? t;

  @override
  void initState() {
    super.initState();
    poll();
    t = Timer.periodic(const Duration(seconds: 30), (_) => poll());
  }

  @override
  void dispose() { t?.cancel(); super.dispose(); }

  Future<void> poll() async {
    try {
      final r = await sb.from('notifications').select('id').eq('read', false);
      if (mounted) setState(() => unread = (r as List).length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const HomePage(), const OrdersPage(), NotificationsPage(onRead: poll), const AccountPage()];
    return Scaffold(
      appBar: AppBar(title: Text(['المحطة', 'طلباتي', 'الإشعارات', 'حسابي'][tab])),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'طلباتي'),
          NavigationDestination(icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)), label: 'الإشعارات'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Load<List<dynamic>>(
        Future.wait([sb.from('offices').select().eq('active', true).order('sort'), sb.from('banners').select().eq('active', true).order('sort')]),
        (d) {
          final offices = (d[0] as List).cast<Map<String, dynamic>>(), banners = (d[1] as List).cast<Map<String, dynamic>>();
          if (offices.isEmpty && banners.isEmpty) return const Empty('لا توجد أقسام حالياً');
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final b in banners)
              Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPri, Color(0xFF073548)]), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b['title'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                if (b['subtitle'] != null) Text('${b['subtitle']}', style: const TextStyle(color: Colors.white70)),
              ])),
            GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.25, children: [
              for (final o in offices)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SectionPage(o))),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(sectionIcon('${o['slug']}'), size: 38, color: kPri),
                      const SizedBox(height: 8),
                      Text('${o['name_ar']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
            ]),
          ]);
        },
      );
}

IconData sectionIcon(String slug) => switch (slug) {
      'travel' => Icons.directions_bus,
      'parcels' => Icons.inventory_2,
      'transfers' => Icons.account_balance_wallet,
      'security' => Icons.shield,
      'realestate' => Icons.apartment,
      _ => Icons.apps,
    };
