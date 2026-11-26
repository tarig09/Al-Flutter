import 'package:flutter/material.dart';
import 'extras.dart';
import 'ui.dart';

class NotificationsPage extends StatefulWidget {
  final Future<void> Function() onRead;
  const NotificationsPage({super.key, required this.onRead});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late Future<List<dynamic>> f = _load();
  Future<List<dynamic>> _load() async {
    final r = await sb.from('notifications').select().order('created_at', ascending: false).limit(50);
    if ((r as List).any((n) => n['read'] != true)) {
      await sb.rpc('mark_all_read');
      widget.onRead();
    }
    return r;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async { setState(() => f = _load()); await f; },
        child: Load<List<dynamic>>(f, (d) {
          if (d.isEmpty) return ListView(children: const [SizedBox(height: 120), Empty('لا توجد إشعارات')]);
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final n in d.cast<Map<String, dynamic>>())
              Card(child: ListTile(
                leading: Icon(Icons.notifications, color: n['read'] == true ? Colors.grey : kAcc),
                title: Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${n['body'] ?? ''}\n${dt('${n['created_at']}')}'),
                isThreeLine: true,
              )),
          ]);
        }),
      );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final n = TextEditingController(), p = TextEditingController(), c = TextEditingController();
  @override
  void initState() {
    super.initState();
    sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).maybeSingle().then((r) {
      if (r != null && mounted) setState(() { n.text = '${r['full_name'] ?? ''}'; p.text = '${r['phone'] ?? ''}'; c.text = '${r['city'] ?? ''}'; });
    });
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(sb.auth.currentUser?.email ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 12),
        TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 10),
        TextField(controller: p, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
        const SizedBox(height: 10),
        TextField(controller: c, decoration: const InputDecoration(labelText: 'المدينة')),
        const SizedBox(height: 14),
        FilledButton(onPressed: () async {
          try {
            await sb.from('profiles').update({'full_name': n.text.trim(), 'phone': p.text.trim(), 'city': c.text.trim()}).eq('id', sb.auth.currentUser!.id);
            if (mounted) toast(context, 'تم الحفظ');
          } catch (e) { if (mounted) toast(context, errMsg(e)); }
        }, child: const Text('حفظ')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => sb.auth.signOut(), child: const Text('تسجيل الخروج')),
        const SocialBar(),
      ]);
}
