/// Accepts only addresses at real, well-known mail providers.
///
/// No verification email is sent, so the domain allow-list is what keeps
/// throwaway / fake addresses out. Returns null when valid, otherwise an
/// Arabic error message for the form.
class EmailPolicy {
  EmailPolicy._();

  static final RegExp _shape = RegExp(
      r'^[a-zA-Z0-9](?:[a-zA-Z0-9._%+-]{0,62}[a-zA-Z0-9_%+-])?@([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$');

  /// Exact domains.
  static const Set<String> providers = <String>{
    // Google
    'gmail.com', 'googlemail.com',
    // Microsoft
    'outlook.com', 'outlook.sa', 'outlook.fr', 'hotmail.com', 'hotmail.fr',
    'hotmail.co.uk', 'live.com', 'live.fr', 'msn.com',
    // Yahoo / AOL
    'yahoo.com', 'yahoo.fr', 'yahoo.co.uk', 'yahoo.de', 'yahoo.es',
    'yahoo.it', 'yahoo.ca', 'yahoo.com.br', 'yahoo.co.jp', 'ymail.com',
    'rocketmail.com', 'aol.com',
    // Apple
    'icloud.com', 'me.com', 'mac.com',
    // Privacy-focused
    'proton.me', 'protonmail.com', 'protonmail.ch', 'pm.me',
    'tutanota.com', 'tutanota.de', 'tuta.io', 'tuta.com',
    // Other major providers
    'zoho.com', 'zohomail.com', 'gmx.com', 'gmx.net', 'gmx.de',
    'mail.com', 'yandex.com', 'yandex.ru', 'mail.ru', 'fastmail.com',
    'hey.com', 'web.de', 'orange.fr', 'free.fr', 'libero.it',
  };

  static String? validate(String raw) {
    final String email = raw.trim().toLowerCase();
    if (email.isEmpty) return 'أدخل بريدك الإلكتروني';
    if (!_shape.hasMatch(email)) return 'صيغة البريد الإلكتروني غير صحيحة';
    final String domain = email.substring(email.lastIndexOf('@') + 1);
    if (!providers.contains(domain)) {
      return 'استخدم بريدًا حقيقيًا من Gmail أو Outlook أو Yahoo أو Proton أو iCloud…';
    }
    final String local = email.substring(0, email.lastIndexOf('@'));
    if (local.length < 3) return 'البريد الإلكتروني قصير جدًا';
    return null;
  }

  static String? validatePassword(String p) {
    if (p.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    return null;
  }

  static String? validateName(String n) {
    final String t = n.trim();
    if (t.length < 2) return 'أدخل اسمًا من حرفين على الأقل';
    if (t.length > 24) return 'الاسم طويل جدًا (24 حرفًا كحد أقصى)';
    return null;
  }
}
