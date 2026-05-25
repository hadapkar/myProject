import "dart:async";
import "dart:math";

import "package:flutter/material.dart";

import "funtarget_assets.dart";

class FunTargetStage extends StatelessWidget {
  static const double designWidth = 1024;
  static const double designHeight = 768;
  static const double heightScale = 0.7;

  final String email;
  final int timeLeftSeconds;
  final double score;
  final double totalBetAmount;
  final double winnerAmount;
  final List<int> last10;

  final int selectedChip;
  final void Function(int chip) onChipSelected;
  final Map<int, int> betsByNumber;
  final int? highlightedBetNumber;
  final bool betNumbersDisabled;
  final void Function(int number) onBetNumberPressed;

  final bool isSpinning;
  final double wheelRotationDegrees;
  final Duration wheelSpinDuration;
  final Curve wheelSpinCurve;

  final bool betOkBlink;
  final bool betOkDisabled;
  final bool takeBlink;
  final bool showPrevBet;

  final VoidCallback onTake;
  final VoidCallback onCancelBet;
  final VoidCallback onCancelSpecific;
  final VoidCallback onBetOk;
  final VoidCallback onPrevBet;
  final VoidCallback onExit;

  final String footerMessage;

  const FunTargetStage({
    super.key,
    required this.email,
    required this.timeLeftSeconds,
    required this.score,
    required this.totalBetAmount,
    required this.winnerAmount,
    required this.last10,
    required this.selectedChip,
    required this.onChipSelected,
    required this.betsByNumber,
    required this.highlightedBetNumber,
    required this.betNumbersDisabled,
    required this.onBetNumberPressed,
    required this.isSpinning,
    required this.wheelRotationDegrees,
    required this.wheelSpinDuration,
    required this.wheelSpinCurve,
    required this.betOkBlink,
    required this.betOkDisabled,
    required this.takeBlink,
    required this.showPrevBet,
    required this.onTake,
    required this.onCancelBet,
    required this.onCancelSpecific,
    required this.onBetOk,
    required this.onPrevBet,
    required this.onExit,
    required this.footerMessage,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : designWidth;
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (designHeight * heightScale);

        final scaleW = maxWidth / designWidth;
        final scaleH = maxHeight / (designHeight * heightScale);
        final scale = min(scaleW, scaleH);

        final outerWidth = designWidth * scale;
        final outerHeight = designHeight * scale * heightScale;

        return SizedBox(
          width: outerWidth,
          height: outerHeight,
          child: Align(
            alignment: Alignment.center,
            child: Transform(
              alignment: Alignment.topCenter,
              transform: Matrix4.diagonal3Values(scale, scale * heightScale, 1),
              child: SizedBox(
                width: designWidth,
                height: designHeight,
                child: _StageBody(
                  email: email,
                  timeLeftSeconds: timeLeftSeconds,
                  score: score,
                  totalBetAmount: totalBetAmount,
                  winnerAmount: winnerAmount,
                  last10: last10,
                  selectedChip: selectedChip,
                  onChipSelected: onChipSelected,
                  betsByNumber: betsByNumber,
                  highlightedBetNumber: highlightedBetNumber,
                  betNumbersDisabled: betNumbersDisabled,
                  onBetNumberPressed: onBetNumberPressed,
                  isSpinning: isSpinning,
                  wheelRotationDegrees: wheelRotationDegrees,
                  wheelSpinDuration: wheelSpinDuration,
                  wheelSpinCurve: wheelSpinCurve,
                  betOkBlink: betOkBlink,
                  betOkDisabled: betOkDisabled,
                  takeBlink: takeBlink,
                  showPrevBet: showPrevBet,
                  onTake: onTake,
                  onCancelBet: onCancelBet,
                  onCancelSpecific: onCancelSpecific,
                  onBetOk: onBetOk,
                  onPrevBet: onPrevBet,
                  onExit: onExit,
                  footerMessage: footerMessage,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StageBody extends StatelessWidget {
  final String email;
  final int timeLeftSeconds;
  final double score;
  final double totalBetAmount;
  final double winnerAmount;
  final List<int> last10;

  final int selectedChip;
  final void Function(int chip) onChipSelected;

  final Map<int, int> betsByNumber;
  final int? highlightedBetNumber;
  final bool betNumbersDisabled;
  final void Function(int number) onBetNumberPressed;

  final bool isSpinning;
  final double wheelRotationDegrees;
  final Duration wheelSpinDuration;
  final Curve wheelSpinCurve;

  final bool betOkBlink;
  final bool betOkDisabled;
  final bool takeBlink;
  final bool showPrevBet;

  final VoidCallback onTake;
  final VoidCallback onCancelBet;
  final VoidCallback onCancelSpecific;
  final VoidCallback onBetOk;
  final VoidCallback onPrevBet;
  final VoidCallback onExit;

  final String footerMessage;

  const _StageBody({
    required this.email,
    required this.timeLeftSeconds,
    required this.score,
    required this.totalBetAmount,
    required this.winnerAmount,
    required this.last10,
    required this.selectedChip,
    required this.onChipSelected,
    required this.betsByNumber,
    required this.highlightedBetNumber,
    required this.betNumbersDisabled,
    required this.onBetNumberPressed,
    required this.isSpinning,
    required this.wheelRotationDegrees,
    required this.wheelSpinDuration,
    required this.wheelSpinCurve,
    required this.betOkBlink,
    required this.betOkDisabled,
    required this.takeBlink,
    required this.showPrevBet,
    required this.onTake,
    required this.onCancelBet,
    required this.onCancelSpecific,
    required this.onBetOk,
    required this.onPrevBet,
    required this.onExit,
    required this.footerMessage,
  });

  @override
  Widget build(BuildContext context) {
    final last10Text = last10.isEmpty
        ? ""
        : last10.reversed.map((n) => n.toString()).join(" ");
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              FunTargetAssets.background,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: const Color(0xFF120804),
                  child: Center(
                    child: Text(
                      "Missing asset: ${FunTargetAssets.background}",
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),

          // Score/time/winner/last10 text overlays (positions match Salesforce CSS).
          Positioned(
            left: 130,
            top: 148,
            width: 180,
            height: 34,
            child:
                _ValueBox(text: score.toStringAsFixed(0), fontSize: 20, alignLeft: true),
          ),
          Positioned(
            left: 130,
            top: 264,
            width: 180,
            height: 34,
            child: _ValueBox(text: "0:${timeLeftSeconds.toString().padLeft(2, "0")}", fontSize: 22, alignLeft: true),
          ),
          Positioned(
            right: -60,
            top: 142,
            width: 180,
            height: 34,
            child: _ValueBox(
              text: winnerAmount.toStringAsFixed(0),
              fontSize: 20,
              alignRight: true,
            ),
          ),
          Positioned(
            right: -40,
            top: 264,
            width: 260,
            height: 34,
            child: _ValueBox(
              text: last10Text,
              fontSize: 20,
              alignLeft: true,
              singleLine: true,
              letterSpacing: 0.4,
            ),
          ),

          // Final-ten timer glow stack (matches LWC: blinks in last 10 seconds).
          Positioned(
            left: 0,
            top: 214,
            width: 241,
            height: 119,
            child: IgnorePointer(
              child: _TimerGlowStack(isBlinking: timeLeftSeconds <= 10),
            ),
          ),

          // Wheel layer.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -60),
                  child: SizedBox(
                    width: 460,
                    child: _Wheel(
                      rotationDegrees: wheelRotationDegrees,
                      duration: wheelSpinDuration,
                      curve: wheelSpinCurve,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Wheel center logo animation (matches Salesforce funTargetLogoAnimator).
          Positioned(
            left: (FunTargetStage.designWidth / 2) - 75,
            top: 248,
            width: 150,
            height: 150,
            child: IgnorePointer(
              child: ClipOval(
                child: _LogoAnimator(spinning: isSpinning),
              ),
            ),
          ),

          // Arrow (blink behavior matches LWC).
          Positioned(
            left: (FunTargetStage.designWidth / 2) - 44,
            top: 44,
            width: 88,
            height: 92,
            child: IgnorePointer(
              child: _ArrowStack(
                isSpinning: isSpinning,
                isFinalTenSeconds: timeLeftSeconds <= 10,
              ),
            ),
          ),

          // Title.
          Positioned(
            left: 0,
            right: 0,
            bottom: 146,
            child: IgnorePointer(
              child: Image.asset(FunTargetAssets.title, fit: BoxFit.fill),
            ),
          ),

          // Coins.
          ..._coinButtons(),

          // Bet number buttons (0-9 with glow).
          ..._betNumberButtons(),

          // Bet amounts shown above each number (matches LWC bet-amount-layer).
          ..._betAmountVisuals(),

          // Total bet amount (bottom-left; matches LWC .total-bet-amount).
          Positioned(
            left: 22,
            bottom: 11,
            child: IgnorePointer(
              child: Text(
                totalBetAmount.toStringAsFixed(0),
                style: const TextStyle(
                  color: Color(0xFFFFE7A1),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(offset: Offset(-1, -1), blurRadius: 0, color: Color(0xFF2A0E07)),
                    Shadow(offset: Offset(1, -1), blurRadius: 0, color: Color(0xFF2A0E07)),
                    Shadow(offset: Offset(-1, 1), blurRadius: 0, color: Color(0xFF2A0E07)),
                    Shadow(offset: Offset(1, 1), blurRadius: 0, color: Color(0xFF2A0E07)),
                  ],
                ),
              ),
            ),
          ),

          // Action buttons row (positions mirror CSS).
          _ActionButton(
            left: 0,
            bottom: 162,
            width: 154,
            height: 41,
            glowOn: FunTargetAssets.takeGlowOn,
            glowOff: FunTargetAssets.takeGlowOff,
            label: "Take",
            blink: takeBlink,
            onPressed: onTake,
          ),
          _ActionButton(
            left: 170,
            bottom: 162,
            width: 152,
            height: 34,
            glowOn: FunTargetAssets.cancelGlowOn,
            glowOff: FunTargetAssets.cancelGlowOff,
            label: "Cancel Bet",
            blink: false,
            onPressed: onCancelBet,
          ),
          _ActionButton(
            left: 700,
            bottom: 162,
            width: 152,
            height: 34,
            glowOn: FunTargetAssets.cancelGlowOn,
            glowOff: FunTargetAssets.cancelGlowOff,
            label: "Cancel Specific Bet",
            labelFontSize: 10,
            blink: false,
            onPressed: onCancelSpecific,
          ),
          Positioned(
            right: 0,
            bottom: 162,
            width: 154,
            height: 42,
            child: Visibility(
              visible: !showPrevBet,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: _ActionButtonBody(
                glowOn: FunTargetAssets.betOkGlowOn,
                glowOff: FunTargetAssets.betOkGlowOff,
                label: "Bet Ok",
                blink: betOkBlink,
                enabled: !betOkDisabled,
                onPressed: onBetOk,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 162,
            width: 154,
            height: 41,
            child: Visibility(
              visible: showPrevBet,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: _ActionButtonBody(
                glowOn: FunTargetAssets.prevGlowOn,
                glowOff: FunTargetAssets.prevGlowOff,
                label: "Prev Bet",
                blink: showPrevBet,
                onPressed: onPrevBet,
              ),
            ),
          ),
          _ActionButton(
            right: 0,
            bottom: 0,
            width: 92,
            height: 39,
            glowOn: FunTargetAssets.exitGlowOn,
            glowOff: FunTargetAssets.exitGlowOff,
            label: "Exit",
            labelFontSize: 18,
            blink: false,
            onPressed: onExit,
          ),

          // Footer message.
          Positioned(
            left: 250,
            right: 250,
            bottom: 10,
            child: Text(
              footerMessage.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: "Times New Roman",
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A1D06),
                letterSpacing: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Intentionally no extra "User:" label overlay (parity with Salesforce LWC).
        ],
      ),
    );
  }

  List<Widget> _coinButtons() {
    const coinValues = [1, 5, 10, 50, 100, 500, 1000, 5000];
    const coinImages = [
      FunTargetAssets.oneCoin,
      FunTargetAssets.fiveCoin,
      FunTargetAssets.tenCoin,
      FunTargetAssets.fiftyCoin,
      FunTargetAssets.hundredCoin,
      FunTargetAssets.fiveHundredCoin,
      FunTargetAssets.thousandCoin,
      FunTargetAssets.fiveThousandCoin,
    ];
    const coinLefts = [0.0, 58.0, 115.0, 172.0, 798.0, 855.0, 910.0, 968.0];
    const coinTop = 369.0;

    return List<Widget>.generate(coinValues.length, (index) {
      final value = coinValues[index];
      final image = coinImages[index];
      final left = coinLefts[index];
      final top = coinTop;
      final selected = value == selectedChip;
      return Positioned(
        left: left,
        top: top,
        width: 55,
        height: 40,
        child: GestureDetector(
          onTap: () => onChipSelected(value),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                const BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.45),
                  offset: Offset(0, 2),
                  blurRadius: 3,
                ),
                if (selected)
                  const BoxShadow(
                    color: Color.fromRGBO(255, 237, 158, 0.95),
                    offset: Offset(0, 0),
                    blurRadius: 9,
                  ),
              ],
            ),
            child: Transform.translate(
              offset: selected ? const Offset(0, -1) : Offset.zero,
              child: Transform.scale(
                scale: selected ? 1.07 : 1.0,
                alignment: Alignment.center,
                child: Image.asset(image, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _betNumberButtons() {
    const order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    const top = 657.0;
    const startLeft = 25.0;
    const step = 103.0;
    const leftShift = -15.0;

    return List<Widget>.generate(order.length, (index) {
      final value = order[index];
      final left = startLeft + index * step + leftShift;
      final hasBet = (betsByNumber[value] ?? 0) > 0;
      final isResult = highlightedBetNumber == value;

      return Positioned(
        left: left,
        top: top,
        width: 76,
        height: 72,
        child: GestureDetector(
          onTap: betNumbersDisabled ? null : () => onBetNumberPressed(value),
          child: Stack(
            children: [
              Positioned.fill(
                child: isResult
                    ? _BlinkingOpacity(
                        period: const Duration(milliseconds: 450),
                        startOn: true,
                        child: Image.asset(
                          FunTargetAssets.betGlow(value),
                          fit: BoxFit.fill,
                        ),
                      )
                    : hasBet
                        ? Image.asset(FunTargetAssets.betGlow(value), fit: BoxFit.fill)
                        : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _betAmountVisuals() {
    const betAmountTop = 631.0; // BET_NUMBER_ROW_TOP - 26 in the LWC.
    const startLeft = 25.0;
    const step = 103.0;
    const leftShift = -15.0;

    const order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    final visuals = <Widget>[];

    for (var i = 0; i < order.length; i++) {
      final value = order[i];
      final amount = betsByNumber[value] ?? 0;
      if (amount <= 0) continue;

      visuals.add(
        Positioned(
          left: startLeft + i * step + leftShift,
          top: betAmountTop,
          width: 76,
          height: 22,
          child: IgnorePointer(
            child: Center(
              child: Text(
                amount.toString(),
                style: const TextStyle(
                  color: Color(0xFF1F1208),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 0,
                      color: Color.fromRGBO(255, 243, 192, 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return visuals;
  }
}

class _Wheel extends StatefulWidget {
  final double rotationDegrees;
  final Duration duration;
  final Curve curve;

  const _Wheel({
    required this.rotationDegrees,
    required this.duration,
    required this.curve,
  });

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late double _fromDegrees;

  @override
  void initState() {
    super.initState();
    _fromDegrees = widget.rotationDegrees;
  }

  @override
  void didUpdateWidget(covariant _Wheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rotationDegrees != widget.rotationDegrees) {
      _fromDegrees = oldWidget.rotationDegrees;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _fromDegrees, end: widget.rotationDegrees),
      duration: widget.duration,
      curve: widget.curve,
      builder: (context, value, child) {
        return Transform.rotate(
          angle: (value % 360) * pi / 180,
          child: child,
        );
      },
      child: Image.asset(FunTargetAssets.wheel, fit: BoxFit.contain),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String text;
  final double fontSize;
  final bool alignLeft;
  final bool alignRight;
  final bool singleLine;
  final double? letterSpacing;

  const _ValueBox({
    required this.text,
    required this.fontSize,
    this.alignLeft = false,
    this.alignRight = false,
    this.singleLine = false,
    this.letterSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = (alignLeft || alignRight) ? Alignment.centerLeft : Alignment.center;
    // Match LWC quirks:
    // - score/time: left-aligned with left padding
    // - winner: flex-start + text-align right + left padding (it sits off the right edge)
    final effectiveAlignRight = alignRight && !alignLeft;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.only(left: (alignLeft || effectiveAlignRight) ? 18 : 0),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            text,
            maxLines: singleLine ? 1 : null,
            overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.visible,
            textAlign: effectiveAlignRight ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: const Color(0xFF241406),
              fontFamily: "Times New Roman",
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
              letterSpacing: letterSpacing,
              shadows: const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 0,
                  color: Color.fromRGBO(255, 255, 255, 0.6),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingOpacity extends StatefulWidget {
  final Duration period;
  final Widget child;
  final bool startOn;

  const _BlinkingOpacity({
    required this.period,
    required this.child,
    this.startOn = true,
  });

  @override
  State<_BlinkingOpacity> createState() => _BlinkingOpacityState();
}

class _BlinkingOpacityState extends State<_BlinkingOpacity> {
  Timer? _timer;
  late bool _on;

  @override
  void initState() {
    super.initState();
    _on = widget.startOn;
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _BlinkingOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _stopTimer();
      _startTimer();
    }
    if (oldWidget.startOn != widget.startOn) {
      _on = widget.startOn;
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(widget.period ~/ 2, (_) {
      if (!mounted) return;
      setState(() => _on = !_on);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(opacity: _on ? 1 : 0, child: widget.child);
  }
}

class _TimerGlowStack extends StatelessWidget {
  final bool isBlinking;

  const _TimerGlowStack({required this.isBlinking});

  @override
  Widget build(BuildContext context) {
    if (!isBlinking) {
      return Image.asset(FunTargetAssets.targetTimeGlowOff, fit: BoxFit.fill);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: _BlinkingOpacity(
            period: const Duration(milliseconds: 900),
            startOn: true,
            child: Image.asset(FunTargetAssets.targetTimeGlowOn, fit: BoxFit.fill),
          ),
        ),
        Positioned.fill(
          child: _BlinkingOpacity(
            period: const Duration(milliseconds: 900),
            startOn: false,
            child: Image.asset(FunTargetAssets.targetTimeGlowOff, fit: BoxFit.fill),
          ),
        ),
      ],
    );
  }
}

class _ArrowStack extends StatelessWidget {
  final bool isSpinning;
  final bool isFinalTenSeconds;

  const _ArrowStack({
    required this.isSpinning,
    required this.isFinalTenSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final isGlowDisabledWindow = !isSpinning && isFinalTenSeconds;
    if (isGlowDisabledWindow) {
      return Image.asset(FunTargetAssets.arrow, fit: BoxFit.contain);
    }

    final period = isSpinning
        ? const Duration(milliseconds: 180)
        : const Duration(milliseconds: 900);

    return Stack(
      children: [
        Positioned.fill(
          child: _BlinkingOpacity(
            period: period,
            startOn: true,
            child: Image.asset(FunTargetAssets.arrowGlow, fit: BoxFit.contain),
          ),
        ),
        Positioned.fill(
          child: _BlinkingOpacity(
            period: period,
            startOn: false,
            child: Image.asset(FunTargetAssets.arrow, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}

class _LogoAnimator extends StatefulWidget {
  final bool spinning;

  const _LogoAnimator({required this.spinning});

  @override
  State<_LogoAnimator> createState() => _LogoAnimatorState();
}

class _LogoAnimatorState extends State<_LogoAnimator> {
  static const _frameInterval = Duration(milliseconds: 90);
  static const _frameCount = 20;
  static const _base = "assets/funTargrtAsset/media/BAD/golo";

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.spinning) {
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant _LogoAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning == oldWidget.spinning) return;

    if (widget.spinning) {
      _reset();
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _reset() {
    _index = 0;
  }

  void _start() {
    _timer ??= Timer.periodic(_frameInterval, (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _frameCount;
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final path = "$_base/Logo$_index.jpg";
    return Image.asset(
      path,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final double? left;
  final double? right;
  final double? bottom;
  final double width;
  final double height;
  final String glowOn;
  final String glowOff;
  final String label;
  final double labelFontSize;
  final bool blink;
  final VoidCallback onPressed;

  const _ActionButton({
    this.left,
    this.right,
    required this.bottom,
    required this.width,
    required this.height,
    required this.glowOn,
    required this.glowOff,
    required this.label,
    this.labelFontSize = 17,
    required this.blink,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: _ActionButtonBody(
        glowOn: glowOn,
        glowOff: glowOff,
        label: label,
        labelFontSize: labelFontSize,
        blink: blink,
        onPressed: onPressed,
      ),
    );
  }
}

class _ActionButtonBody extends StatelessWidget {
  final String glowOn;
  final String glowOff;
  final String label;
  final double labelFontSize;
  final bool blink;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButtonBody({
    required this.glowOn,
    required this.glowOff,
    required this.label,
    this.labelFontSize = 17,
    required this.blink,
    this.enabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = label.toUpperCase();
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: blink
                ? _BlinkingOpacity(
                    period: const Duration(milliseconds: 900),
                    startOn: false,
                    child: Image.asset(glowOff, fit: BoxFit.fill),
                  )
                : Image.asset(glowOff, fit: BoxFit.fill),
          ),
          Positioned.fill(
            child: blink
                ? _BlinkingOpacity(
                    period: const Duration(milliseconds: 900),
                    startOn: true,
                    child: Image.asset(glowOn, fit: BoxFit.fill),
                  )
                : Opacity(
                    opacity: 0,
                    child: Image.asset(glowOn, fit: BoxFit.fill),
                  ),
          ),
          Positioned.fill(
            child: Center(
              child: Text(
                labelText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFE6A8),
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: labelFontSize <= 10 ? 0 : 0.3,
                  shadows: const [
                    Shadow(
                        offset: Offset(-1, -1),
                        blurRadius: 0,
                        color: Color(0xFF3F0B06)),
                    Shadow(
                        offset: Offset(1, -1),
                        blurRadius: 0,
                        color: Color(0xFF3F0B06)),
                    Shadow(
                        offset: Offset(-1, 1),
                        blurRadius: 0,
                        color: Color(0xFF3F0B06)),
                    Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 0,
                        color: Color(0xFF3F0B06)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
