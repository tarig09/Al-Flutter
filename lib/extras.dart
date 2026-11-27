import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ui.dart';

/// محوّل العملات + طلب تبديل (يُعتمد من الإدارة) — داخل قسم التحويلات المالية
class ConverterPage extends StatefulWidget {
  const ConverterPage({super.key});
  @override
  State<ConverterPage> createState() => _ConverterPageState();
}

class _ConverterPageState extends State<ConverterPage> {
  bool egpToSdg = true, busy = false, rateTouched = false;
  final amount = TextEditingController(), reqRate = TextEditingController();
  late final Future<Map<String, dynamic>?> fut = sb.from('currency_rates').select().eq('pair', 'EGP_SDG').maybeSingle();
  late Future<List<dynamic>> mine = _mine();

  Future<List<dynamic>> _mine() async => await sb.from('fx_requests').select().order('created_at', ascending: false).limit(20) as List;

  String fmt(num v) => NumberFormat('#,##0.##', 'en').format(v);

  Future<void> submit(double x, double rate) async {
    if (x <= 0 || rate <= 0) return toast(context, 'أدخل المبلغ وسعر التبديل');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد طلب التبديل'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Kv('الاتجاه', egpToSdg ? 'مصري ← سوداني' : 'سوداني ← مصري'),
          Kv('المبلغ', '${fmt(x)} ${egpToSdg ? 'جنيه مصري' : 'جنيه سوداني'}'),
          Kv('سعر التبديل', fmt(rate)),
          Kv('تحصل على', '${fmt(egpToSdg ? x * rate : x / rate)} ${egpToSdg ? 'جنيه سوداني' : 'جنيه مصري'}'),
          const SizedBox(height: 8),
          const Text('سيُرسل الطلب للإدارة، ولا يُنفَّذ إلا بعد موافقتها.', style: TextStyle(color: Colors.black54, fontSize: 12.5)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('تبديل'))],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await sb.from('fx_requests').insert({'user_id': sb.auth.currentUser!.id, 'direction': egpToSdg ? 'egp_sdg' : 'sdg_egp', 'amount': x, 'requested_rate': rate});
      if (!mounted) return;
      toast(context, 'تم إرسال طلب التبديل للإدارة');
      amount.clear();
      setState(() => mine = _mine());
    } catch (e) {
      if (mounted) toast(context, errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('محوّل العملات')),
        body: Load<Map<String, dynamic>?>(fut, (r) {
          final official = r == null ? 0.0 : (r['rate'] as num).toDouble();
          if (!rateTouched && reqRate.text.isEmpty && official > 0) reqRate.text = official.toString();
          final x = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
          final rr = double.tryParse(reqRate.text) ?? 0;
          final out = official > 0 ? (egpToSdg ? x * official : x / official) : 0.0;
          final outReq = rr > 0 ? (egpToSdg ? x * rr : x / rr) : 0.0;
          return ListView(padding: const EdgeInsets.all(16), children: [
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('مصري ← سوداني')), ButtonSegment(value: false, label: Text('سوداني ← مصري'))],
              selected: {egpToSdg},
              onSelectionChanged: (s) => setState(() => egpToSdg = s.first),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'المبلغ (${egpToSdg ? 'جنيه مصري' : 'جنيه سوداني'})'),
            ),
            const SizedBox(height: 14),
            if (official > 0) ...[
              Card(
                color: kPri,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Text('المبلغ بعد التحويل (السعر الرسمي)', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(x > 0 ? fmt(out) : '—', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                    Text(egpToSdg ? 'جنيه سوداني' : 'جنيه مصري', style: const TextStyle(color: kAcc, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
              Kv('سعر الفك الرسمي', '1 جنيه مصري = ${fmt(official)} جنيه سوداني'),
              if (r!['updated_at'] != null) Kv('آخر تحديث', dt('${r['updated_at']}')),
            ] else
              const Padding(padding: EdgeInsets.all(12), child: Text('لم يحدد سعر الصرف الرسمي بعد.', style: TextStyle(color: Colors.black54))),
            const Divider(height: 30),
            const Text('طلب تبديل عملات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kPri)),
            const SizedBox(height: 4),
            const Text('حدّد السعر الذي ترغب بالتبديل به، وسيُراجع طلبك من الإدارة.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: reqRate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_) => setState(() => rateTouched = true),
              decoration: const InputDecoration(labelText: 'سعر التبديل المطلوب (1 جنيه مصري = كم سوداني)'),
            ),
            if (x > 0 && rr > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Kv('ستحصل على', '${fmt(outReq)} ${egpToSdg ? 'جنيه سوداني' : 'جنيه مصري'}')),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: busy ? null : () => submit(x, rr), icon: const Icon(Icons.swap_horiz), label: const Text('تبديل')),
            const SizedBox(height: 18),
            const Text('طلبات التبديل الخاصة بي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            FutureBuilder<List<dynamic>>(
              future: mine,
              builder: (c, s) {
                if (s.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                final l = ((s.data ?? []) as List).cast<Map<String, dynamic>>();
                if (l.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد طلبات بعد', style: TextStyle(color: Colors.black54)));
                return Column(children: [
                  for (final q in l)
                    Card(child: ListTile(
                      title: Text('${fmt(q['amount'] as num)} ${q['direction'] == 'egp_sdg' ? 'مصري ← سوداني' : 'سوداني ← مصري'}'),
                      subtitle: Text('السعر ${fmt(q['requested_rate'] as num)}  •  ${fmt((q['result_amount'] ?? 0) as num)}\n${q['ref_no']}${q['note'] != null ? '\n${q['note']}' : ''}'),
                      isThreeLine: true,
                      trailing: StatusBadge('${q['status']}', label: q['status'] == 'pending' ? 'قيد المراجعة' : null),
                    )),
                ]);
              },
            ),
          ]);
        }),
      );
}

IconData _icon(String p) => switch (p) {
      'facebook' => Icons.facebook,
      'tiktok' => Icons.music_note,
      'telegram' => Icons.telegram,
      'whatsapp' => Icons.chat,
      'instagram' => Icons.camera_alt,
      'youtube' => Icons.play_circle_fill,
      'x' => Icons.alternate_email,
      'snapchat' => Icons.photo_camera,
      _ => Icons.public,
    };

Color _color(String p) => switch (p) {
      'facebook' => const Color(0xFF1877F2),
      'tiktok' => Colors.black,
      'telegram' => const Color(0xFF229ED9),
      'whatsapp' => const Color(0xFF25D366),
      'instagram' => const Color(0xFFE1306C),
      'youtube' => const Color(0xFFFF0000),
      'snapchat' => const Color(0xFFF7C600),
      'x' => Colors.black,
      _ => kPri,
    };

/// شريط أيقونات التواصل (تُضاف من لوحة الإدارة)
class SocialBar extends StatelessWidget {
  const SocialBar({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
        future: sb.from('social_links').select().eq('active', true).order('sort'),
        builder: (c, s) {
          final l = ((s.data ?? []) as List).cast<Map<String, dynamic>>();
          if (l.isEmpty) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              const Text('تابعنا على', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Wrap(spacing: 14, runSpacing: 10, alignment: WrapAlignment.center, children: [
                for (final x in l)
                  Tooltip(
                    message: '${x['label'] ?? x['platform']}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () async {
                        final u = Uri.tryParse('${x['url']}');
                        if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
                      },
                      child: CircleAvatar(radius: 22, backgroundColor: _color('${x['platform']}'), child: Icon(_icon('${x['platform']}'), color: Colors.white, size: 22)),
                    ),
                  ),
              ]),
            ]),
          );
        },
      );
}
