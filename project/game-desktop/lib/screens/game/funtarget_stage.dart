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

  final bool betOkBlink;
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
    required this.betOkBlink,
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
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : designWidth;
        final scale = width / designWidth;
        final outerHeight = designHeight * scale * heightScale;

        return SizedBox(
          width: width,
          height: outerHeight,
          child: Align(
            alignment: Alignment.topCenter,
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
                  betOkBlink: betOkBlink,
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

  final bool betOkBlink;
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
    required this.betOkBlink,
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
    final last10Text = last10.join(", ");
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              FunTargetAssets.background,
              // For pixel-perfect overlays, avoid `cover` cropping.
              fit: BoxFit.fill,
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
            child: _ValueBox(text: score.toStringAsFixed(2), fontSize: 20, alignLeft: true),
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
            child: _ValueBox(text: winnerAmount.toStringAsFixed(2), fontSize: 20, alignRight: true),
          ),
          Positioned(
            right: -40,
            top: 264,
            width: 260,
            height: 34,
            child: _ValueBox(text: last10Text, fontSize: 20, alignLeft: true, singleLine: true),
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
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Arrow (blinking is implemented later; keep static now).
          Positioned(
            left: (FunTargetStage.designWidth / 2) - 44,
            top: 44,
            width: 88,
            height: 92,
            child: IgnorePointer(
              child: Stack(
                children: [
                  Positioned.fill(child: Image.asset(FunTargetAssets.arrowGlow, fit: BoxFit.contain)),
                  Positioned.fill(child: Image.asset(FunTargetAssets.arrow, fit: BoxFit.contain)),
                ],
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

          // Total bet amount display.
          Positioned(
            left: 445,
            top: 628,
            width: 140,
            height: 24,
            child: Center(
              child: Text(
                totalBetAmount.toStringAsFixed(2),
                style: const TextStyle(
                  color: Color(0xFF1F1208),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  shadows: [Shadow(offset: Offset(0, 1), blurRadius: 0, color: Color.fromRGBO(255, 243, 192, 0.7))],
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
              footerMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A1D06),
                letterSpacing: 1.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // User label (top-left, outside the "game art" feel but useful for parity).
          Positioned(
            left: 16,
            top: 12,
            child: Text(
              "User: $email",
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
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
        width: 54,
        height: 54,
        child: GestureDetector(
          onTap: () => onChipSelected(value),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              boxShadow: selected
                  ? [
                      const BoxShadow(
                        color: Color.fromRGBO(255, 220, 120, 0.75),
                        blurRadius: 12,
                        spreadRadius: 2,
                      )
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset(image, fit: BoxFit.cover),
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

    return List<Widget>.generate(order.length, (index) {
      final value = order[index];
      final left = startLeft + index * step;
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
                child: Opacity(
                  opacity: hasBet || isResult ? 1 : 0.65,
                  child: Image.asset(FunTargetAssets.betGlow(value), fit: BoxFit.fill),
                ),
              ),
              if (hasBet || isResult)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: isResult ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFFFD676), width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _Wheel extends StatelessWidget {
  final double rotationDegrees;
  const _Wheel({required this.rotationDegrees});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: rotationDegrees),
      duration: const Duration(milliseconds: 2800),
      curve: Curves.easeOutCubic,
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

  const _ValueBox({
    required this.text,
    required this.fontSize,
    this.alignLeft = false,
    this.alignRight = false,
    this.singleLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = alignRight
        ? Alignment.centerRight
        : alignLeft
            ? Alignment.centerLeft
            : Alignment.center;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.only(left: alignLeft ? 18 : 0, right: alignRight ? 18 : 0),
        child: Text(
          text,
          maxLines: singleLine ? 1 : null,
          overflow: singleLine ? TextOverflow.ellipsis : TextOverflow.visible,
          style: TextStyle(
            color: const Color(0xFF241406),
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
            shadows: const [Shadow(offset: Offset(0, 1), blurRadius: 0, color: Color.fromRGBO(255, 255, 255, 0.6))],
          ),
        ),
      ),
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
  final VoidCallback onPressed;

  const _ActionButtonBody({
    required this.glowOn,
    required this.glowOff,
    required this.label,
    this.labelFontSize = 17,
    required this.blink,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: blink ? 0.35 : 1,
              child: Image.asset(glowOff, fit: BoxFit.fill),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: blink ? 0.65 : 0,
              child: Image.asset(glowOn, fit: BoxFit.fill),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFE6A8),
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w800,
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
