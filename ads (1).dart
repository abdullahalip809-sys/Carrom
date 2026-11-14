import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Apni AdMob IDs (Android). Testing ke waqt `useTestAds = true` kar do,
/// taaki galti se apne asli ads par click na ho.
class AdIds {
  static const bool useTestAds = false;

  static String get banner {
    if (useTestAds || !Platform.isAndroid) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return 'ca-app-pub-2742278117330941/7106980071';
  }

  static String get interstitial {
    if (useTestAds || !Platform.isAndroid) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return 'ca-app-pub-2742278117330941/2233927347';
  }

  static String get rewarded {
    if (useTestAds || !Platform.isAndroid) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    return 'ca-app-pub-2742278117330941/7348467317';
  }
}

/// Rewarded video ad manager.
class RewardedManager {
  RewardedAd? _ad;
  bool _loading = false;

  bool get isReady => _ad != null;

  void load() {
    if (_loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// Video dikhata hai. Poora dekhne par [onReward] chalta hai.
  /// Ad ready na ho to [onUnavailable] chalta hai.
  void show({required VoidCallback onReward, VoidCallback? onUnavailable}) {
    final ad = _ad;
    if (ad == null) {
      load();
      onUnavailable?.call();
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        load();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _ad = null;
        load();
        onUnavailable?.call();
      },
    );
    _ad = null;
    ad.show(onUserEarnedReward: (adWithoutView, reward) => onReward());
  }

  void dispose() => _ad?.dispose();
}

/// Full-screen (interstitial) ad manager.
class InterstitialManager {
  InterstitialAd? _ad;
  bool _loading = false;

  void load() {
    if (_loading || _ad != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// Ad dikhata hai. Ad band hone par (ya ad na mile to) [onDone] chalta hai.
  void show({VoidCallback? onDone}) {
    final ad = _ad;
    if (ad == null) {
      load();
      onDone?.call();
      return;
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        load();
        onDone?.call();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _ad = null;
        load();
        onDone?.call();
      },
    );
    _ad = null;
    ad.show();
  }

  void dispose() => _ad?.dispose();
}

/// Neeche dikhne wala banner ad.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox(height: 50);
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
