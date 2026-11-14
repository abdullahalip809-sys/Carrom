import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads.dart';

// ---------------------------------------------------------------------------
// Board constants (sab kuch 800x800 ke "world units" me hai)
// ---------------------------------------------------------------------------
const double boardSize = 800;
const double frameSize = 40;
const double coinR = 15;
const double strikerR = 21;
const double pocketR = 32;
const double pocketInset = 30;
const double wallBounce = 0.78;
const double maxPower = 2600;
const double bottomY = 690;
const double topY = 110;
const double baseMinX = 160;
const double baseMaxX = 640;

const List<Offset> pockets = [
  Offset(pocketInset, pocketInset),
  Offset(boardSize - pocketInset, pocketInset),
  Offset(pocketInset, boardSize - pocketInset),
  Offset(boardSize - pocketInset, boardSize - pocketInset),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const CarromApp());
}

class CarromApp extends StatelessWidget {
  const CarromApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carrom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A5A2F),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _start(BuildContext context, bool vsComputer) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(vsComputer: vsComputer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2B1C10),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'कैरम',
                      style: TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF5D58A),
                      ),
                    ),
                    const Text(
                      'CARROM',
                      style: TextStyle(
                        fontSize: 20,
                        letterSpacing: 8,
                        color: Color(0xFFD9B26B),
                      ),
                    ),
                    const SizedBox(height: 48),
                    FilledButton.icon(
                      onPressed: () => _start(context, true),
                      icon: const Icon(Icons.smart_toy),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('Computer के साथ खेलो'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: () => _start(context, false),
                      icon: const Icon(Icons.people),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('2 Players (दोस्त के साथ)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Physics objects
// ---------------------------------------------------------------------------
enum CoinType { white, black, queen, striker }

class Piece {
  Offset pos;
  Offset vel = Offset.zero;
  final CoinType type;
  final double r;
  final double mass;
  bool active = true;

  Piece(this.pos, this.type)
      : r = type == CoinType.striker ? strikerR : coinR,
        mass = type == CoinType.striker ? 2.0 : 1.0;
}

double distPointSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance;
  final ap = p - a;
  double t = (ap.dx * ab.dx + ap.dy * ab.dy) / len2;
  t = t.clamp(0.0, 1.0).toDouble();
  return (p - (a + ab * t)).distance;
}

enum Phase { placing, moving, over }

class _AiPlan {
  final double x;
  final Offset dir;
  final double power;
  _AiPlan(this.x, this.dir, this.power);
}

// ---------------------------------------------------------------------------
// Game screen
// ---------------------------------------------------------------------------
class GameScreen extends StatefulWidget {
  final bool vsComputer;
  const GameScreen({super.key, required this.vsComputer});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final Random _rnd = Random();
  final InterstitialManager _interstitial = InterstitialManager();
  final RewardedManager _rewarded = RewardedManager();
  final List<bool> rewardUsed = [false, false];

  final List<Piece> coins = [];
  late Piece striker;

  int current = 0; // 0 = White (neeche), 1 = Black (upar)
  Phase phase = Phase.placing;
  double strikerX = 400;
  int queenOwner = -1;
  String message = '';

  Offset? dragStart;
  Offset? dragNow;
  double _scale = 1;

  bool strikerPocketedThisShot = false;
  final List<CoinType> pocketedThisShot = [];
  int _gameId = 0;

  @override
  void initState() {
    super.initState();
    _interstitial.load();
    _rewarded.load();
    _newGame();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _interstitial.dispose();
    _rewarded.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- setup
  void _newGame() {
    _gameId++;
    coins.clear();
    const center = Offset(boardSize / 2, boardSize / 2);
    coins.add(Piece(center, CoinType.queen));
    for (int i = 0; i < 6; i++) {
      final a = pi / 3 * i;
      coins.add(Piece(
        center + Offset(cos(a), sin(a)) * 31.5,
        i.isEven ? CoinType.white : CoinType.black,
      ));
    }
    for (int i = 0; i < 12; i++) {
      final a = pi / 6 * i;
      coins.add(Piece(
        center + Offset(cos(a), sin(a)) * 63,
        i.isEven ? CoinType.black : CoinType.white,
      ));
    }
    striker = Piece(const Offset(400, bottomY), CoinType.striker);
    current = 0;
    queenOwner = -1;
    rewardUsed[0] = false;
    rewardUsed[1] = false;
    phase = Phase.placing;
    message = '';
    dragStart = null;
    dragNow = null;
    strikerPocketedThisShot = false;
    pocketedThisShot.clear();
    _prepareStriker();
  }

  void _prepareStriker() {
    strikerX = 400;
    _placeStriker();
  }

  void _placeStriker() {
    striker.active = true;
    striker.vel = Offset.zero;
    striker.pos = Offset(strikerX, current == 0 ? bottomY : topY);
  }

  bool _strikerBlocked() {
    return coins.any(
      (c) => c.active && (c.pos - striker.pos).distance < c.r + strikerR + 1,
    );
  }

  // ------------------------------------------------------------- game loop
  void _onTick(Duration elapsed) {
    final double dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.034).toDouble();
    _last = elapsed;
    if (phase != Phase.moving) return;

    final int steps = (dt / (1 / 240)).ceil().clamp(1, 12).toInt();
    final double h = dt / steps;
    for (int i = 0; i < steps; i++) {
      _physics(h);
    }
    final stopped = _allStopped();
    if (stopped) {
      _endShot();
    }
    if (mounted) setState(() {});
  }

  bool _allStopped() {
    for (final c in coins) {
      if (c.active && c.vel != Offset.zero) return false;
    }
    if (striker.active && striker.vel != Offset.zero) return false;
    return true;
  }

  void _physics(double h) {
    final all = <Piece>[
      ...coins.where((c) => c.active),
      if (striker.active) striker,
    ];

    for (final p in all) {
      p.pos += p.vel * h;
      p.vel *= exp(-1.6 * h);
      if (p.vel.distance < 6) p.vel = Offset.zero;
    }

    for (final p in all) {
      for (final pk in pockets) {
        if ((p.pos - pk).distance < pocketR - 6) {
          _pocket(p);
          break;
        }
      }
      if (!p.active) continue;

      if (p.pos.dx < p.r) {
        p.pos = Offset(p.r, p.pos.dy);
        p.vel = Offset(-p.vel.dx * wallBounce, p.vel.dy);
      } else if (p.pos.dx > boardSize - p.r) {
        p.pos = Offset(boardSize - p.r, p.pos.dy);
        p.vel = Offset(-p.vel.dx * wallBounce, p.vel.dy);
      }
      if (p.pos.dy < p.r) {
        p.pos = Offset(p.pos.dx, p.r);
        p.vel = Offset(p.vel.dx, -p.vel.dy * wallBounce);
      } else if (p.pos.dy > boardSize - p.r) {
        p.pos = Offset(p.pos.dx, boardSize - p.r);
        p.vel = Offset(p.vel.dx, -p.vel.dy * wallBounce);
      }
    }

    final live = all.where((p) => p.active).toList();
    for (int i = 0; i < live.length; i++) {
      for (int j = i + 1; j < live.length; j++) {
        _collide(live[i], live[j]);
      }
    }
  }

  void _pocket(Piece p) {
    p.active = false;
    p.vel = Offset.zero;
    if (p.type == CoinType.striker) {
      strikerPocketedThisShot = true;
    } else {
      pocketedThisShot.add(p.type);
    }
  }

  void _collide(Piece a, Piece b) {
    final delta = b.pos - a.pos;
    double d = delta.distance;
    final minD = a.r + b.r;
    if (d >= minD) return;
    Offset n;
    if (d < 0.0001) {
      n = const Offset(1, 0);
      d = 0.0001;
    } else {
      n = delta / d;
    }
    final overlap = minD - d;
    final invA = 1 / a.mass;
    final invB = 1 / b.mass;
    final tot = invA + invB;
    a.pos -= n * (overlap * invA / tot);
    b.pos += n * (overlap * invB / tot);

    final rel = a.vel - b.vel;
    final vn = rel.dx * n.dx + rel.dy * n.dy;
    if (vn <= 0) return;
    const e = 0.92;
    final j = (1 + e) * vn / tot;
    a.vel -= n * (j * invA);
    b.vel += n * (j * invB);
  }

  // ------------------------------------------------------------ shot / turn
  void _shoot(Offset dir, double power) {
    striker.vel = dir * power;
    phase = Phase.moving;
    pocketedThisShot.clear();
    strikerPocketedThisShot = false;
    message = '';
  }

  void _endShot() {
    final me = current;
    final myType = me == 0 ? CoinType.white : CoinType.black;
    bool scored = false;
    final notes = <String>[];

    for (final t in pocketedThisShot) {
      if (t == myType) {
        scored = true;
        notes.add('बढ़िया! coin पॉकेट हुआ');
      } else if (t == CoinType.queen) {
        queenOwner = me;
        scored = true;
        notes.add('Queen पॉकेट! +3');
      } else {
        notes.add('सामने वाले का coin पॉकेट हो गया');
      }
    }

    if (strikerPocketedThisShot) {
      scored = false;
      notes.add('Foul! Striker पॉकेट हो गया');
      final own = coins.where((c) => c.type == myType && !c.active).toList();
      if (own.isNotEmpty) {
        _returnToCentre(own.first);
        notes.add('एक coin वापस रखा गया');
      }
      if (pocketedThisShot.contains(CoinType.queen) && queenOwner == me) {
        final q = coins.firstWhere((c) => c.type == CoinType.queen);
        _returnToCentre(q);
        queenOwner = -1;
      }
    }

    final whiteDone =
        coins.where((c) => c.type == CoinType.white).every((c) => !c.active);
    final blackDone =
        coins.where((c) => c.type == CoinType.black).every((c) => !c.active);

    int? winner;
    final meDone = me == 0 ? whiteDone : blackDone;
    final otherDone = me == 0 ? blackDone : whiteDone;
    if (meDone) {
      winner = me;
    } else if (otherDone) {
      winner = 1 - me;
    }

    if (winner != null) {
      message = notes.join(' • ');
      _gameOver(winner);
      return;
    }

    if (!scored) current = 1 - current;
    message = notes.join(' • ');
    phase = Phase.placing;
    _prepareStriker();
    _scheduleAi();
  }

  void _returnToCentre(Piece c) {
    const center = Offset(boardSize / 2, boardSize / 2);
    for (int k = 0; k < 60; k++) {
      final cand = center + Offset(cos(k * 2.4), sin(k * 2.4)) * (k * 4.0);
      final free = coins.every(
        (o) => o == c || !o.active || (o.pos - cand).distance >= o.r + c.r + 1,
      );
      if (free) {
        c.pos = cand;
        c.vel = Offset.zero;
        c.active = true;
        return;
      }
    }
    c.pos = center;
    c.vel = Offset.zero;
    c.active = true;
  }

  // ------------------------------------------------------------------ input
  void _panEnd() {
    if (dragStart == null || dragNow == null) return;
    final v = (dragStart! - dragNow!) / _scale;
    final len = v.distance;
    dragStart = null;
    dragNow = null;
    if (len < 10) {
      setState(() {});
      return;
    }
    if (_strikerBlocked()) {
      setState(() => message = 'Striker किसी coin पर है — slider से हिलाओ');
      return;
    }
    final power = (len / 200).clamp(0.12, 1.0).toDouble() * maxPower;
    setState(() => _shoot(v / len, power));
  }

  // --------------------------------------------------------------------- AI
  void _scheduleAi() {
    if (!widget.vsComputer || current != 1 || phase != Phase.placing) return;
    final id = _gameId;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || id != _gameId || phase != Phase.placing || current != 1) {
        return;
      }
      final plan = _planAi();
      setState(() {
        strikerX = plan.x;
        _placeStriker();
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted ||
            id != _gameId ||
            phase != Phase.placing ||
            current != 1) {
          return;
        }
        setState(() => _shoot(plan.dir, plan.power));
      });
    });
  }

  _AiPlan _planAi() {
    final targets = coins
        .where((c) =>
            c.active && (c.type == CoinType.black || c.type == CoinType.queen))
        .toList();

    double bestScore = -1e9;
    _AiPlan? best;

    for (double x = 170; x <= 630; x += 20) {
      final sp = Offset(x, topY);
      final blocked = coins.any(
        (c) => c.active && (c.pos - sp).distance < c.r + strikerR + 1,
      );
      if (blocked) continue;

      for (final t in targets) {
        for (final pk in pockets) {
          final tp = pk - t.pos;
          final dTP = tp.distance;
          if (dTP < 1) continue;
          final u = tp / dTP;
          final ghost = t.pos - u * (coinR + strikerR);
          if (ghost.dx < strikerR ||
              ghost.dx > boardSize - strikerR ||
              ghost.dy < strikerR ||
              ghost.dy > boardSize - strikerR) {
            continue;
          }
          final aim = ghost - sp;
          final dA = aim.distance;
          if (dA < 1) continue;
          final a = aim / dA;
          final cosA = a.dx * u.dx + a.dy * u.dy;
          if (cosA < 0.35) continue;

          bool clear = true;
          for (final o in coins) {
            if (!o.active || o == t) continue;
            if (distPointSeg(o.pos, sp, ghost) < coinR + strikerR - 2 ||
                distPointSeg(o.pos, t.pos, pk) < 2 * coinR - 2) {
              clear = false;
              break;
            }
          }
          if (!clear) continue;

          final score = cosA * 2 -
              (dA + dTP) / 1600 +
              (t.type == CoinType.queen ? 0.1 : 0);
          if (score > bestScore) {
            bestScore = score;
            final noise = (_rnd.nextDouble() - 0.5) * 0.05;
            final dir = Offset(
              a.dx * cos(noise) - a.dy * sin(noise),
              a.dx * sin(noise) + a.dy * cos(noise),
            );
            final power = (700 + (dA + dTP) * 1.9).clamp(900.0, 2400.0);
            best = _AiPlan(x, dir, power.toDouble());
          }
        }
      }
    }

    if (best != null) return best;

    final x = 300 + _rnd.nextDouble() * 200;
    final d = Offset((_rnd.nextDouble() - 0.5) * 0.5, 1);
    return _AiPlan(x, d / d.distance, 1500);
  }

  // ---------------------------------------------------------- rewarded video
  void _watchVideoForCoin() {
    if (phase != Phase.placing || rewardUsed[current]) return;
    _rewarded.show(
      onReward: _giveFreeCoin,
      onUnavailable: () {
        if (mounted) {
          setState(() => message = 'Video अभी तैयार नहीं है, थोड़ी देर बाद कोशिश करो');
        }
      },
    );
  }

  void _giveFreeCoin() {
    if (!mounted || phase != Phase.placing) return;
    final me = current;
    final myType = me == 0 ? CoinType.white : CoinType.black;
    final own = coins.where((c) => c.type == myType && c.active).toList();
    if (own.isEmpty) return;
    final coin = own[_rnd.nextInt(own.length)];
    coin.active = false;
    coin.vel = Offset.zero;
    rewardUsed[me] = true;
    final allDone =
        coins.where((c) => c.type == myType).every((c) => !c.active);
    setState(() {
      message = '🎁 Video का इनाम: आपका एक coin पॉकेट हो गया!';
      if (allDone) _gameOver(me);
    });
  }

  // --------------------------------------------------------------- game over
  void _gameOver(int winner) {
    phase = Phase.over;
    final vs = widget.vsComputer;
    final title = vs
        ? (winner == 0 ? '🎉 आप जीत गए!' : 'Computer जीत गया')
        : (winner == 0 ? '🎉 Player 1 (White) जीता!' : '🎉 Player 2 (Black) जीता!');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: const Text('खेल खत्म हुआ। दोबारा खेलोगे?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _interstitial.show(onDone: () {
                  if (mounted) Navigator.of(context).pop();
                });
              },
              child: const Text('Menu'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _interstitial.show(onDone: () {
                  if (mounted) setState(_newGame);
                });
              },
              child: const Text('फिर खेलो'),
            ),
          ],
        ),
      );
    });
  }

  // ------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final vs = widget.vsComputer;
    final canShoot = phase == Phase.placing && (!vs || current == 0);
    final whiteOut =
        coins.where((c) => c.type == CoinType.white && !c.active).length;
    final blackOut =
        coins.where((c) => c.type == CoinType.black && !c.active).length;
    final p1 = vs ? 'आप (White)' : 'Player 1 (White)';
    final p2 = vs ? 'Computer (Black)' : 'Player 2 (Black)';

    String status;
    if (phase == Phase.moving) {
      status = '';
    } else if (phase == Phase.over) {
      status = 'खेल खत्म';
    } else if (vs && current == 1) {
      status = 'Computer सोच रहा है…';
    } else {
      status = '${current == 0 ? p1 : p2} की बारी';
    }

    Offset? aimDir;
    double aimPower = 0;
    if (dragStart != null && dragNow != null) {
      final v = (dragStart! - dragNow!) / _scale;
      final len = v.distance;
      if (len > 6) {
        aimDir = v / len;
        aimPower = (len / 200).clamp(0.0, 1.0).toDouble();
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF2B1C10),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '$p1: $whiteOut/9   •   $p2: $blackOut/9',
                          style: const TextStyle(fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          status,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF5D58A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(_newGame),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 20,
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final side = min(c.maxWidth, c.maxHeight);
                  _scale = side / (boardSize + 2 * frameSize);
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: GestureDetector(
                        onPanStart: canShoot
                            ? (d) => setState(() {
                                  dragStart = d.localPosition;
                                  dragNow = d.localPosition;
                                })
                            : null,
                        onPanUpdate: canShoot
                            ? (d) => setState(() {
                                  dragNow = d.localPosition;
                                })
                            : null,
                        onPanEnd: canShoot ? (_) => _panEnd() : null,
                        onPanCancel: canShoot
                            ? () => setState(() {
                                  dragStart = null;
                                  dragNow = null;
                                })
                            : null,
                        child: CustomPaint(
                          size: Size(side, side),
                          painter: BoardPainter(
                            coins: coins,
                            striker: striker,
                            aimDir: aimDir,
                            aimPower: aimPower,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Slider(
                    min: baseMinX,
                    max: baseMaxX,
                    value: strikerX.clamp(baseMinX, baseMaxX).toDouble(),
                    onChanged: canShoot
                        ? (v) => setState(() {
                              strikerX = v;
                              _placeStriker();
                            })
                        : null,
                  ),
                  Text(
                    canShoot
                        ? 'Slider से striker रखो → फिर board पर पीछे खींचकर छोड़ो'
                        : ' ',
                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                  ),
                  TextButton.icon(
                    onPressed: (canShoot && !rewardUsed[current])
                        ? _watchVideoForCoin
                        : null,
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    label: const Text('Video देखो → 1 coin फ्री'),
                  ),
                ],
              ),
            ),
            const BannerAdWidget(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------
class BoardPainter extends CustomPainter {
  final List<Piece> coins;
  final Piece striker;
  final Offset? aimDir;
  final double aimPower;

  BoardPainter({
    required this.coins,
    required this.striker,
    required this.aimDir,
    required this.aimPower,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / (boardSize + 2 * frameSize);
    canvas.scale(s);

    // Wooden frame
    const total = boardSize + 2 * frameSize;
    final frameRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, total, total),
      const Radius.circular(28),
    );
    canvas.drawRRect(frameRect, Paint()..color = const Color(0xFF6B4423));
    canvas.drawRRect(
      frameRect.deflate(6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF8A5A2F),
    );

    canvas.translate(frameSize, frameSize);

    // Playing surface
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, boardSize, boardSize),
      Paint()..color = const Color(0xFFEBCB8B),
    );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF5A3A1A);

    // Baselines (4 sides) + end circles
    const lo = topY;
    const hi = bottomY;
    canvas.drawLine(const Offset(baseMinX, lo), const Offset(baseMaxX, lo), line);
    canvas.drawLine(const Offset(baseMinX, hi), const Offset(baseMaxX, hi), line);
    canvas.drawLine(const Offset(lo, baseMinX), const Offset(lo, baseMaxX), line);
    canvas.drawLine(const Offset(hi, baseMinX), const Offset(hi, baseMaxX), line);
    final dot = Paint()..color = const Color(0xFFB03A2E);
    for (final y in [lo, hi]) {
      for (final x in [baseMinX, baseMaxX]) {
        canvas.drawCircle(Offset(x, y), 17, dot);
        canvas.drawCircle(Offset(x, y), 17, line);
        canvas.drawCircle(Offset(y, x), 17, dot);
        canvas.drawCircle(Offset(y, x), 17, line);
      }
    }

    // Centre circles
    const c = Offset(boardSize / 2, boardSize / 2);
    canvas.drawCircle(c, 95, line);
    canvas.drawCircle(c, 22, line);

    // Pockets
    for (final p in pockets) {
      canvas.drawCircle(p, pocketR, Paint()..color = const Color(0xFF111111));
      canvas.drawCircle(
        p,
        pocketR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF3A2A1A),
      );
    }

    // Aim guide
    if (aimDir != null && striker.active) {
      final guide = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withAlpha(200);
      final end = striker.pos + aimDir! * (80 + 320 * aimPower);
      canvas.drawLine(striker.pos, end, guide);
      canvas.drawCircle(end, 6, Paint()..color = Colors.white.withAlpha(200));
      final pull = Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(Colors.yellow, Colors.red, aimPower)!;
      canvas.drawLine(
        striker.pos,
        striker.pos - aimDir! * (20 + 90 * aimPower),
        pull,
      );
    }

    // Coins + striker
    for (final p in coins) {
      if (p.active) _drawPiece(canvas, p);
    }
    if (striker.active) _drawPiece(canvas, striker);
  }

  void _drawPiece(Canvas canvas, Piece p) {
    canvas.drawCircle(
      p.pos + const Offset(2, 3),
      p.r,
      Paint()..color = Colors.black.withAlpha(70),
    );
    Color fill;
    Color ring;
    if (p.type == CoinType.white) {
      fill = const Color(0xFFF7F1E3);
      ring = const Color(0xFFB9A98A);
    } else if (p.type == CoinType.black) {
      fill = const Color(0xFF222222);
      ring = const Color(0xFF666666);
    } else if (p.type == CoinType.queen) {
      fill = const Color(0xFFC0392B);
      ring = const Color(0xFF7B241C);
    } else {
      fill = const Color(0xFF2E86DE);
      ring = Colors.white;
    }
    canvas.drawCircle(p.pos, p.r, Paint()..color = fill);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ring;
    canvas.drawCircle(p.pos, p.r, stroke);
    canvas.drawCircle(p.pos, p.r * 0.62, stroke);
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
