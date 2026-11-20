import 'package:flutter/material.dart';

import '../core/app_data.dart';
import '../core/app_theme.dart';
import '../widgets/common.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this);
  int _openFaq = 0;

  static const List<({IconData icon, String title, String sub, String? tag})>
      _contacts = [
    (
      icon: Icons.alternate_email_rounded,
      title: 'راسلنا',
      sub: 'support@animax.tv • الرد خلال 24 ساعة',
      tag: null
    ),
    (
      icon: Icons.chat_bubble_outline_rounded,
      title: 'دردشة مباشرة',
      sub: 'متوسط وقت الرد: دقيقتان',
      tag: 'متصل'
    ),
    (
      icon: Icons.phone_outlined,
      title: 'مركز الاتصال',
      sub: '+1 234 567 890 • 24/7',
      tag: null
    ),
  ];

  static const List<({String name, bool ok})> _services = [
    (name: 'سيرفرات البث', ok: true),
    (name: 'شبكة التوصيل', ok: true),
    (name: 'التحميلات', ok: true),
    (name: 'خدمات الحساب', ok: false),
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  IconBubble(Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  const Text('مركز المساعدة', style: AppText.h3),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TabBar(
              controller: _tabs,
              indicatorColor: AppColors.accent,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.muted,
              labelStyle:
                  const TextStyle(fontFamily: 'Plex', fontSize: 12.5, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Plex', fontSize: 12.5, fontWeight: FontWeight.w500),
              dividerColor: AppColors.stroke,
              tabs: const [
                Tab(text: 'الأسئلة الشائعة'),
                Tab(text: 'اتصل بنا'),
                Tab(text: 'الخدمة'),
                Tab(text: 'الفيديو'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildFaq(),
                  _buildContacts(),
                  _buildServices(),
                  _buildVideos(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaq() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      itemCount: AnimaxData.faqs.length,
      itemBuilder: (BuildContext context, int i) {
        final bool open = _openFaq == i;
        return GestureDetector(
          onTap: () => setState(() => _openFaq = open ? -1 : i),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: open ? Border.all(color: AppColors.accent, width: 1.2) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(AnimaxData.faqs[i]['q']!,
                          style: AppText.bodyBold.copyWith(fontSize: 13)),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.accent),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState:
                      open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(AnimaxData.faqs[i]['a']!, style: AppText.body),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContacts() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        ..._contacts.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(c.icon, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title,
                            style: AppText.bodyBold.copyWith(fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(c.sub, style: AppText.label),
                      ],
                    ),
                  ),
                  if (c.tag != null)
                    Row(
                      children: [
                        Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: AppColors.accent, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(c.tag!,
                            style: AppText.label
                                .copyWith(color: AppColors.accent, fontSize: 10.5)),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            )),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, color: AppColors.accent, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                    'يرد فريق الدعم على كل طلب خلال يوم عمل واحد.',
                    style: AppText.body),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServices() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const Text('حالة الخدمة', style: AppText.h3),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: List<Widget>.generate(_services.length, (int i) {
              final s = _services[i];
              return Column(
                children: [
                  if (i > 0) const Divider(indent: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(s.name,
                                style: AppText.bodyBold.copyWith(fontSize: 13.5))),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: s.ok ? AppColors.accent : AppColors.amber,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.ok ? 'يعمل' : 'صيانة',
                          style: AppText.label.copyWith(
                              color: s.ok ? AppColors.accent : AppColors.amber,
                              fontWeight: FontWeight.w600,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildVideos() {
    // Text-only quick guide — the app carries no bundled artwork or fake
    // tutorials; these steps mirror what the backend actually supports.
    const List<({IconData icon, String title, String body})> steps = [
      (
        icon: Icons.search_rounded,
        title: '1. ابحث عن عمل',
        body:
            'استخدم البحث في الرئيسية أو تصفّح الأقسام. كل ما تراه يُحمَّل مباشرة من المصادر.',
      ),
      (
        icon: Icons.play_circle_outline_rounded,
        title: '2. اختر حلقة',
        body:
            'افتح عنوانًا واضغط على حلقة. يختار المشغّل أفضل سيرفر متاح تلقائيًا.',
      ),
      (
        icon: Icons.dns_rounded,
        title: '3. اختر مترجم / مدبلج',
        body:
            'إذا تعثّر سيرفر، اختر غيره — يتبدّل التشغيل دون مغادرة التطبيق.',
      ),
      (
        icon: Icons.calendar_month_rounded,
        title: '4. تابع الجدول',
        body:
            'يعرض تقويم العرض المواعيد الدقيقة، وتجمع الإشعارات أحدث الحلقات.',
      ),
    ];
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        const Text('البداية', style: AppText.h3),
        const SizedBox(height: 14),
        ...steps.map((s) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(s.icon, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            style: AppText.bodyBold.copyWith(fontSize: 13.5)),
                        const SizedBox(height: 4),
                        Text(s.body, style: AppText.label),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
