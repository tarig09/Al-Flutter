import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';

/// الجهة المستلمة للطلب: مكتب (agency) أو قسم مباشر (office)
class Target {
  final String? agencyId;
  final Map<String, dynamic> pricing;
  final String name;
  const Target(this.agencyId, this.pricing, this.name);
  static Target ofAgency(Map<String, dynamic> a) => Target('${a['id']}', a, '${a['name']}');
  static Target ofOffice(Map<String, dynamic> o) => Target(null, o, '${o['name_ar']}');
}

Future<String?> pickPath(BuildContext c, String bucket, String prefix) async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
  if (x == null) return null;
  final p = '${sb.auth.currentUser!.id}/$prefix-${DateTime.now().millisecondsSinceEpoch}.jpg';
  await sb.storage.from(bucket).upload(p, File(x.path));
  return p;
}

Widget tf(String l, TextEditingController c, {TextInputType? t, int lines = 1, bool ro = false, void Function(String)? on}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, keyboardType: t, maxLines: lines, readOnly: ro, onChanged: on, decoration: InputDecoration(labelText: l)));

Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPri)));

Future<Map<String, dynamic>?> myProfile() => sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).maybeSingle();

/// بطاقة المشرف المتابع
Widget handlerCard(BuildContext ctx, Map<String, dynamic> r) {
  if (r['handler_name'] == null) return const SizedBox();
  final ph = '${r['handler_phone'] ?? ''}';
  return Card(
    child: ListTile(
      leading: const Icon(Icons.support_agent, color: kPri),
      title: Text('يتابع طلبك: ${r['handler_name']}'),
      subtitle: Text(ph),
      trailing: ph.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:$ph'))),
        IconButton(icon: const Icon(Icons.chat, color: Colors.green), onPressed: () => launchUrl(Uri.parse('https://wa.me/${ph.replaceAll(RegExp(r'\D'), '')}'), mode: LaunchMode.externalApplication)),
      ]),
    ),
  );
}

/// المخطط الزمني
Widget timeline(List<String> keys, String status, {Map<String, String>? times, Map<String, String>? labels}) {
  final idx = keys.indexOf(status);
  final done = status == keys.last;
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        for (var i = 0; i < keys.length; i++)
          Row(children: [
            Icon(done || i < idx ? Icons.check_circle : i == idx ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: done || i < idx ? Colors.green : i == idx ? kAcc : Colors.grey),
            const SizedBox(width: 10),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(labels?[keys[i]] ?? (statusMap[keys[i]]?[0] ?? keys[i]) as String, style: TextStyle(fontWeight: i == idx ? FontWeight.bold : FontWeight.normal)),
              if (times?[keys[i]] != null) Text(dt(times![keys[i]]), style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]))),
          ]),
      ]),
    ),
  );
}

/// خريطة بسيطة (OpenStreetMap)
Widget mapCard(String title, double lat, double lng, String? when) {
  final p = LatLng(lat, lng);
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    head(title),
    Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        SizedBox(
          height: 220,
          child: FlutterMap(
            options: MapOptions(initialCenter: p, initialZoom: 11),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.almahatta.al_mahatta'),
              MarkerLayer(markers: [Marker(point: p, width: 44, height: 44, child: const Icon(Icons.location_on, color: Colors.red, size: 40))]),
            ],
          ),
        ),
        ListTile(
          dense: true,
          title: Text(when == null ? '' : 'آخر تحديث: ${dt(when)}', style: const TextStyle(fontSize: 12.5)),
          trailing: TextButton(onPressed: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=12/$lat/$lng'), mode: LaunchMode.externalApplication), child: const Text('فتح الخريطة')),
        ),
      ]),
    ),
  ]);
}

/// تقييم المكتب
class RateCard extends StatefulWidget {
  final String agencyId;
  const RateCard(this.agencyId, {super.key});
  @override
  State<RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<RateCard> {
  int stars = 0;
  final c = TextEditingController();
  @override
  void initState() {
    super.initState();
    sb.from('agency_ratings').select('stars').eq('agency_id', widget.agencyId).eq('user_id', sb.auth.currentUser!.id).maybeSingle().then((r) {
      if (r != null && mounted) setState(() => stars = (r['stars'] as num).toInt());
    });
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head('قيّم المكتب'),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(onPressed: () => setState(() => stars = i), icon: Icon(i <= stars ? Icons.star : Icons.star_border, color: kAcc, size: 34))]),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'تعليق (اختياري)')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: stars == 0 ? null : () async {
              try {
                await sb.rpc('rate_agency', params: {'p_agency': widget.agencyId, 'p_stars': stars, 'p_comment': c.text.trim().isEmpty ? null : c.text.trim()});
                if (mounted) toast(context, 'شكراً لتقييمك');
              } catch (e) { if (mounted) toast(context, errMsg(e)); }
            },
            child: const Text('إرسال التقييم'),
          ),
        ]))),
      ]);
}

Widget agencyHeader(Map<String, dynamic>? a) => a == null ? const SizedBox() : Card(child: ListTile(leading: a['logo_url'] != null ? CircleAvatar(backgroundImage: NetworkImage('${a['logo_url']}')) : const CircleAvatar(child: Icon(Icons.business)), title: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('المكتب المسؤول عن طلبك')));

Future<Map<String, dynamic>?> getAgency(Object? id) async => id == null ? null : await sb.from('agencies').select().eq('id', id).maybeSingle();

Widget payMethodsCards(BuildContext ctx, List<Map<String, dynamic>> pm) => Column(children: [
      if (pm.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('لم تُضف وسيلة دفع بعد. تواصل مع المشرف لمعرفة طريقة الدفع.')),
      for (final m in pm)
        Card(child: ListTile(
          title: Text('${m['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${m['account_no']}${m['holder'] != null ? '\n${m['holder']}' : ''}${m['note'] != null ? '\n${m['note']}' : ''}'),
          trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () { Clipboard.setData(ClipboardData(text: '${m['account_no']}')); toast(ctx, 'تم النسخ'); }),
        )),
    ]);

Future<List<Map<String, dynamic>>> payMethods(Object? agencyId) async {
  final base = sb.from('payment_methods').select().eq('active', true);
  final r = agencyId != null ? await base.eq('agency_id', agencyId).order('sort') : await base.isFilter('agency_id', null).order('sort');
  return (r as List).cast<Map<String, dynamic>>();
}

// ───────────────────────── الإرساليات ─────────────────────────
class ShipNew extends StatefulWidget {
  final Target target;
  const ShipNew(this.target, {super.key});
  @override
  State<ShipNew> createState() => _ShipNewState();
}

class _ShipNewState extends State<ShipNew> {
  final sn = TextEditingController(), sp = TextEditingController(), sf = TextEditingController(), rn = TextEditingController(), rp = TextEditingController(), rt = TextEditingController(), wk = TextEditingController(text: '1'), ds = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    myProfile().then((p) { if (p != null && mounted) setState(() { sn.text = '${p['full_name'] ?? ''}'; sp.text = '${p['phone'] ?? ''}'; }); });
  }

  num? get base => widget.target.pricing['ship_base'] as num?;
  num get cost => base == null ? 0 : base! + ((widget.target.pricing['ship_per_kg'] as num?) ?? 0) * (double.tryParse(wk.text) ?? 0);

  Future<void> go() async {
    final w = double.tryParse(wk.text) ?? 0;
    if ([sn, sp, sf, rn, rp, rt].any((c) => c.text.trim().isEmpty) || w <= 0) return toast(context, 'أكمل جميع الحقول المطلوبة');
    setState(() => busy = true);
    try {
      final r = await sb.from('shipments').insert({'sender_name': sn.text.trim(), 'sender_phone': sp.text.trim(), 'from_place': sf.text.trim(), 'receiver_name': rn.text.trim(), 'receiver_phone': rp.text.trim(), 'to_place': rt.text.trim(), 'weight_kg': w, 'description': ds.text.trim(), 'agency_id': widget.target.agencyId}).select().single();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ShipDetail('${r['id']}')));
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إرسالية جديدة')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          head('المرسل'), tf('الاسم', sn), tf('الهاتف', sp, t: TextInputType.phone), tf('مكان الإرسال', sf),
          head('المستلم'), tf('الاسم', rn), tf('الهاتف', rp, t: TextInputType.phone), tf('مكان الاستلام', rt),
          head('الإرسالية'), tf('الوزن (كجم)', wk, t: const TextInputType.numberWithOptions(decimal: true), on: (_) => setState(() {})), tf('الوصف', ds),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: base != null ? Kv('التكلفة التقديرية', money(cost)) : const Text('يحدد المكتب التكلفة بعد استلام طلبك.'))),
          const SizedBox(height: 10),
          FilledButton(onPressed: busy ? null : go, child: const Text('تسجيل الإرسالية')),
        ]),
      );
}

const shipFlow = ['received', 'in_transit', 'arrived', 'delivered'];

class ShipTrack extends StatefulWidget {
  const ShipTrack({super.key});
  @override
  State<ShipTrack> createState() => _ShipTrackState();
}

class _ShipTrackState extends State<ShipTrack> {
  final n = TextEditingController();
  Map<String, dynamic>? res;
  bool loading = false, searched = false;
  Future<void> go() async {
    final no = n.text.trim().toUpperCase();
    if (no.isEmpty) return;
    setState(() { loading = true; searched = true; });
    try {
      final r = await sb.rpc('track_shipment', params: {'p_no': no});
      res = r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = res;
    final hist = <String, String>{for (final e in ((t?['events'] ?? []) as List)) '${e['status']}': '${e['created_at']}'};
    return Scaffold(
      appBar: AppBar(title: const Text('تتبع إرسالية')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('أدخل رقم التتبع الذي يبدأ بـ TRK لعرض حالة أي إرسالية.'),
        const SizedBox(height: 10),
        TextField(controller: n, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'رقم التتبع', hintText: 'TRK-XXXXXXX')),
        const SizedBox(height: 10),
        FilledButton(onPressed: loading ? null : go, child: const Text('بحث')),
        if (loading) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (!loading && searched && t == null) const Empty('لم يتم العثور على إرسالية بهذا الرقم'),
        if (t != null) ...[
          const SizedBox(height: 12),
          Card(child: ListTile(title: Text('${t['tracking_no']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), subtitle: Text('${t['from_place']} ← ${t['to_place']}'), trailing: StatusBadge('${t['status']}'))),
          if (t['agency_name'] != null) Kv('المكتب', '${t['agency_name']}'),
          Kv('الوزن', '${t['weight_kg']} كجم'),
          head('حالة الإرسالية'),
          t['status'] == 'cancelled' ? const StatusBadge('cancelled') : timeline(shipFlow, '${t['status']}', times: hist),
          if (t['lat'] != null && t['lng'] != null) mapCard('أين الإرسالية الآن', (t['lat'] as num).toDouble(), (t['lng'] as num).toDouble(), t['updated_at'] as String?) else const Padding(padding: EdgeInsets.all(8), child: Text('سيظهر موقع الإرسالية على الخريطة عندما يحدّثه المكتب.')),
        ],
      ]),
    );
  }
}

class ShipDetail extends StatelessWidget {
  final String id;
  const ShipDetail(this.id, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('متابعة الإرسالية')),
        body: Load<List<dynamic>>(Future.wait([sb.from('shipments').select().eq('id', id).single(), sb.from('shipment_events').select().eq('shipment_id', id).order('created_at')]), (d) {
          final s = d[0] as Map<String, dynamic>;
          final hist = <String, String>{for (final e in (d[1] as List)) '${e['status']}': '${e['created_at']}'};
          return FutureBuilder<Map<String, dynamic>?>(
            future: getAgency(s['agency_id']),
            builder: (c, a) => ListView(padding: const EdgeInsets.all(16), children: [
              agencyHeader(a.data),
              handlerCard(context, s),
              Card(child: ListTile(title: Text('${s['tracking_no']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), trailing: StatusBadge('${s['status']}'))),
              Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
                Text('${s['from_place']}  ←  ${s['to_place']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPri)),
                const Divider(),
                Kv('المرسل', '${s['sender_name']}'), Kv('المستلم', '${s['receiver_name']}'), Kv('الوزن', '${s['weight_kg']} كجم'),
                Kv('التكلفة', ((s['cost'] as num?) ?? 0) > 0 ? money(s['cost'] as num) : 'يحددها المكتب'),
              ]))),
              head('حالة الإرسالية'),
              s['status'] == 'cancelled' ? const StatusBadge('cancelled') : timeline(shipFlow, '${s['status']}', times: hist),
              if (s['lat'] != null && s['lng'] != null) mapCard('أين إرساليتك الآن', (s['lat'] as num).toDouble(), (s['lng'] as num).toDouble(), s['updated_at'] as String?) else const Padding(padding: EdgeInsets.all(8), child: Text('سيظهر موقع الإرسالية على الخريطة عندما يحدّثه المكتب.')),
              if (s['status'] == 'delivered' && s['agency_id'] != null) RateCard('${s['agency_id']}'),
            ]),
          );
        }),
      );
}

// ───────────────────────── التحويلات ─────────────────────────
class TransferNew extends StatefulWidget {
  final Target target;
  const TransferNew(this.target, {super.key});
  @override
  State<TransferNew> createState() => _TransferNewState();
}

class _TransferNewState extends State<TransferNew> {
  static const cur = {'السودان': 'SDG', 'مصر': 'EGP', 'السعودية': 'SAR', 'الإمارات': 'AED', 'قطر': 'QAR', 'تركيا': 'TRY', 'أمريكا': 'USD'};
  String kind = 'domestic', country = 'السودان';
  final sn = TextEditingController(), rn = TextEditingController(), rp = TextEditingController(), am = TextEditingController(), nt = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    myProfile().then((p) { if (p != null && mounted) setState(() => sn.text = '${p['full_name'] ?? ''}'); });
  }

  num? get pct => widget.target.pricing['transfer_pct'] as num?;
  num? get min => widget.target.pricing['transfer_min'] as num?;
  num feeOf(num x) => (pct == null && min == null) ? 0 : [(x * (pct ?? 0) / 100).round(), min ?? 0].reduce((a, b) => a > b ? a : b);

  Future<void> go() async {
    final x = num.tryParse(am.text) ?? 0;
    if (sn.text.trim().isEmpty || rn.text.trim().isEmpty || rp.text.trim().isEmpty || x <= 0) return toast(context, 'أكمل الحقول المطلوبة');
    setState(() => busy = true);
    try {
      final r = await sb.from('transfers').insert({'kind': kind, 'country': country, 'currency': cur[country], 'amount': x, 'sender_name': sn.text.trim(), 'receiver_name': rn.text.trim(), 'receiver_phone': rp.text.trim(), 'note': nt.text.trim(), 'agency_id': widget.target.agencyId}).select().single();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TransferDetail('${r['id']}')));
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = num.tryParse(am.text) ?? 0, f = x > 0 ? feeOf(x) : 0;
    final feeTxt = (pct == null && min == null) ? 'بدون رسوم' : '${pct ?? 0}%${min != null ? ' بحد أدنى ${money(min)}' : ''}';
    return Scaffold(
      appBar: AppBar(title: const Text('تحويل مالي')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'domestic', label: Text('تحويل داخلي')), ButtonSegment(value: 'international', label: Text('تحويل خارجي'))],
          selected: {kind},
          onSelectionChanged: (s) => setState(() { kind = s.first; if (kind == 'domestic') country = 'السودان'; }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: country, decoration: const InputDecoration(labelText: 'الدولة'), items: [for (final k in cur.keys) DropdownMenuItem(value: k, child: Text(k))], onChanged: (v) => setState(() => country = v!)),
        const SizedBox(height: 12),
        Kv('العملة', cur[country]!),
        tf('اسم المرسل', sn), tf('اسم المستلم', rn), tf('هاتف المستلم', rp, t: TextInputType.phone),
        tf('المبلغ', am, t: const TextInputType.numberWithOptions(decimal: true), on: (_) => setState(() {})), tf('ملاحظة', nt),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Kv('الرسوم ($feeTxt)', x > 0 ? money(f) : '—'), Kv('الإجمالي', x > 0 ? money(x + f) : '—')]))),
        const SizedBox(height: 10),
        FilledButton(onPressed: busy ? null : go, child: const Text('إرسال التحويل')),
      ]),
    );
  }
}

class TransferDetail extends StatefulWidget {
  final String id;
  const TransferDetail(this.id, {super.key});
  @override
  State<TransferDetail> createState() => _TransferDetailState();
}

class _TransferDetailState extends State<TransferDetail> {
  late Future<Map<String, dynamic>> f = _load();
  bool busy = false;
  Future<Map<String, dynamic>> _load() async {
    final t = await sb.from('transfers').select().eq('id', widget.id).single();
    return {'t': t, 'a': await getAgency(t['agency_id']), 'pm': t['status'] == 'accepted' ? await payMethods(t['agency_id']) : <Map<String, dynamic>>[]};
  }

  void reload() => setState(() => f = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حالة التحويل')),
        body: Load<Map<String, dynamic>>(f, (d) {
          final t = d['t'] as Map<String, dynamic>, a = d['a'] as Map<String, dynamic>?, pm = (d['pm'] as List).cast<Map<String, dynamic>>();
          final st = '${t['status']}', dead = st == 'rejected' || st == 'cancelled';
          return ListView(padding: const EdgeInsets.all(16), children: [
            agencyHeader(a), handlerCard(context, t),
            Card(child: ListTile(title: Text('${t['ref_no']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: StatusBadge(st))),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
              Kv('النوع', t['kind'] == 'domestic' ? 'داخلي' : 'خارجي'), Kv('الدولة / العملة', '${t['country']} · ${t['currency']}'), Kv('المستلم', '${t['receiver_name']}'),
              Kv('المبلغ', money(t['amount'] as num?)), Kv('الرسوم', money(t['fee'] as num?)), Kv('الإجمالي المطلوب دفعه', money(t['total'] as num?)),
            ]))),
            head('متابعة الحالة'),
            dead ? StatusBadge(st) : timeline(const ['pending', 'accepted', 'payment_review', 'processing', 'completed'], st),
            if (st == 'accepted') ...[
              head('طريقة الدفع'),
              Card(color: kAcc.withOpacity(.12), child: Padding(padding: const EdgeInsets.all(14), child: Text('قبل المكتب طلبك. حوّل الإجمالي ${money(t['total'] as num?)} ثم ارفع إثبات التحويل.'))),
              payMethodsCards(context, pm),
              FilledButton.icon(
                onPressed: busy ? null : () async {
                  setState(() => busy = true);
                  try {
                    final p = await pickPath(context, 'payment-proofs', 't-${t['id']}');
                    if (p != null) {
                      await sb.rpc('submit_transfer_proof', params: {'p_transfer': t['id'], 'p_path': p});
                      if (mounted) toast(context, 'تم رفع الإثبات');
                      reload();
                    }
                  } catch (e) { if (mounted) toast(context, errMsg(e)); }
                  if (mounted) setState(() => busy = false);
                },
                icon: const Icon(Icons.upload), label: const Text('رفع إثبات الدفع')),
            ],
            if (st == 'payment_review') const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('تم استلام إثبات الدفع، والمشرف يراجعه ثم ينفّذ التحويل.'))),
            if (['pending', 'accepted', 'payment_review'].contains(st)) Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton(onPressed: () async {
              try { await sb.rpc('cancel_transfer', params: {'p_transfer': t['id']}); reload(); } catch (e) { toast(context, errMsg(e)); }
            }, child: const Text('إلغاء الطلب'))),
            if (st == 'completed' && a != null) RateCard('${a['id']}'),
          ]);
        }),
      );
}

// ───────────────────────── الموافقات الأمنية ─────────────────────────
class SecurityNew extends StatefulWidget {
  final Target target;
  const SecurityNew(this.target, {super.key});
  @override
  State<SecurityNew> createState() => _SecurityNewState();
}

class _SecurityNewState extends State<SecurityNew> {
  final sv = TextEditingController(), fn = TextEditingController(), ph = TextEditingController(), idn = TextEditingController(), nt = TextEditingController();
  final docs = <XFile>[];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    myProfile().then((p) { if (p != null && mounted) setState(() { fn.text = '${p['full_name'] ?? ''}'; ph.text = '${p['phone'] ?? ''}'; }); });
  }

  Future<void> go() async {
    if (sv.text.trim().isEmpty || fn.text.trim().isEmpty || ph.text.trim().isEmpty) return toast(context, 'الخدمة والاسم والهاتف مطلوبة');
    setState(() => busy = true);
    try {
      final paths = <String>[];
      for (final x in docs) {
        final p = '${sb.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}-${paths.length}.jpg';
        await sb.storage.from('documents').upload(p, File(x.path));
        paths.add(p);
      }
      final r = await sb.from('security_requests').insert({'service': sv.text.trim(), 'full_name': fn.text.trim(), 'phone': ph.text.trim(), 'id_no': idn.text.trim().isEmpty ? null : idn.text.trim(), 'notes': nt.text.trim(), 'docs': paths, 'agency_id': widget.target.agencyId}).select().single();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SecurityDetail('${r['id']}')));
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلب موافقة أمنية')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          tf('نوع الطلب / الخدمة', sv), tf('الاسم الكامل', fn), tf('الهاتف', ph, t: TextInputType.phone), tf('رقم الهوية / الجواز', idn), tf('ملاحظات', nt, lines: 3),
          OutlinedButton.icon(
            onPressed: docs.length >= 5 ? null : () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
              if (x != null) setState(() => docs.add(x));
            },
            icon: const Icon(Icons.attach_file), label: Text('إرفاق مستند (${docs.length}/5)')),
          Wrap(spacing: 6, children: [for (var i = 0; i < docs.length; i++) Chip(label: Text('مستند ${i + 1}'), onDeleted: () => setState(() => docs.removeAt(i)))]),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : go, child: const Text('إرسال الطلب')),
        ]),
      );
}

class SecurityDetail extends StatelessWidget {
  final String id;
  const SecurityDetail(this.id, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حالة الطلب')),
        body: Load<Map<String, dynamic>>(sb.from('security_requests').select().eq('id', id).single(), (r) => FutureBuilder<Map<String, dynamic>?>(
              future: getAgency(r['agency_id']),
              builder: (c, a) => ListView(padding: const EdgeInsets.all(16), children: [
                agencyHeader(a.data), handlerCard(context, r),
                Card(child: ListTile(title: Text('${r['ref_no']}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), trailing: StatusBadge('${r['status']}'))),
                Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [Kv('الخدمة', '${r['service']}'), Kv('مقدم الطلب', '${r['full_name']}'), Kv('المستندات', '${(r['docs'] as List).length} ملف'), Kv('التاريخ', dt('${r['created_at']}'))]))),
                head('متابعة الطلب'),
                r['status'] == 'rejected' ? const StatusBadge('rejected') : timeline(const ['pending', 'processing', 'approved'], '${r['status']}'),
                if (r['status'] == 'approved' && a.data != null) RateCard('${a.data!['id']}'),
              ]),
            )),
      );
}

// ───────────────────────── العقارات ─────────────────────────
class PropsPage extends StatefulWidget {
  final String? agencyId;
  const PropsPage(this.agencyId, {super.key});
  @override
  State<PropsPage> createState() => _PropsPageState();
}

class _PropsPageState extends State<PropsPage> {
  String f = 'all';
  late final Future<dynamic> fut = widget.agencyId != null
      ? sb.from('properties').select().eq('active', true).eq('agency_id', widget.agencyId!).order('created_at', ascending: false)
      : sb.from('properties').select().eq('active', true).isFilter('agency_id', null).order('created_at', ascending: false);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('العقارات')),
        body: Load<dynamic>(fut, (d) {
          final l = (d as List).cast<Map<String, dynamic>>().where((p) => f == 'all' || p['listing'] == f).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [for (final c in const [['all', 'الكل'], ['sale', 'بيع'], ['rent', 'إيجار']]) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(c[1]), selected: f == c[0], onSelected: (_) => setState(() => f = c[0])))]),
            if (l.isEmpty) const Empty('لا توجد عقارات'),
            for (final p in l)
              Card(clipBehavior: Clip.antiAlias, child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PropDetail(p))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (p['image_url'] != null) Image.network('${p['image_url']}', height: 170, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 60)),
                  Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.bold))), Text(p['listing'] == 'sale' ? 'بيع' : 'إيجار')]),
                    Text('${p['city']}${p['area'] != null ? ' - ${p['area']}' : ''}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text('${money(p['price'] as num?)}${p['listing'] == 'rent' ? ' / شهر' : ''}', style: const TextStyle(color: kPri, fontWeight: FontWeight.bold, fontSize: 17)),
                  ])),
                ]),
              )),
          ]);
        }),
      );
}

class PropDetail extends StatelessWidget {
  final Map<String, dynamic> p;
  const PropDetail(this.p, {super.key});
  Future<void> send(BuildContext c, String kind) async {
    final prof = await myProfile();
    final ctl = TextEditingController(text: '${prof?['phone'] ?? ''}');
    if (!c.mounted) return;
    final ok = await showDialog<bool>(context: c, builder: (x) => AlertDialog(title: const Text('رقم هاتفك للتواصل'), content: TextField(controller: ctl, keyboardType: TextInputType.phone), actions: [TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(x, true), child: const Text('إرسال'))]));
    if (ok != true || ctl.text.trim().isEmpty) return;
    try {
      await sb.from('property_requests').insert({'property_id': p['id'], 'kind': kind, 'phone': ctl.text.trim(), 'agency_id': p['agency_id']});
      if (c.mounted) toast(c, 'تم إرسال طلبك');
    } catch (e) {
      if (c.mounted) toast(c, errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل العقار')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (p['image_url'] != null) ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network('${p['image_url']}', height: 210, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
          const SizedBox(height: 10),
          Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          Text('${money(p['price'] as num?)}${p['listing'] == 'rent' ? ' / شهر' : ''}', style: const TextStyle(color: kPri, fontWeight: FontWeight.bold, fontSize: 19)),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
            Kv('النوع', '${p['kind'] ?? '—'}'), Kv('الموقع', '${p['city']}${p['area'] != null ? ' - ${p['area']}' : ''}'), Kv('الغرف', '${p['rooms'] ?? '—'}'), Kv('الحمامات', '${p['baths'] ?? '—'}'), Kv('المساحة', p['size_m2'] != null ? '${p['size_m2']} م²' : '—'),
          ]))),
          if ('${p['details'] ?? ''}'.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('${p['details']}'))),
          FilledButton(onPressed: () => send(context, 'viewing'), child: const Text('طلب معاينة')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => send(context, 'booking'), child: const Text('طلب حجز')),
        ]),
      );
}
