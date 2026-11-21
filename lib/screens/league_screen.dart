import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/cloud.dart';
import '../core/social.dart';
import '../widgets/mb_ui.dart' show kFont;
import '../widgets/social_bar.dart' show UserAvatar;
import 'auth_screen.dart';
import 'user_profile_screen.dart';

/// Weekly Bingo league: you vs the people you follow, plus the top players
/// of the week. Points: 1 per goal, 3 per bingo line, 5 per full card.
/// Cards and scores reset every Monday.
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  late Future<List<LeagueRow>> _friends = League.friends();
  late Future<List<LeagueRow>> _top = League.top();

  Future<void> _refresh() async {
    setState(() {
      _friends = League.friends();
      _top = League.top();
    });
    await Future.wait(<Future<dynamic>>[_friends, _top]);
  }

  @override
  Widget build(BuildContext context) {
    final Duration left = BingoStore.weekEnds(DateTime.now())
        .difference(DateTime.now().toUtc());
    final String ends = left.inDays >= 1
        ? 'ينتهي الأسبوع بعد ${left.inDays} يوم'
        : 'ينتهي الأسبوع بعد ${left.inHours} ساعة';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          title: const Text('دوري البينغو الأسبوعي'),
          bottom: const TabBar(
            labelStyle: TextStyle(
              fontFamily: kFont,
              fontWeight: FontWeight.w700,
            ),
            indicatorColor: AppColors.brandGreen,
            tabs: <Widget>[
              Tab(text: 'أنا ومن أتابعهم'),
              Tab(text: 'الأفضل هذا الأسبوع'),
            ],
          ),
        ),
        body: !CloudAuth.I.signedIn
            ? Center(
                child: FilledButton(
                  onPressed: () async {
                    if (await requireLogin(context)) _refresh();
                  },
                  child: const Text(
                    'سجّل الدخول للانضمام للدوري',
                    style: TextStyle(fontFamily: kFont),
                  ),
                ),
              )
            : Column(
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGrad,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListenableBuilder(
                      listenable: BingoStore.I,
                      builder: (BuildContext context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'نقاطك هذا الأسبوع: ${BingoStore.I.score}',
                            key: const Key('myLeagueScore'),
                            style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF07130D),
                            ),
                          ),
                          Text(
                            '$ends · هدف = 1 · بينغو = 3 · بطاقة كاملة = 5',
                            style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 12.5,
                              color: Color(0xFF07130D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _list(
                          _friends,
                          empty: 'تابع أصدقاءك لتنافسهم هنا — كل متابَع يظهر في جدولك.',
                        ),
                        _list(
                          _top,
                          empty: 'لا يوجد لاعبون هذا الأسبوع بعد — كن الأول!',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _list(Future<List<LeagueRow>> f, {required String empty}) {
    final String me = CloudAuth.I.user?.uid ?? '';
    return RefreshIndicator(
      color: AppColors.brandGreen,
      onRefresh: _refresh,
      child: FutureBuilder<List<LeagueRow>>(
        future: f,
        builder: (BuildContext context, AsyncSnapshot<List<LeagueRow>> s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brandGreen),
            );
          }
          if (s.hasError) {
            return ListView(
              children: const <Widget>[
                SizedBox(height: 120),
                Center(
                  child: Text(
                    'تعذّر تحميل الجدول — اسحب للتحديث.',
                    style: TextStyle(fontFamily: kFont, color: AppColors.sub),
                  ),
                ),
              ],
            );
          }
          final List<LeagueRow> rows = s.data ?? const <LeagueRow>[];
          if (rows.isEmpty ||
              (rows.length == 1 &&
                  rows.first.uid == me &&
                  rows.first.score == 0)) {
            return ListView(
              children: <Widget>[
                const SizedBox(height: 120),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    empty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 15,
                      color: AppColors.sub,
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
            itemCount: rows.length,
            itemBuilder: (BuildContext c, int i) {
              final LeagueRow r = rows[i];
              final bool isMe = r.uid == me;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppColors.brandGreen.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => openUserProfile(c, r.uid),
                  leading: SizedBox(
                    width: 84,
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 34,
                          child: Text(
                            i < 3 ? <String>['🥇', '🥈', '🥉'][i] : '${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: kFont,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        UserAvatar(name: r.name, size: 40),
                      ],
                    ),
                  ),
                  title: Text(
                    isMe ? '${r.name} (أنت)' : r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kFont,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    '${r.goals}/9 أهداف · ${r.lines} بينغو',
                    style: const TextStyle(
                      fontFamily: kFont,
                      color: AppColors.sub,
                    ),
                  ),
                  trailing: Text(
                    '${r.score}',
                    style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandGreen,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
