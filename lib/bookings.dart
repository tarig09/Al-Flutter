import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'services.dart';
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
        sb.from('security_requests').select().order('created_at', ascending: false).limit(30),
        sb.from('fx_requests').select().order('created_at', ascending: false).limit(30),
      ]);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async { setState(() => f = _load()); await f; },
        child: Load<List<dynamic>>(f, (d) {
          final cut = DateTime.now().subtract(const Duration(days: 7));
          final b = (d[0] as List).cast<Map<String, dynamic>>().where((x) => x['trips'] == null || DateTime.parse('${x['trips']['depart_at']}').isAfter(cut)).toList(), s = (d[1] as List).cast<Map<String, dynamic>>(), t = (d[2] as List).cast<Map<String, dynamic>>(), sc = (d[3] as List).cast<Map<String, dynamic>>(), fx = (d[4] as List).cast<Map<String, dynamic>>();
          if (b.isEmpty && s.isEmpty && t.isEmpty && sc.isEmpty && fx.isEmpty) return ListView(children: const [SizedBox(height: 120), Empty('لا توجد طلبات بعد')]);
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
              Card(child: ListTile(leading: const Icon(Icons.inventory_2, color: kPri), title: Text('إرسالية ${x['tracking_no'] ?? x['ref_no'] ?? ''}'), subtitle: Text('${x['from_place'] ?? ''} ← ${x['to_place'] ?? ''}'), trailing: StatusBadge('${x['status']}'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShipDetail('${x['id']}'))))),
            for (final x in t)
              Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet, color: kPri), title: Text('تحويل ${money(x['amount'] as num?)}'), subtitle: Text('${x['country'] ?? ''}'), trailing: StatusBadge('${x['status']}'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransferDetail('${x['id']}'))))),
            for (final x in fx)
              Card(child: ListTile(leading: const Icon(Icons.currency_exchange, color: kPri), title: Text('تبديل ${x['ref_no']}'), subtitle: Text('${money(x['amount'] as num?).replaceAll(' ج.س', '')} ${x['direction'] == 'egp_sdg' ? 'مصري ← سوداني' : 'سوداني ← مصري'}'), trailing: StatusBadge('${x['status']}', label: x['status'] == 'pending' ? 'قيد المراجعة' : null))),
            for (final x in sc)
              Card(child: ListTile(leading: const Icon(Icons.shield, color: kPri), title: Text('${x['service'] ?? 'طلب أمني'}'), subtitle: Text('${x['ref_no'] ?? ''}'), trailing: StatusBadge('${x['status']}'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SecurityDetail('${x['id']}'))))),
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
  final tkey = GlobalKey();

  Future<Uint8List> _png() async {
    final bd = tkey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await bd.toImage(pixelRatio: 3);
    return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<void> saveTicket(String ref, bool asPdf) async {
    try {
      final png = await _png();
      final dir = await getTemporaryDirectory();
      late File f;
      if (asPdf) {
        final doc = pw.Document();
        final im = pw.MemoryImage(png);
        final dec = await decodeImageFromList(png);
        final w = 420.0, h = w * dec.height / dec.width;
        doc.addPage(pw.Page(pageFormat: PdfPageFormat(w, h, marginAll: 0), build: (_) => pw.Image(im, fit: pw.BoxFit.fill)));
        f = File('${dir.path}/ticket-$ref.pdf')..writeAsBytesSync(await doc.save());
      } else {
        f = File('${dir.path}/ticket-$ref.png')..writeAsBytesSync(png);
      }
      await Share.shareXFiles([XFile(f.path)], text: 'تذكرة $ref');
    } catch (e) {
      if (mounted) toast(context, 'تعذّر حفظ التذكرة');
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final b = await sb.from('bookings').select('*, trips(*, buses(name,plate_no,bus_type,driver_name,driver_phone))').eq('id', widget.id).single();
    List pm = [];
    if (b['status'] == 'accepted') {
      final base = sb.from('payment_methods').select().eq('active', true);
      pm = b['agency_id'] != null ? await base.eq('agency_id', b['agency_id']).order('sort') : await base.isFilter('agency_id', null).order('sort');
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
            RepaintBoundary(key: tkey, child: Card(
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
            )),
            if (ok) Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [Expanded(child: FilledButton(onPressed: () => saveTicket('${b['ref_no']}', false), child: const Text('حفظ كصورة'))), const SizedBox(width: 10), Expanded(child: OutlinedButton(onPressed: () => saveTicket('${b['ref_no']}', true), child: const Text('حفظ PDF')))])),
            if (st != 'pending' && st != 'cancelled') ...[
              if (t['buses'] != null) Card(child: ListTile(leading: const Icon(Icons.directions_bus, color: kPri), title: Text('الحافلة: ${t['buses']['name']}'), subtitle: Text([if (t['buses']['plate_no'] != null) 'اللوحة ${t['buses']['plate_no']}', if (t['buses']['driver_name'] != null) 'السائق ${t['buses']['driver_name']}'].join('  •  ')))),
              head('حالة الرحلة'),
              timeline(const ['scheduled', 'departed', 'on_road', 'near', 'arrived'], '${t['travel_status'] ?? 'scheduled'}', times: t['status_updated_at'] != null ? {'${t['travel_status']}': '${t['status_updated_at']}'} : null, labels: const {'scheduled': 'لم تتحرك بعد', 'departed': 'تحركت الرحلة', 'on_road': 'في الطريق', 'near': 'قربت على الوصول', 'arrived': 'وصلت بسلامة'}),
            ],
            if (ok && b['agency_id'] != null && t['travel_status'] == 'arrived') RateCard('booking', '${b['id']}'),
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
