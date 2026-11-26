import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Future<List<dynamic>> f = _load();
  Future<List<dynamic>> _load() => Future.wait([
        sb.from('bookings').select('*, trips(from_city,to_city,depart_at)').order('created_at', ascending: false).limit(30),
        sb.from('shipments').select().order('created_at', ascending: false).limit(30),
        sb.from('transfers').select().order('created_at', ascending: false).limit(30),
      ]);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async { setState(() => f = _load()); await f; },
        child: Load<List<dynamic>>(f, (d) {
          final b = (d[0] as List).cast<Map<String, dynamic>>(), s = (d[1] as List).cast<Map<String, dynamic>>(), t = (d[2] as List).cast<Map<String, dynamic>>();
          if (b.isEmpty && s.isEmpty && t.isEmpty) return ListView(children: const [SizedBox(height: 120), Empty('لا توجد طلبات بعد')]);
          return ListView(padding: const EdgeInsets.all(16), children: [
            for (final x in b)
              Card(child: ListTile(
                leading: const Icon(Icons.directions_bus, color: kPri),
                title: Text(x['trips'] == null ? 'حجز' : '${x['trips']['from_city']} ← ${x['trips']['to_city']}'),
                subtitle: Text('${x['ref_no']}  •  ${money(x['total'] as num?)}'),
                trailing: StatusBadge('${x['status']}'),
                onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetail('${x['id']}'))); setState(() => f = _load()); },
              )),
            for (final x in s)
              Card(child: ListTile(leading: const Icon(Icons.inventory_2, color: kPri), title: Text('إرسالية ${x['tracking_no'] ?? x['ref_no'] ?? ''}'), subtitle: Text('${x['from_place'] ?? ''} ← ${x['to_place'] ?? ''}'), trailing: StatusBadge('${x['status']}'))),
            for (final x in t)
              Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet, color: kPri), title: Text('تحويل ${money(x['amount'] as num?)}'), subtitle: Text('${x['country'] ?? ''}'), trailing: StatusBadge('${x['status']}'))),
          ]);
        }),
      );
}

class BookingDetail extends StatefulWidget {
  final String id;
  const BookingDetail(this.id, {super.key});
  @override
  State<BookingDetail> createState() => _BookingDetailState();
}

class _BookingDetailState extends State<BookingDetail> {
  late Future<Map<String, dynamic>> f = _load();
  bool busy = false;

  Future<Map<String, dynamic>> _load() async {
    final b = await sb.from('bookings').select('*, trips(*)').eq('id', widget.id).single();
    List pm = [];
    if (b['status'] == 'accepted') {
      final q = sb.from('payment_methods').select().eq('active', true).order('sort');
      pm = b['agency_id'] != null ? await q.eq('agency_id', b['agency_id']) : await q.isFilter('agency_id', null);
    }
    return {'b': b, 'pm': pm};
  }

  void reload() => setState(() => f = _load());

  Future<void> upload(Map<String, dynamic> b) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
    if (x == null) return;
    setState(() => busy = true);
    try {
      final path = '${sb.auth.currentUser!.id}/${b['id']}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await sb.storage.from('payment-proofs').upload(path, File(x.path));
      await sb.rpc('submit_payment_proof', params: {'p_booking': b['id'], 'p_path': path});
      if (mounted) toast(context, 'تم رفع الإثبات');
      reload();
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('إلغاء هذا الحجز؟'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم'))]));
    if (ok != true) return;
    try {
      await sb.rpc('cancel_booking', params: {'p_booking': b['id']});
      reload();
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('التذكرة')),
        body: Load<Map<String, dynamic>>(f, (d) {
          final b = d['b'] as Map<String, dynamic>, t = b['trips'] as Map<String, dynamic>, pm = (d['pm'] as List).cast<Map<String, dynamic>>();
          final st = '${b['status']}', ok = st == 'confirmed';
          final seats = (b['seats'] as List).join('، ');
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (b['handler_name'] != null)
              Card(child: ListTile(
                leading: const Icon(Icons.support_agent, color: kPri),
                title: Text('يتابع طلبك: ${b['handler_name']}'),
                subtitle: Text('${b['handler_phone'] ?? ''}'),
                trailing: b['handler_phone'] != null ? IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:${b['handler_phone']}'))) : null,
              )),
            Card(
              child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('تذكرة سفر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), StatusBadge(st)]),
                const SizedBox(height: 8),
                Text('${t['from_city']}  ←  ${t['to_city']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kPri)),
                const Divider(height: 24),
                Kv('المسافر', '${b['passenger_name']}'), Kv('الهاتف', '${b['passenger_phone']}'), Kv('الموعد', dt('${t['depart_at']}')), Kv('المقاعد', seats), Kv('الإجمالي', money(b['total'] as num?)),
                const Divider(height: 24),
                if (ok) QrImageView(data: 'MAHATTA|${b['ref_no']}', size: 190) else Padding(padding: const EdgeInsets.all(24), child: Text(st == 'cancelled' ? 'التذكرة ملغاة' : 'يظهر الباركود بعد أن يُصدر المشرف التذكرة', style: const TextStyle(color: Colors.black54))),
                Text('${b['ref_no']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kPri, letterSpacing: 2)),
              ])),
            ),
            if (st == 'accepted') ...[
              const SizedBox(height: 8),
              Card(color: kAcc.withOpacity(.12), child: Padding(padding: const EdgeInsets.all(14), child: Text('قبل المكتب طلبك. المبلغ المطلوب تحويله: ${money(b['total'] as num?)}', style: const TextStyle(fontWeight: FontWeight.bold)))),
              if (pm.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لم تُضف وسيلة دفع بعد. تواصل مع المشرف لمعرفة طريقة الدفع.')),
              for (final m in pm)
                Card(child: ListTile(
                  title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${m['account_no']}${m['holder'] != null ? '\n${m['holder']}' : ''}'),
                  trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: '${m['account_no']}')); toast(context, 'تم النسخ'); }),
                )),
              FilledButton.icon(onPressed: busy ? null : () => upload(b), icon: const Icon(Icons.upload), label: const Text('رفع إثبات الدفع')),
            ],
            if (st == 'payment_review') const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('تم استلام إثبات الدفع، والمشرف يراجعه ثم يُصدر تذكرتك.'))),
            if (['pending', 'accepted', 'payment_review'].contains(st)) Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton(onPressed: () => cancel(b), child: const Text('إلغاء الحجز'))),
          ]);
        }),
      );
}
