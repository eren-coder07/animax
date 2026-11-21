import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent palettes selectable in Settings → Appearance.
class AccentTheme {
  const AccentTheme(this.key, this.name, this.color, this.deep, this.ink);

  final String key;
  final String name;
  final Color color;
  final Color deep;
  final Color ink;

  static const AccentTheme green = AccentTheme('green', 'أخضر نيون',
      Color(0xFF2EE58B), Color(0xFF1FC8EE), Color(0xFF06130A));
  static const AccentTheme red = AccentTheme('red', 'أحمر سينمائي',
      Color(0xFFE50914), Color(0xFF8E0A0F), Color(0xFFFFFFFF));
  static const AccentTheme purple = AccentTheme('purple', 'بنفسجي',
      Color(0xFF8B5CF6), Color(0xFF5B2EC5), Color(0xFFFFFFFF));
  static const AccentTheme blue = AccentTheme('blue', 'أزرق المحيط',
      Color(0xFF2E90FA), Color(0xFF1D5FB8), Color(0xFFFFFFFF));
  static const AccentTheme pink = AccentTheme('pink', 'وردي ساكورا',
      Color(0xFFF0428C), Color(0xFFB0235E), Color(0xFFFFFFFF));

  static const List<AccentTheme> all = <AccentTheme>[
    green, red, purple, blue, pink,
  ];

  static const AccentTheme def = green;

  static AccentTheme byKey(String key) {
    for (final AccentTheme a in all) {
      if (a.key == key) return a;
    }
    return def;
  }
}

/// Reactive app-wide preferences (SharedPreferences-backed, change-notifying).
///
/// One singleton ([AppPrefs.I]) serves every screen so toggles like accent
/// color or data-saver apply instantly through [ListenableBuilder].
class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs I = AppPrefs._();

  SharedPreferences? _sp;
  bool _loaded = false;

  // ---- Appearance --------------------------------------------------------
  String accentKey = AccentTheme.def.key;
  bool amoled = false; // true-black backgrounds (OLED battery saver)

  // ---- Playback ----------------------------------------------------------
  bool dataSaver = false; // caps manga images + warns on cellular
  bool downloadWifiOnly = false; // downloads wait for Wi-Fi
  String defaultQuality = 'auto'; // auto | 1080 | 720 | 480 | 360
  bool autoPlayNext = true;
  bool autoSkipIntro = false;
  bool bingeMode = false; // marathon: countdown auto-next + skip intros
  bool timedComments = true; // comments pinned to moments float over video
  bool spoilerShield = true; // blur clips/comments past your progress
  bool audioOnly = false; // players: sound only (smallest stream, background)
  int dataBudgetMb = 0; // monthly mobile-data budget, 0 = off
  bool cloudSync = true; // list / progress / history follow the account
  double readerScrollSpeed = 1.0; // auto-scroll speed multiplier
  int skipIntroSeconds = 85;
  bool pauseOnBackground = true;
  String cinemaProvider = ''; // '' = auto (first working provider)

  // ---- Reader ------------------------------------------------------------
  /// Arabic first; chapters fall back to English when none exist.
  String mangaLanguage = 'ar';
  String readerMode = 'vertical'; // vertical | paged
  bool readerRtl = true; // paged mode reading direction
  bool readerDataSaver = false;
  String readerBg = 'black'; // black | white | gray

  // ---- Notifications / misc ---------------------------------------------
  String lastSeenVersion = ''; // drives the What's-new dialog
  bool navBadges = true;

  /// Completes after [load] finished (awaited by the splash screen).
  Future<void> get ready => _completer.future;
  final Completer<void> _completer = Completer<void>();

  Future<void> load() async {
    if (_loaded) return;
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      _sp = sp;
      accentKey = sp.getString('pref.accent') ?? accentKey;
      amoled = sp.getBool('pref.amoled') ?? amoled;
      dataSaver = sp.getBool('pref.dataSaver') ?? dataSaver;
      downloadWifiOnly = sp.getBool('pref.dlWifiOnly') ?? downloadWifiOnly;
      defaultQuality = sp.getString('pref.defaultQuality') ?? defaultQuality;
      autoPlayNext = sp.getBool('pref.autoPlayNext') ?? autoPlayNext;
      autoSkipIntro = sp.getBool('pref.autoSkipIntro') ?? autoSkipIntro;
      bingeMode = sp.getBool('pref.bingeMode') ?? bingeMode;
      timedComments = sp.getBool('pref.timedComments') ?? timedComments;
      spoilerShield = sp.getBool('pref.spoilerShield') ?? spoilerShield;
      audioOnly = sp.getBool('pref.audioOnly') ?? audioOnly;
      dataBudgetMb = sp.getInt('pref.dataBudgetMb') ?? dataBudgetMb;
      cloudSync = sp.getBool('pref.cloudSync') ?? cloudSync;
      readerScrollSpeed = sp.getDouble('pref.readerScrollSpeed') ?? readerScrollSpeed;
      skipIntroSeconds = sp.getInt('pref.skipIntroSec') ?? skipIntroSeconds;
      pauseOnBackground = sp.getBool('pref.pauseOnBg') ?? pauseOnBackground;
      cinemaProvider = sp.getString('pref.cinemaProvider') ?? '';
      mangaLanguage = sp.getString('pref.mangaLang') ?? mangaLanguage;
      readerMode = sp.getString('pref.readerMode') ?? readerMode;
      readerRtl = sp.getBool('pref.readerRtl') ?? readerRtl;
      readerDataSaver = sp.getBool('pref.readerDataSaver') ?? readerDataSaver;
      readerBg = sp.getString('pref.readerBg') ?? readerBg;
      lastSeenVersion = sp.getString('pref.lastSeenVersion') ?? '';
      navBadges = sp.getBool('pref.navBadges') ?? navBadges;
    } catch (_) {
      // Corrupt or missing prefs fall back to defaults.
    }
    _loaded = true;
    _completer.complete();
    notifyListeners();
  }

  AccentTheme get accent => AccentTheme.byKey(accentKey);

  void set(String key, Object value) {
    final SharedPreferences? sp = _sp;
    switch (key) {
      case 'accent':
        accentKey = value as String;
        sp?.setString('pref.accent', accentKey);
        break;
      case 'amoled':
        amoled = value as bool;
        sp?.setBool('pref.amoled', amoled);
        break;
      case 'dataSaver':
        dataSaver = value as bool;
        sp?.setBool('pref.dataSaver', dataSaver);
        break;
      case 'downloadWifiOnly':
        downloadWifiOnly = value as bool;
        sp?.setBool('pref.dlWifiOnly', downloadWifiOnly);
        break;
      case 'defaultQuality':
        defaultQuality = value as String;
        sp?.setString('pref.defaultQuality', defaultQuality);
        break;
      case 'autoPlayNext':
        autoPlayNext = value as bool;
        sp?.setBool('pref.autoPlayNext', autoPlayNext);
        break;
      case 'bingeMode':
        bingeMode = value as bool;
        sp?.setBool('pref.bingeMode', bingeMode);
        break;
      case 'timedComments':
        timedComments = value as bool;
        sp?.setBool('pref.timedComments', timedComments);
        break;
      case 'spoilerShield':
        spoilerShield = value as bool;
        sp?.setBool('pref.spoilerShield', spoilerShield);
        break;
      case 'audioOnly':
        audioOnly = value as bool;
        sp?.setBool('pref.audioOnly', audioOnly);
        break;
      case 'dataBudgetMb':
        dataBudgetMb = value as int;
        sp?.setInt('pref.dataBudgetMb', dataBudgetMb);
        break;
      case 'cloudSync':
        cloudSync = value as bool;
        sp?.setBool('pref.cloudSync', cloudSync);
        break;
      case 'readerScrollSpeed':
        readerScrollSpeed = value as double;
        sp?.setDouble('pref.readerScrollSpeed', readerScrollSpeed);
        break;
      case 'autoSkipIntro':
        autoSkipIntro = value as bool;
        sp?.setBool('pref.autoSkipIntro', autoSkipIntro);
        break;
      case 'skipIntroSec':
        skipIntroSeconds = value as int;
        sp?.setInt('pref.skipIntroSec', skipIntroSeconds);
        break;
      case 'pauseOnBackground':
        pauseOnBackground = value as bool;
        sp?.setBool('pref.pauseOnBg', pauseOnBackground);
        break;
      case 'cinemaProvider':
        cinemaProvider = value as String;
        sp?.setString('pref.cinemaProvider', cinemaProvider);
        break;
      case 'mangaLanguage':
        mangaLanguage = value as String;
        sp?.setString('pref.mangaLang', mangaLanguage);
        break;
      case 'readerMode':
        readerMode = value as String;
        sp?.setString('pref.readerMode', readerMode);
        break;
      case 'readerRtl':
        readerRtl = value as bool;
        sp?.setBool('pref.readerRtl', readerRtl);
        break;
      case 'readerDataSaver':
        readerDataSaver = value as bool;
        sp?.setBool('pref.readerDataSaver', readerDataSaver);
        break;
      case 'readerBg':
        readerBg = value as String;
        sp?.setString('pref.readerBg', readerBg);
        break;
      case 'lastSeenVersion':
        lastSeenVersion = value as String;
        sp?.setString('pref.lastSeenVersion', lastSeenVersion);
        break;
      case 'navBadges':
        navBadges = value as bool;
        sp?.setBool('pref.navBadges', navBadges);
        break;
    }
    notifyListeners();
  }
}
