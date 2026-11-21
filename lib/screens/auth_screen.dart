import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/email_policy.dart';
import '../core/social.dart';
import '../widgets/animax_logo.dart';
import '../widgets/mb_ui.dart';

/// Opens the login screen when needed; returns true when signed in.
Future<bool> requireLogin(BuildContext context) async {
  if (CloudAuth.I.signedIn) return true;
  final bool? ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
  return ok == true && CloudAuth.I.signedIn;
}

/// Login / create account (email + password, real providers only,
/// no verification email).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false});
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _register = widget.register;
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await CloudAuth.I.register(_email.text, _pass.text, _name.text);
      } else {
        await CloudAuth.I.signIn(_email.text, _pass.text);
      }
      await Social.ensureProfile();
      await BingoStore.I.load();
      if (mounted) Navigator.of(context).pop(true);
    } on CloudException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: kFont, fontSize: 15, color: AppColors.muted),
        prefixIcon: Icon(icon, color: AppColors.sub),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.surfaceHi,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppColors.brandGreen, width: 1.2)),
        errorStyle: const TextStyle(fontFamily: kFont, fontSize: 12.5),
      );

  @override
  Widget build(BuildContext context) {
    const TextStyle field =
        TextStyle(fontFamily: kFont, fontSize: 15.5, color: Colors.white);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: AppColors.bg),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 30),
            children: <Widget>[
              const Center(child: AnimaxLogo(size: 64)),
              const SizedBox(height: 14),
              Text(_register ? 'إنشاء حساب' : 'تسجيل الدخول',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 6),
              const Text(
                  'للإعجاب والتعليق والمتابعة وصنع المقاطع ومشاركتها',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: kFont, fontSize: 14, color: AppColors.sub)),
              const SizedBox(height: 26),
              if (_register) ...<Widget>[
                TextFormField(
                  controller: _name,
                  style: field,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => EmailPolicy.validateName(v ?? ''),
                  decoration: _dec('الاسم الظاهر', Icons.person_outline_rounded),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                style: field,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                validator: (String? v) => EmailPolicy.validate(v ?? ''),
                decoration: _dec('البريد الإلكتروني (Gmail, Outlook…)',
                    Icons.alternate_email_rounded),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pass,
                style: field,
                obscureText: _hide,
                textDirection: TextDirection.ltr,
                onFieldSubmitted: (_) => _submit(),
                validator: (String? v) =>
                    EmailPolicy.validatePassword(v ?? ''),
                decoration: _dec('كلمة المرور', Icons.lock_outline_rounded,
                    suffix: IconButton(
                      icon: Icon(
                          _hide
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.sub),
                      onPressed: () => setState(() => _hide = !_hide),
                    )),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.badge.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 14,
                          color: Color(0xFFFF8A8F))),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: _busy
                      ? 'لحظة…'
                      : (_register ? 'إنشاء الحساب' : 'دخول'),
                  height: 52,
                  expand: true,
                  onTap: _busy ? null : _submit,
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(
                    _register
                        ? 'لديك حساب؟ سجّل الدخول'
                        : 'ليس لديك حساب؟ أنشئ حسابًا مجانًا',
                    style: const TextStyle(
                        fontFamily: kFont,
                        fontSize: 15,
                        color: AppColors.brandGreen)),
              ),
              const SizedBox(height: 8),
              const Text(
                  'نقبل البريد من مزودين حقيقيين فقط: Gmail · Outlook/Hotmail · Yahoo · iCloud · Proton · Zoho · GMX وغيرها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: kFont, fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
