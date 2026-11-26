import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ui.dart';

enum _M { login, signup, verify, forgot, reset }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  _M mode = _M.login;
  bool busy = false;
  String? note;
  final email = TextEditingController(), pw = TextEditingController(), name = TextEditingController(), phone = TextEditingController(), code = TextEditingController();

  String authErr(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'البريد أو كلمة المرور غير صحيحة.';
    if (s.contains('already registered')) return 'هذا البريد مسجّل مسبقاً.';
    if (s.contains('password') && s.contains('6')) return 'كلمة المرور 6 أحرف على الأقل.';
    if (s.contains('rate') || s.contains('seconds')) return 'محاولات كثيرة، انتظر قليلاً ثم أعد المحاولة.';
    if (s.contains('expired') || s.contains('invalid')) return 'الرمز غير صحيح أو منتهي.';
    return m;
  }

  Future<void> run(Future<void> Function() f) async {
    setState(() { busy = true; note = null; });
    try {
      await f();
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('not confirmed')) {
        await sb.auth.resend(type: OtpType.signup, email: email.text.trim());
        setState(() { mode = _M.verify; note = 'حسابك غير مؤكد. أرسلنا رمز تأكيد إلى بريدك.'; });
      } else {
        setState(() => note = authErr(e.message));
      }
    } catch (e) {
      setState(() => note = errMsg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() => run(() async {
        final e = email.text.trim();
        switch (mode) {
          case _M.login:
            await sb.auth.signInWithPassword(email: e, password: pw.text);
          case _M.signup:
            final r = await sb.auth.signUp(email: e, password: pw.text, data: {'full_name': name.text.trim(), 'phone': phone.text.trim()});
            if (r.session == null) setState(() { mode = _M.verify; note = 'أرسلنا رمز تأكيد إلى بريدك. أدخله هنا.'; });
          case _M.verify:
            await sb.auth.verifyOTP(email: e, token: code.text.trim(), type: OtpType.signup);
          case _M.forgot:
            await sb.auth.resetPasswordForEmail(e);
            setState(() { mode = _M.reset; note = 'أرسلنا رمزاً إلى بريدك. أدخله مع كلمة المرور الجديدة.'; });
          case _M.reset:
            await sb.auth.verifyOTP(email: e, token: code.text.trim(), type: OtpType.recovery);
            await sb.auth.updateUser(UserAttributes(password: pw.text));
        }
      });

  Widget field(String l, TextEditingController c, {bool obscure = false, TextInputType? type, bool ltr = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, obscureText: obscure, keyboardType: type, textDirection: ltr ? TextDirection.ltr : null, decoration: InputDecoration(labelText: l)),
      );

  @override
  Widget build(BuildContext context) {
    final titles = {_M.login: 'تسجيل الدخول', _M.signup: 'إنشاء حساب', _M.verify: 'تأكيد البريد', _M.forgot: 'استعادة كلمة المرور', _M.reset: 'كلمة مرور جديدة'};
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 12),
          Center(child: ClipOval(child: Image.asset('assets/logo.png', width: 120))),
          const SizedBox(height: 18),
          Center(child: Text(titles[mode]!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          const SizedBox(height: 18),
          if (note != null) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: kAcc.withOpacity(.15), borderRadius: BorderRadius.circular(10)), child: Text(note!)),
          field('البريد الإلكتروني', email, type: TextInputType.emailAddress, ltr: true),
          if (mode == _M.signup) ...[field('الاسم الكامل', name), field('رقم الهاتف', phone, type: TextInputType.phone, ltr: true)],
          if (mode == _M.verify || mode == _M.reset) field('الرمز المرسل إلى بريدك', code, type: TextInputType.number, ltr: true),
          if (mode == _M.login || mode == _M.signup || mode == _M.reset) field(mode == _M.reset ? 'كلمة المرور الجديدة' : 'كلمة المرور', pw, obscure: true, ltr: true),
          const SizedBox(height: 4),
          FilledButton(onPressed: busy ? null : submit, child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(titles[mode]!)),
          const SizedBox(height: 8),
          if (mode == _M.login) ...[
            TextButton(onPressed: () => setState(() { mode = _M.forgot; note = null; }), child: const Text('نسيت كلمة المرور؟')),
            TextButton(onPressed: () => setState(() { mode = _M.signup; note = null; }), child: const Text('ليس لديك حساب؟ أنشئ حساباً')),
          ] else
            TextButton(onPressed: () => setState(() { mode = _M.login; note = null; }), child: const Text('العودة لتسجيل الدخول')),
        ]),
      ),
    );
  }
}
