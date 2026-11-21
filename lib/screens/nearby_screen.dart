import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/download_manager.dart';
import '../core/nearby_share.dart';
import '../widgets/mb_ui.dart' show kFont, NetImage;

/// Sends a finished download to a nearby phone — no internet needed.
Future<void> openNearbySend(BuildContext context, DownloadItem item) {
  NearbyShare.I.send(item);
  return Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NearbyScreen(sending: true, item: item)));
}

/// Receives a file from a nearby phone.
Future<void> openNearbyReceive(BuildContext context) {
  NearbyShare.I.receive();
  return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NearbyScreen(sending: false)));
}

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.sending, this.item});
  final bool sending;
  final DownloadItem? item;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  @override
  void dispose() {
    final NearbyShare n = NearbyShare.I;
    if (n.phase != NearbyPhase.transferring) n.stop();
    super.dispose();
  }

  static String _mb(int b) => b >= 1 << 30
      ? '${(b / (1 << 30)).toStringAsFixed(2)} ج.ب'
      : '${(b / (1 << 20)).toStringAsFixed(1)} م.ب';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(widget.sending ? 'إرسال لجهاز قريب' : 'استلام من جهاز قريب'),
      ),
      body: ListenableBuilder(
        listenable: NearbyShare.I,
        builder: (BuildContext context, _) {
          final NearbyShare n = NearbyShare.I;
          return ListView(
            padding: const EdgeInsets.all(18),
            children: <Widget>[
              _header(n),
              const SizedBox(height: 18),
              if (n.phase == NearbyPhase.confirm) _confirm(n),
              if (n.phase == NearbyPhase.waiting && !widget.sending) _peers(n),
              if (n.phase == NearbyPhase.transferring || n.phase == NearbyPhase.done)
                _progress(n),
              if (n.message.isNotEmpty && n.phase != NearbyPhase.confirm)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(n.message,
                      key: const Key('nearbyMessage'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: kFont,
                          fontSize: 14.5,
                          height: 1.6,
                          color: n.phase == NearbyPhase.error
                              ? const Color(0xFFFF6B6B)
                              : AppColors.sub)),
                ),
              if (n.phase == NearbyPhase.error)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: () => widget.sending && widget.item != null
                        ? n.send(widget.item!)
                        : n.receive(),
                    child: const Text('حاول مجددًا', style: TextStyle(fontFamily: kFont)),
                  ),
                ),
              if (n.phase == NearbyPhase.done)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('تم', style: TextStyle(fontFamily: kFont)),
                  ),
                ),
              const SizedBox(height: 26),
              const _Tips(),
            ],
          );
        },
      ),
    );
  }

  Widget _header(NearbyShare n) {
    final DownloadItem? it = widget.item;
    return Row(
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(gradient: AppColors.brandGrad, shape: BoxShape.circle),
          child: Icon(widget.sending ? Icons.wifi_tethering_rounded : Icons.radar_rounded,
              color: const Color(0xFF07130D), size: 34),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                  widget.sending
                      ? (it?.title ?? '')
                      : (n.fileTitle.isEmpty ? 'بانتظار ملف' : n.fileTitle),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: kFont,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 4),
              const Text('بدون إنترنت — عبر البلوتوث و Wi-Fi المباشر',
                  style: TextStyle(fontFamily: kFont, fontSize: 12.5, color: AppColors.sub)),
            ],
          ),
        ),
        if (it != null && it.poster.isNotEmpty)
          SizedBox(
              width: 46,
              height: 64,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(6), child: NetImage(it.poster))),
      ],
    );
  }

  Widget _peers(NearbyShare n) {
    if (n.peers.isEmpty) {
      return const Column(
        children: <Widget>[
          SizedBox(height: 20),
          Center(child: CircularProgressIndicator(color: AppColors.brandGreen)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('أجهزة قريبة ترسل الآن — اختر جهاز صديقك:',
            style: TextStyle(fontFamily: kFont, fontSize: 14, color: Colors.white)),
        const SizedBox(height: 8),
        for (final NearbyPeer p in n.peers)
          Card(
            color: AppColors.surface,
            child: ListTile(
              leading: const Icon(Icons.smartphone_rounded, color: AppColors.brandGreen),
              title: Text(p.name,
                  style: const TextStyle(fontFamily: kFont, color: Colors.white)),
              trailing: const Text('استلام',
                  style: TextStyle(fontFamily: kFont, color: AppColors.brandGreen)),
              onTap: () => n.connect(p),
            ),
          ),
      ],
    );
  }

  Widget _confirm(NearbyShare n) {
    return Container(
      key: const Key('nearbyConfirm'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Text('الاتصال بـ ${n.pendingName}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: kFont, fontSize: 15, color: Colors.white)),
          const SizedBox(height: 10),
          const Text('تأكد أن هذا الرمز ظاهر على الجهازين:',
              style: TextStyle(fontFamily: kFont, fontSize: 13, color: AppColors.sub)),
          const SizedBox(height: 6),
          Text(n.code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  fontFamily: kFont,
                  fontSize: 38,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandGreen)),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: n.reject,
                  child: const Text('رفض',
                      style: TextStyle(fontFamily: kFont, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('nearbyAccept'),
                  onPressed: n.accept,
                  child: const Text('قبول', style: TextStyle(fontFamily: kFont)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progress(NearbyShare n) {
    return Column(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: n.total > 0 ? n.fraction : null,
            minHeight: 10,
            color: AppColors.brandGreen,
            backgroundColor: Colors.white12,
          ),
        ),
        const SizedBox(height: 8),
        Text(n.total > 0 ? '${_mb(n.bytes)} / ${_mb(n.total)}' : '',
            style: const TextStyle(fontFamily: kFont, color: AppColors.sub)),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    const TextStyle t = TextStyle(fontFamily: kFont, fontSize: 13, height: 1.7, color: AppColors.muted);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('كيف يعمل؟', style: TextStyle(fontFamily: kFont, fontSize: 14.5, color: Colors.white)),
          SizedBox(height: 6),
          Text('١. المرسل: التحميلات ← ⋮ ← «إرسال لجهاز قريب».', style: t),
          Text('٢. المستلم: التحميلات ← «استلام من جهاز قريب» ثم يختار جهاز المرسل.', style: t),
          Text('٣. تأكدا أن الرمز نفسه ظاهر على الجهازين واضغطا «قبول».', style: t),
          Text('شغّل البلوتوث وابقِ الجهازين قريبين. يعمل بدون إنترنت ولا يستهلك باقتك.', style: t),
        ],
      ),
    );
  }
}
