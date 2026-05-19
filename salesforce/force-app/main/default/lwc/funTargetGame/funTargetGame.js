import { LightningElement, track } from "lwc";
import funTargrtAsset from "@salesforce/resourceUrl/funTargrtAsset";
import getOrCreateState from "@salesforce/apex/FunTargetStateController.getOrCreateState";
import getCurrentState from "@salesforce/apex/FunTargetStateController.getCurrentState";
import saveSpinResult from "@salesforce/apex/FunTargetStateController.saveSpinResult";
import applySiteIntentFlat from "@salesforce/apex/FunTargetStateController.applySiteIntentFlat";
import saveState from "@salesforce/apex/FunTargetStateController.saveState";

const SEGMENTS = 10;
const SEGMENT_ANGLE = 360 / SEGMENTS;
const POINTER_ALIGNMENT_OFFSET = 0;
const BET_BUTTON_LEFT_SHIFT = -15;
const BET_NUMBER_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
const BET_OK_HIGHLIGHT_STORAGE_KEY = "funTargetGame.betOkHighlighted";
const DEFAULT_FOOTER_MESSAGE =
  "You can either Make a Bet or press BET OK button";
const SPIN_FOOTER_MESSAGE = "For Amusement Only No Cash Value";
const POST_SPIN_FOOTER_MESSAGE = "Please bet to Start Game. Minimum Bet - 1";
const DEFAULT_LAST_RESULTS = [8, 8, 9, 0, 2, 9, 6, 4, 3, 7];
const SAVE_DEBOUNCE_MS = 450;
const LIVE_STATE_SYNC_MS = 3000;
const LIVE_STATE_SYNC_FINAL_TEN_MS = 1000;
const AUTO_SPIN_DURATION = "5.0s";
const ROUND_SECONDS = 60;
const SPIN_START_SECOND = 0;
const SPIN_RESULT_SECOND = 55;
const RESULT_HIGHLIGHT_CLEAR_SECOND = 50;
const PAYOUT_FORFEIT_SECOND = 30;
const FINAL_TEN_SECOND = 10;
const ANCHOR_SHIFT_TO_59_MS = 56000;
const ROUND_PHASE = {
  BETTING: "BETTING",
  SPINNING: "SPINNING",
  RESULT: "RESULT",
  LOCKED: "LOCKED"
};

const ASSET_BASE = `${funTargrtAsset}/media/FunTargetImages`;
const SOUND_BASE = `${funTargrtAsset}/Sounds`;
const SOUND_FILES = {
  bet: `${SOUND_BASE}/bet.wav`,
  button: `${SOUND_BASE}/button.WAV`,
  exit: `${SOUND_BASE}/exit.wav`,
  loading: `${SOUND_BASE}/loading.wav`,
  lose: `${SOUND_BASE}/lose.wav`,
  take: `${SOUND_BASE}/take.wav`,
  wheelEnd: `${SOUND_BASE}/wheelEnd.wav`,
  wheelStart: `${SOUND_BASE}/wheelStart.wav`,
  win: `${SOUND_BASE}/win.WAV`
};

const COIN_BUTTONS = [
  { value: 1, image: `${ASSET_BASE}/oneCoin.jpg`, left: 0, top: 369 },
  { value: 5, image: `${ASSET_BASE}/fiveCoin.jpg`, left: 58, top: 369 },
  { value: 10, image: `${ASSET_BASE}/tenCoin.jpg`, left: 115, top: 369 },
  { value: 50, image: `${ASSET_BASE}/fiftyCoin.jpg`, left: 172, top: 369 },
  { value: 100, image: `${ASSET_BASE}/hundredCoin.jpg`, left: 798, top: 369 },
  {
    value: 500,
    image: `${ASSET_BASE}/fiveHundredCoin.jpg`,
    left: 855,
    top: 369
  },
  { value: 1000, image: `${ASSET_BASE}/thousandCoin.jpg`, left: 910, top: 369 },
  {
    value: 5000,
    image: `${ASSET_BASE}/fiveThousandCoin.jpg`,
    left: 968,
    top: 369
  }
];

const BET_NUMBER_ROW_TOP = 657;
const BET_NUMBER_START_LEFT = 25;
const BET_NUMBER_STEP = 103;
const BET_AMOUNT_ROW_TOP = BET_NUMBER_ROW_TOP - 26;
const BET_NUMBER_BUTTONS = BET_NUMBER_ORDER.map((value, index) => ({
  value,
  left: BET_NUMBER_START_LEFT + index * BET_NUMBER_STEP,
  top: BET_NUMBER_ROW_TOP
}));

export default class FunTargetGame extends LightningElement {
  numbers = Array.from({ length: SEGMENTS }, (_, idx) => idx);

  @track selectedNumber = null;
  @track selectedNumbers = [];
  @track betsByNumber = {};
  @track pendingPayout = 0;
  @track winnerValue = 0;
  @track highlightedBetNumber = null;
  @track isBetOkHighlighted = false;
  @track isBetConfirmed = false;
  @track showPrevBet = false;
  @track selectedChip = 1;
  @track currentNumber = 0;
  @track coins = 1000;
  @track rotation = 0;
  @track isSpinning = false;
  @track lastResults = [...DEFAULT_LAST_RESULTS];
  @track footerMessage = DEFAULT_FOOTER_MESSAGE;
  @track isFinalTenSeconds = false;
  @track logoResetToken = 0;
  @track roundPhase = ROUND_PHASE.BETTING;

  spinDuration = "2.8s";
  spinEasing = "cubic-bezier(0.22, 0.9, 0.26, 1.05)";
  _spinTimer;
  _spinRafId;
  _countdownTimer;
  _timeLeftSeconds = 59;
  _lastTimerSecond = null;
  _autoSpinActive = false;
  _autoSpinResult = null;
  _prevBet = null;
  _resizeRafId;
  _boundHandleResize;
  _lastAppliedScale = 1;
  _stateSaveTimer;
  _stateSaveInFlight = false;
  _stateDirty = false;
  _stateInitialized = false;
  _pendingSaveBeforeInit = false;
  _lastSavedStateHash = "";
  _lastRoundAtIso = null;
  _fallbackRoundAnchorMs = null;
  _serverClockOffsetMs = 0;
  _roundStartInProgress = false;
  _roundPredefinedNumber = null;
  _predefinedWheelNumber = null;
  _liveStateSyncTimer;
  _liveStateSyncInFlight = false;
  _sounds = {};
  _soundLoadingPlayed = false;
  _audioUnlocked = false;
  _audioUnlockInProgress = false;
  _pendingSoundKey = null;
  _audioUnlockHandler;
  _boundVisibilityChange;
  _boundWindowFocus;
  _coinButtonsCacheKey;
  _coinButtonsCache;
  _lastResultsTextCacheKey;
  _lastResultsTextCacheValue = "";
  _betButtonsCacheKey;
  _betButtonsCache;
  _betAmountsCacheKey;
  _betAmountsCache;
  _betPersistInFlight = false;
  _betPersistQueued = false;
  _betPersistPromise;
  _timerText = "0:59";
  _stateLastModified = null;

  get stageStyle() {
    return `background-image: url(${ASSET_BASE}/Bg.jpg);`;
  }

  get wheelUrl() {
    return `${ASSET_BASE}/Wheel5.png`;
  }

  get arrowUrl() {
    return `${ASSET_BASE}/Arrow.png`;
  }

  get arrowGlowUrl() {
    return `${ASSET_BASE}/ArrowGlow.png`;
  }

  get targetTimeGlowUrl() {
    return `${ASSET_BASE}/TargetTimeGlow.jpg`;
  }

  get targetTimeOffUrl() {
    return `${ASSET_BASE}/TargetTimeGlow2.png`;
  }

  get arrowStackClass() {
    return `arrow-stack${this.isSpinning ? " spinning" : ""}${this.isGlowDisabledWindow ? " no-glow" : ""}`;
  }

  get timerGlowClass() {
    return `timer-glow-stack${this.isFinalTenSeconds ? " blinking" : ""}`;
  }

  get isGlowDisabledWindow() {
    return !this.isSpinning && this.isFinalTenSeconds;
  }

  get titleUrl() {
    return `${ASSET_BASE}/Title.png`;
  }

  get takeGlowUrl() {
    return `${ASSET_BASE}/Take_Glow.jpg`;
  }

  get takeOffUrl() {
    return `${ASSET_BASE}/Take_Glow2.png`;
  }

  get betOkGlowUrl() {
    return `${ASSET_BASE}/BetOk_Glow.jpg`;
  }

  get betOkOffUrl() {
    return `${ASSET_BASE}/BetOk_Glow2.png`;
  }

  get cancelGlowUrl() {
    return `${ASSET_BASE}/Cancel-Bet-Glow.png`;
  }

  get cancelOffUrl() {
    return `${ASSET_BASE}/Cancel-Bet.png`;
  }

  get prevGlowUrl() {
    return `${ASSET_BASE}/PrevBetGlow.jpg`;
  }

  get prevOffUrl() {
    return `${ASSET_BASE}/PrevBetGlow2.png`;
  }

  get exitGlowUrl() {
    return `${ASSET_BASE}/exit_Glow.png`;
  }

  get exitOffUrl() {
    return `${ASSET_BASE}/exit_Glow2.png`;
  }

  get wheelStyle() {
    return `--wheel-rot: ${this.rotation}deg; --spin-duration: ${this.spinDuration}; --spin-easing: ${this.spinEasing};`;
  }

  get coinButtons() {
    const cacheKey = String(this.selectedChip);
    if (this._coinButtonsCacheKey === cacheKey && this._coinButtonsCache) {
      return this._coinButtonsCache;
    }

    this._coinButtonsCache = COIN_BUTTONS.map((item) => ({
      value: item.value,
      image: item.image,
      isSelected: this.selectedChip === item.value,
      ariaLabel: `Select coin ${item.value}`,
      className: `coin-btn${this.selectedChip === item.value ? " active" : ""}`,
      style: `left:${item.left}px; top:${item.top}px;`
    }));
    this._coinButtonsCacheKey = cacheKey;

    return this._coinButtonsCache;
  }

  get lastResultsText() {
    const cacheKey = this.lastResults.join(",");
    if (this._lastResultsTextCacheKey === cacheKey) {
      return this._lastResultsTextCacheValue;
    }

    this._lastResultsTextCacheKey = cacheKey;
    this._lastResultsTextCacheValue = [...this.lastResults].reverse().join(" ");
    return this._lastResultsTextCacheValue;
  }

  get betNumberButtons() {
    const betsSignature = this._betsSignature();
    const disabledFlag = this.isBetNumberDisabled ? "1" : "0";
    const cacheKey = `${betsSignature}|${this.highlightedBetNumber}|${disabledFlag}`;
    if (this._betButtonsCacheKey === cacheKey && this._betButtonsCache) {
      return this._betButtonsCache;
    }

    this._betButtonsCache = BET_NUMBER_BUTTONS.map((item) => ({
      value: item.value,
      ariaLabel: `Bet ${item.value}`,
      glowUrl: `${ASSET_BASE}/BetGlow${item.value}.jpg`,
      className: this._betButtonClass(item.value),
      isDisabled: this.isBetNumberDisabled,
      style: `left:${item.left + BET_BUTTON_LEFT_SHIFT}px; top:${item.top}px;`
    }));
    this._betButtonsCacheKey = cacheKey;

    return this._betButtonsCache;
  }

  get betAmountVisuals() {
    const betsSignature = this._betsSignature();
    if (this._betAmountsCacheKey === betsSignature && this._betAmountsCache) {
      return this._betAmountsCache;
    }

    this._betAmountsCache = BET_NUMBER_BUTTONS.filter(
      (slot) => (this.betsByNumber[slot.value] || 0) > 0
    ).map((slot) => ({
      key: `bet-amount-${slot.value}`,
      value: this.betsByNumber[slot.value],
      style: `left:${slot.left + BET_BUTTON_LEFT_SHIFT}px; top:${BET_AMOUNT_ROW_TOP}px;`
    }));
    this._betAmountsCacheKey = betsSignature;

    return this._betAmountsCache;
  }

  get totalBetAmount() {
    return Object.values(this.betsByNumber).reduce(
      (sum, amount) => sum + amount,
      0
    );
  }

  get isBetNumberDisabled() {
    return this.roundPhase !== ROUND_PHASE.BETTING || this.isBetConfirmed;
  }

  get shouldHighlightBetOk() {
    return (
      this.isBetOkHighlighted &&
      !this.isBetConfirmed &&
      !this.isSpinning &&
      !this.isFinalTenSeconds
    );
  }

  get isBetOkDisabled() {
    return (
      this.roundPhase !== ROUND_PHASE.BETTING ||
      this.isBetConfirmed ||
      this.totalBetAmount <= 0
    );
  }

  get betOkButtonClass() {
    return `action-btn betok${this.showPrevBet ? " hidden" : ""}${this.shouldBlinkBetOk ? " blink" : ""}`;
  }

  get prevButtonClass() {
    return `action-btn prev${this.showPrevBet ? " blink" : " hidden"}`;
  }

  get takeButtonClass() {
    return `action-btn take${this.pendingPayout > 0 ? " blink" : ""}`;
  }

  get shouldBlinkBetOk() {
    return !this.showPrevBet && !this.isBetConfirmed && this.totalBetAmount > 0;
  }

  selectNumber(event) {
    const value = Number(event.currentTarget.dataset.number);
    if (!this.selectedChip || this.isBetNumberDisabled) {
      return;
    }
    if (this.coins < this.selectedChip) {
      return;
    }

    const updatedBets = { ...this.betsByNumber };
    updatedBets[value] = (updatedBets[value] || 0) + this.selectedChip;
    this.betsByNumber = updatedBets;
    this.showPrevBet = false;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this._playSound("bet");

    this.coins -= this.selectedChip;
    this.selectedNumbers = Object.keys(updatedBets).map(Number);
    this.selectedNumber = value;
    this._persistBetsState();
  }

  selectChip(event) {
    const value = Number(event.currentTarget.dataset.chip);
    this.selectedChip = value;
    this._playSound("button");
  }

  spinWheel() {
    const target =
      this.selectedNumber ??
      this.selectedNumbers[this.selectedNumbers.length - 1];
    if (this.isSpinning || target === undefined || target === null) {
      return;
    }

    this.isSpinning = true;
    const targetAngle = this._targetAngleForNumber(target);
    const spins = 5;
    const nextRotation = this.rotation + spins * 360 + targetAngle;
    this._startSpinAnimation(
      nextRotation,
      "2.8s",
      "cubic-bezier(0.22, 0.9, 0.26, 1.05)"
    );

    window.clearTimeout(this._spinTimer);
    this._spinTimer = window.setTimeout(() => {
      this.isSpinning = false;
      this.currentNumber = target;
      this.lastResults = [target, ...this.lastResults].slice(0, 10);
      this._prevBet = {
        betsByNumber: { ...this.betsByNumber },
        numbers: [...this.selectedNumbers],
        number: target,
        chip: this.selectedChip
      };
    }, 2800);
  }

  placeBet() {
    if (this.isBetOkDisabled) {
      return;
    }
    if (!this.selectedNumbers.length || this.totalBetAmount <= 0) {
      return;
    }
    this._playSound("bet");
    this.isBetConfirmed = true;
    this.showPrevBet = false;
    this.footerMessage = "Your bet has been Accepted";
    this._setBetOkHighlighted(false);
    this._prevBet = {
      betsByNumber: { ...this.betsByNumber },
      numbers: [...this.selectedNumbers],
      number: this.selectedNumber,
      chip: this.selectedChip
    };
    this._persistBetsState();
  }

  cancelBet() {
    this._playSound("button");
    this.selectedNumber = null;
    this.selectedNumbers = [];
    this.highlightedBetNumber = null;
    const refund = Object.values(this.betsByNumber).reduce(
      (sum, amount) => sum + amount,
      0
    );
    this.coins += refund;
    this.betsByNumber = {};
    this.isBetConfirmed = false;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this._refreshRoundPhase();
    this._persistBetsState();
  }

  cancelSpecificBet() {
    if (this.selectedNumber === null) {
      return;
    }
    this._playSound("button");

    const target = this.selectedNumber;
    const updatedBets = { ...this.betsByNumber };
    const refund = updatedBets[target] || 0;
    delete updatedBets[target];

    this.coins += refund;
    this.betsByNumber = updatedBets;
    this.selectedNumbers = Object.keys(updatedBets).map(Number);
    this.selectedNumber = null;
    this.isBetConfirmed = false;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this._refreshRoundPhase();
    this._persistBetsState();
  }

  takePayout() {
    if (!this.pendingPayout) {
      return;
    }
    this._playSound("take");
    this.coins += this.pendingPayout;
    this.pendingPayout = 0;
    this.winnerValue = 0;
    this.highlightedBetNumber = null;
    this.isBetConfirmed = false;
    this.showPrevBet = true;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this._setBetOkHighlighted(true);
    this._refreshRoundPhase();
    this._applySiteIntent("TAKE_PAYOUT").catch(() => {
      this._syncStateFromServer();
    });
  }

  prevBet() {
    if (this.isSpinning || this.isFinalTenSeconds || this.isBetConfirmed) {
      return;
    }
    this._playSound("button");
    this.showPrevBet = false;
    if (!this._prevBet) {
      return;
    }
    const previousBets = { ...(this._prevBet.betsByNumber || {}) };
    const previousTotal = Object.values(previousBets).reduce(
      (sum, amount) => sum + amount,
      0
    );
    if (this.coins < previousTotal) {
      return;
    }

    this.betsByNumber = previousBets;
    this.coins -= previousTotal;
    this.selectedNumbers = Object.keys(previousBets).map(Number);
    this.selectedNumber =
      this.selectedNumbers[this.selectedNumbers.length - 1] ??
      this._prevBet.number ??
      null;
    this.selectedChip = this._prevBet.chip ?? this.selectedChip;
    this.isBetConfirmed = false;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this._refreshRoundPhase();
    this._persistBetsState();
  }

  showAllBet() {
    return;
  }

  resetGame() {
    this._playSound("exit");
    this.selectedNumber = null;
    this.selectedNumbers = [];
    this.betsByNumber = {};
    this.pendingPayout = 0;
    this.winnerValue = 0;
    this.highlightedBetNumber = null;
    this._setBetOkHighlighted(false);
    this.isBetConfirmed = false;
    this.showPrevBet = false;
    this.footerMessage = DEFAULT_FOOTER_MESSAGE;
    this.selectedChip = 1;
    this.currentNumber = 0;
    this.rotation = 0;
    this.isSpinning = false;
    this.coins = 0;
    this.lastResults = [...DEFAULT_LAST_RESULTS];
    this._timeLeftSeconds = 59;
    this._lastTimerSecond = null;
    this._autoSpinActive = false;
    this._autoSpinResult = null;
    this.spinDuration = "2.8s";
    this.spinEasing = "cubic-bezier(0.22, 0.9, 0.26, 1.05)";
    this._fallbackRoundAnchorMs =
      this._getServerNowMs() - ANCHOR_SHIFT_TO_59_MS;
    this._prevBet = null;
    window.clearTimeout(this._spinTimer);
    if (this._spinRafId) {
      window.cancelAnimationFrame(this._spinRafId);
      this._spinRafId = null;
    }
    this.logoResetToken += 1;
    this._lastRoundAtIso = null;
    this._updateTimerFromAnchor();
    this._refreshRoundPhase();
    this._applySiteIntent("RESET_GAME").catch(() => {
      this._syncStateFromServer();
    });
  }

  connectedCallback() {
    this._initializeSounds();
    this._registerAudioUnlockListeners();
    this._tryWarmupAudio();
    if (!this._boundHandleResize) {
      this._boundHandleResize = this._scheduleScaleUpdate.bind(this);
    }
    if (!this._boundVisibilityChange) {
      this._boundVisibilityChange = this._handleVisibilityChange.bind(this);
    }
    if (!this._boundWindowFocus) {
      this._boundWindowFocus = this._handleWindowFocus.bind(this);
    }
    window.addEventListener("resize", this._boundHandleResize);
    window.addEventListener("orientationchange", this._boundHandleResize);
    window.addEventListener("focus", this._boundWindowFocus);
    if (typeof document !== "undefined") {
      document.addEventListener(
        "visibilitychange",
        this._boundVisibilityChange
      );
    }
    this._playLoadingSoundOnce();
    this._restoreBetOkHighlight();
    this._startCountdown();
    this._initializeState();
    this._startLiveStateSync();
    this._syncStateFromServer();
  }

  renderedCallback() {
    this._scheduleScaleUpdate();
    this._renderTimerTextToDom();
  }

  disconnectedCallback() {
    this._disposeSounds();
    this._unregisterAudioUnlockListeners();
    if (this._boundHandleResize) {
      window.removeEventListener("resize", this._boundHandleResize);
      window.removeEventListener("orientationchange", this._boundHandleResize);
    }
    if (this._boundWindowFocus) {
      window.removeEventListener("focus", this._boundWindowFocus);
    }
    if (this._boundVisibilityChange && typeof document !== "undefined") {
      document.removeEventListener(
        "visibilitychange",
        this._boundVisibilityChange
      );
    }
    if (this._resizeRafId) {
      window.cancelAnimationFrame(this._resizeRafId);
      this._resizeRafId = null;
    }
    if (this._countdownTimer) {
      window.clearTimeout(this._countdownTimer);
      this._countdownTimer = null;
    }
    window.clearTimeout(this._spinTimer);
    if (this._spinRafId) {
      window.cancelAnimationFrame(this._spinRafId);
      this._spinRafId = null;
    }
    if (this._stateSaveTimer) {
      window.clearTimeout(this._stateSaveTimer);
      this._stateSaveTimer = null;
    }
    if (
      this._stateInitialized &&
      this._stateDirty &&
      !this._stateSaveInFlight
    ) {
      this._flushStateSave();
    }
    this._stopLiveStateSync();
  }

  _startCountdown() {
    if (this._countdownTimer) {
      return;
    }

    this._runCountdownTick();
  }

  _runCountdownTick() {
    this._countdownTimer = null;
    this._updateTimerFromAnchor();

    const nowMs = this._getServerNowMs();
    const msToNextSecond = 1000 - (nowMs % 1000);
    const nextDelay = Math.min(1000, Math.max(120, msToNextSecond + 12));
    this._countdownTimer = window.setTimeout(() => {
      this._runCountdownTick();
    }, nextDelay);
  }

  _updateTimerFromAnchor() {
    const nextSecond = this._computeTimerSecond();
    if (nextSecond === this._lastTimerSecond) {
      return;
    }

    const previousSecond = this._lastTimerSecond;
    this._lastTimerSecond = nextSecond;
    this._timeLeftSeconds = nextSecond;
    this._handleTimerSecondChange(previousSecond, nextSecond);
    this._updateTimerText();
  }

  _computeTimerSecond() {
    const anchorMs = this._getRoundAnchorMs();
    if (!Number.isFinite(anchorMs)) {
      return 59;
    }

    const elapsedSeconds = Math.max(
      0,
      Math.floor((this._getServerNowMs() - anchorMs) / 1000)
    );
    return (
      (SPIN_RESULT_SECOND - (elapsedSeconds % ROUND_SECONDS) + ROUND_SECONDS) %
      ROUND_SECONDS
    );
  }

  _getRoundAnchorMs() {
    if (this._lastRoundAtIso) {
      const parsedAnchorMs = new Date(this._lastRoundAtIso).getTime();
      if (Number.isFinite(parsedAnchorMs)) {
        return parsedAnchorMs;
      }
    }

    if (
      this._fallbackRoundAnchorMs !== null &&
      Number.isFinite(this._fallbackRoundAnchorMs)
    ) {
      return this._fallbackRoundAnchorMs;
    }

    if (this._stateLastModified) {
      const modifiedMs = new Date(this._stateLastModified).getTime();
      if (Number.isFinite(modifiedMs)) {
        this._fallbackRoundAnchorMs = modifiedMs - ANCHOR_SHIFT_TO_59_MS;
        return this._fallbackRoundAnchorMs;
      }
    }

    this._fallbackRoundAnchorMs =
      this._getServerNowMs() - ANCHOR_SHIFT_TO_59_MS;
    return this._fallbackRoundAnchorMs;
  }

  _handleTimerSecondChange(previousSecond, currentSecond) {
    this._syncFinalTenState();
    if (!this._stateInitialized) {
      return;
    }

    if (
      this._crossedTimerSecond(
        previousSecond,
        currentSecond,
        RESULT_HIGHLIGHT_CLEAR_SECOND
      )
    ) {
      this.highlightedBetNumber = null;
    }

    if (
      this._crossedTimerSecond(previousSecond, currentSecond, FINAL_TEN_SECOND)
    ) {
      this._setBetOkHighlighted(false);
    }

    if (
      this._crossedTimerSecond(
        previousSecond,
        currentSecond,
        PAYOUT_FORFEIT_SECOND
      )
    ) {
      if (this.winnerValue > 0 || this.pendingPayout > 0) {
        this.winnerValue = 0;
        this.pendingPayout = 0;
        this._applySiteIntent("FORFEIT_PAYOUT").catch(() => {
          this._syncStateFromServer();
        });
      }
    }

    if (
      this._crossedTimerSecond(previousSecond, currentSecond, SPIN_START_SECOND)
    ) {
      this._startAutoSpinRound();
    }

    if (
      this._autoSpinActive &&
      this._crossedTimerSecond(
        previousSecond,
        currentSecond,
        SPIN_RESULT_SECOND
      )
    ) {
      this._finalizeAutoSpinRound();
    }
  }

  _crossedTimerSecond(previousSecond, currentSecond, targetSecond) {
    if (previousSecond === null || previousSecond === undefined) {
      return currentSecond === targetSecond;
    }

    if (previousSecond === currentSecond) {
      return false;
    }

    let cursor = previousSecond;
    for (let index = 0; index < ROUND_SECONDS; index += 1) {
      cursor = (cursor - 1 + ROUND_SECONDS) % ROUND_SECONDS;
      if (cursor === targetSecond) {
        return true;
      }
      if (cursor === currentSecond) {
        return false;
      }
    }

    return false;
  }

  _updateTimerText() {
    const seconds = String(this._timeLeftSeconds).padStart(2, "0");
    this._timerText = `0:${seconds}`;
    this._renderTimerTextToDom();
  }

  _syncFinalTenState() {
    const isFinalTen =
      this._timeLeftSeconds >= 0 && this._timeLeftSeconds <= 10;
    if (isFinalTen !== this.isFinalTenSeconds) {
      this.isFinalTenSeconds = isFinalTen;
      this._restartLiveStateSync();
    }
    this._refreshRoundPhase();
  }

  _refreshRoundPhase() {
    let nextPhase = ROUND_PHASE.BETTING;
    if (this.isSpinning) {
      nextPhase = ROUND_PHASE.SPINNING;
    } else if (this.pendingPayout > 0) {
      nextPhase = ROUND_PHASE.RESULT;
    } else if (this.isFinalTenSeconds) {
      nextPhase = ROUND_PHASE.LOCKED;
    }

    if (nextPhase !== this.roundPhase) {
      this.roundPhase = nextPhase;
    }
  }

  _renderTimerTextToDom() {
    const timeValueEl = this.template.querySelector('[data-id="timeValue"]');
    if (!timeValueEl || timeValueEl.textContent === this._timerText) {
      return;
    }
    timeValueEl.textContent = this._timerText;
  }

  _startAutoSpinRound() {
    if (this._autoSpinActive || this._roundStartInProgress) {
      return;
    }
    this._roundStartInProgress = true;
    this.highlightedBetNumber = null;
    this._setBetOkHighlighted(false);
    this.isBetConfirmed = true;
    this.footerMessage = SPIN_FOOTER_MESSAGE;
    this._queueStateSave(true);

    try {
      const predefinedNumber = this._predefinedWheelNumber;

      const result =
        predefinedNumber !== null
          ? predefinedNumber
          : Math.floor(Math.random() * SEGMENTS);
      const targetAngle = this._targetAngleForNumber(result);
      const normalized = ((this.rotation % 360) + 360) % 360;
      const delta = (targetAngle - normalized + 360) % 360;

      this._roundPredefinedNumber = predefinedNumber;
      this._autoSpinResult = result;
      this._autoSpinActive = true;
      this.isSpinning = true;
      this._refreshRoundPhase();
      this._playSound("wheelStart");
      this._startSpinAnimation(
        this.rotation + 12 * 360 + delta,
        AUTO_SPIN_DURATION,
        "cubic-bezier(0.1, 0.95, 0.15, 1)"
      );
    } finally {
      this._roundStartInProgress = false;
    }
  }

  _finalizeAutoSpinRound() {
    if (!this._autoSpinActive || this._autoSpinResult === null) {
      return;
    }

    const result = this._autoSpinResult;
    const usedPredefinedNumber = this._roundPredefinedNumber !== null;
    this.currentNumber = result;
    this.highlightedBetNumber = result;
    this.lastResults = [result, ...this.lastResults].slice(0, 10);
    this._resolveRoundBets(result);
    this.isSpinning = false;
    this._stopSound("wheelStart");
    this._playSound("wheelEnd");
    this._playSound(this.winnerValue > 0 ? "win" : "lose");
    this._autoSpinActive = false;
    this._autoSpinResult = null;
    this._roundPredefinedNumber = null;
    this._predefinedWheelNumber = null;
    this.spinDuration = "2.8s";
    this.spinEasing = "cubic-bezier(0.22, 0.9, 0.26, 1.05)";
    this.isBetConfirmed = false;
    this.footerMessage = POST_SPIN_FOOTER_MESSAGE;
    this._lastRoundAtIso = new Date(this._getServerNowMs()).toISOString();
    this._fallbackRoundAnchorMs = null;
    this._refreshRoundPhase();
    this._persistSpinResult(result, usedPredefinedNumber);
  }

  _startSpinAnimation(targetRotation, duration, easing) {
    if (this._spinRafId) {
      window.cancelAnimationFrame(this._spinRafId);
      this._spinRafId = null;
    }

    this.spinDuration = duration;
    this.spinEasing = easing;

    this._spinRafId = window.requestAnimationFrame(() => {
      this.rotation = targetRotation;
      this._spinRafId = null;
    });
  }

  _targetAngleForNumber(value) {
    return 360 - (value * SEGMENT_ANGLE + POINTER_ALIGNMENT_OFFSET);
  }

  _resolveRoundBets(result) {
    const winningStake = this.betsByNumber[result] || 0;
    this.winnerValue = winningStake > 0 ? winningStake * 9 : 0;
    this.pendingPayout = this.winnerValue;
    this.betsByNumber = {};
    this.selectedNumber = null;
    this.selectedNumbers = [];
    this._refreshRoundPhase();
  }

  _persistSpinResult(spinResult, clearPredefinedWheelNumber) {
    saveSpinResult({
      spinResult,
      clearPredefinedWheelNumber,
      expectedLastModified: this._stateLastModified
    })
      .then((state) => {
        if (state) {
          this._applyLoadedState(state);
          this._lastSavedStateHash = JSON.stringify(this._buildStatePayload());
        }
      })
      .catch(() => {
        // If server-side spin persistence fails, keep local values.
      });
  }

  _initializeState() {
    getOrCreateState()
      .then((state) => {
        this._applyLoadedState(state);
        this._stateInitialized = true;
        this._lastSavedStateHash = JSON.stringify(this._buildStatePayload());
        if (this._pendingSaveBeforeInit) {
          this._pendingSaveBeforeInit = false;
          this._queueStateSave(true);
        }
      })
      .catch(() => {
        this._stateInitialized = true;
      });
  }

  _handleVisibilityChange() {
    if (this._isDocumentVisible()) {
      this._startLiveStateSync();
      this._syncStateFromServer();
      return;
    }
    this._stopLiveStateSync();
  }

  _handleWindowFocus() {
    this._syncStateFromServer();
  }

  _isDocumentVisible() {
    if (typeof document === "undefined") {
      return true;
    }
    return document.visibilityState !== "hidden";
  }

  _syncServerClock(serverNowValue) {
    if (!serverNowValue) {
      return;
    }
    const parsedServerNowMs = new Date(serverNowValue).getTime();
    if (!Number.isFinite(parsedServerNowMs)) {
      return;
    }
    this._serverClockOffsetMs = parsedServerNowMs - Date.now();
  }

  _getServerNowMs() {
    return Date.now() + this._serverClockOffsetMs;
  }

  _syncFallbackRoundAnchor(lastModifiedValue) {
    if (this._fallbackRoundAnchorMs !== null) {
      return;
    }
    if (lastModifiedValue) {
      const modifiedMs = new Date(lastModifiedValue).getTime();
      if (Number.isFinite(modifiedMs)) {
        this._fallbackRoundAnchorMs = modifiedMs - ANCHOR_SHIFT_TO_59_MS;
        return;
      }
    }
    this._fallbackRoundAnchorMs =
      this._getServerNowMs() - ANCHOR_SHIFT_TO_59_MS;
  }

  _startLiveStateSync() {
    if (this._liveStateSyncTimer || !this._isDocumentVisible()) {
      return;
    }

    this._scheduleNextLiveStateSync(this._getLiveStateSyncDelayMs());
  }

  _stopLiveStateSync() {
    if (!this._liveStateSyncTimer) {
      return;
    }
    window.clearTimeout(this._liveStateSyncTimer);
    this._liveStateSyncTimer = null;
  }

  _restartLiveStateSync() {
    if (!this._isDocumentVisible()) {
      return;
    }
    this._stopLiveStateSync();
    this._startLiveStateSync();
  }

  _scheduleNextLiveStateSync(delayMs) {
    this._liveStateSyncTimer = window.setTimeout(() => {
      this._liveStateSyncTimer = null;
      if (!this._isDocumentVisible()) {
        return;
      }
      this._syncStateFromServer();
      this._scheduleNextLiveStateSync(this._getLiveStateSyncDelayMs());
    }, delayMs);
  }

  _getLiveStateSyncDelayMs() {
    return this._timeLeftSeconds >= 0 && this._timeLeftSeconds <= 10
      ? LIVE_STATE_SYNC_FINAL_TEN_MS
      : LIVE_STATE_SYNC_MS;
  }

  _syncStateFromServer() {
    if (
      !this._stateInitialized ||
      !this._isDocumentVisible() ||
      this._liveStateSyncInFlight ||
      this._stateSaveInFlight ||
      this._stateDirty
    ) {
      return;
    }

    this._liveStateSyncInFlight = true;
    getCurrentState()
      .then((state) => {
        if (!state) {
          return;
        }
        this._syncServerClock(state.serverNow);

        // Prevent stale site-side score from overwriting local in-round score.
        // Only sync score from server when it was updated by Admin.
        const updatedFrom = String(state.lastUpdatedFrom || "")
          .trim()
          .toLowerCase();
        if (updatedFrom === "admin") {
          const serverScore = Number(state.score);
          if (Number.isFinite(serverScore) && serverScore !== this.coins) {
            this.coins = serverScore;
          }
        }
        this._predefinedWheelNumber = this._normalizeWheelNumber(
          state.predefinedWheelNumber
        );
        this._stateLastModified =
          this._safeIsoDate(state.lastModifiedDate) || this._stateLastModified;
        const incomingLastRoundAt = this._safeIsoDate(state.lastRoundAt);
        if (incomingLastRoundAt) {
          if (incomingLastRoundAt !== this._lastRoundAtIso) {
            this._lastRoundAtIso = incomingLastRoundAt;
            this._fallbackRoundAnchorMs = null;
            this._lastTimerSecond = null;
          }
        } else if (!this._lastRoundAtIso) {
          this._syncFallbackRoundAnchor(this._stateLastModified);
        }
        this._updateTimerFromAnchor();
      })
      .catch(() => {
        // no-op
      })
      .finally(() => {
        this._liveStateSyncInFlight = false;
      });
  }

  _applyLoadedState(state) {
    if (!state) {
      return;
    }

    this._syncServerClock(state.serverNow);
    this.coins = Number(state.score ?? this.coins);
    this.lastResults = this._parseLast10Results(state.last10Results);
    this.currentNumber = this.lastResults[0] ?? this.currentNumber;
    this.winnerValue = Number(state.winnerAmount ?? this.winnerValue);
    this.pendingPayout = Number(state.winnerAmount ?? this.pendingPayout);
    this.betsByNumber = this._parseBetsJson(state.betsJson);
    this._predefinedWheelNumber = this._normalizeWheelNumber(
      state.predefinedWheelNumber
    );
    this.selectedNumbers = Object.keys(this.betsByNumber).map(Number);
    this.selectedNumber =
      this.selectedNumbers[this.selectedNumbers.length - 1] ?? null;
    this._lastRoundAtIso = this._safeIsoDate(state.lastRoundAt);
    this._stateLastModified = this._safeIsoDate(state.lastModifiedDate);
    if (this._lastRoundAtIso) {
      this._fallbackRoundAnchorMs = null;
    } else {
      this._syncFallbackRoundAnchor(this._stateLastModified);
    }
    this._lastTimerSecond = null;
    this._updateTimerFromAnchor();
    this._refreshRoundPhase();
  }

  _parseLast10Results(value) {
    if (!value || typeof value !== "string") {
      return [...DEFAULT_LAST_RESULTS];
    }
    const parsed = value
      .split(",")
      .map((item) => Number(item.trim()))
      .filter((item) => Number.isInteger(item) && item >= 0 && item <= 9)
      .slice(0, 10);

    return parsed.length ? parsed : [...DEFAULT_LAST_RESULTS];
  }

  _parseBetsJson(value) {
    if (!value) {
      return {};
    }
    try {
      const parsed = JSON.parse(value);
      if (!parsed || typeof parsed !== "object") {
        return {};
      }

      return Object.keys(parsed).reduce((acc, key) => {
        const numericKey = Number(key);
        const numericValue = Number(parsed[key]);
        if (
          Number.isInteger(numericKey) &&
          numericKey >= 0 &&
          numericKey <= 9 &&
          numericValue > 0
        ) {
          acc[numericKey] = numericValue;
        }
        return acc;
      }, {});
    } catch (error) {
      return {};
    }
  }

  _normalizeWheelNumber(value) {
    if (value === null || value === undefined || value === "") {
      return null;
    }
    const parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 0 || parsed > 9) {
      return null;
    }
    return parsed;
  }

  _safeIsoDate(value) {
    if (!value) {
      return null;
    }
    try {
      const dateValue = new Date(value);
      if (Number.isNaN(dateValue.getTime())) {
        return null;
      }
      return dateValue.toISOString();
    } catch (error) {
      return null;
    }
  }

  _buildStatePayload() {
    return {
      score: Math.max(0, this.coins),
      last10Results: this.lastResults.join(","),
      totalBetAmount: this.totalBetAmount,
      winnerAmount: this.winnerValue,
      betsJson: JSON.stringify(this.betsByNumber),
      lastUpdatedFrom: "Site",
      lastRoundAt: this._lastRoundAtIso
    };
  }

  _queueStateSave(immediate = false) {
    if (!this._stateInitialized) {
      this._pendingSaveBeforeInit = true;
      return;
    }

    this._stateDirty = true;
    if (this._stateSaveTimer) {
      window.clearTimeout(this._stateSaveTimer);
      this._stateSaveTimer = null;
    }

    if (immediate) {
      this._flushStateSave();
      return;
    }

    this._stateSaveTimer = window.setTimeout(() => {
      this._flushStateSave();
    }, SAVE_DEBOUNCE_MS);
  }

  _flushStateSave() {
    if (!this._stateDirty || this._stateSaveInFlight) {
      return;
    }

    const payload = this._buildStatePayload();
    const payloadHash = JSON.stringify(payload);
    if (payloadHash === this._lastSavedStateHash) {
      this._stateDirty = false;
      return;
    }

    this._stateDirty = false;
    this._stateSaveInFlight = true;

    saveState({ payload, expectedLastModified: this._stateLastModified })
      .then((state) => {
        this._lastSavedStateHash = payloadHash;
        if (state) {
          this._applyLoadedState(state);
          this._lastSavedStateHash = JSON.stringify(this._buildStatePayload());
        }
      })
      .catch((error) => {
        const message = error?.body?.message || error?.message || "";
        if (message.includes("STATE_CONFLICT")) {
          // Conflict can happen if admin/site writes overlap.
          // Clear lock token once and retry local payload so bets don't get stuck unsaved.
          this._stateLastModified = null;
          this._stateDirty = true;
          return;
        }
        this._stateDirty = true;
      })
      .finally(() => {
        this._stateSaveInFlight = false;
        if (this._stateDirty) {
          this._queueStateSave();
        }
      });
  }

  _applySiteIntent(intent, extras = {}) {
    const requestPayload = {
      request: {
        intent,
        ...extras
      },
      expectedLastModified: this._stateLastModified
    };

    const attemptIntent = (attempt, expectedLastModified) =>
      applySiteIntentFlat({
        intent: requestPayload.request.intent,
        betsJson: requestPayload.request.betsJson,
        expectedLastModified
      })
        .then((state) => {
          if (state) {
            this._applyLoadedState(state);
            this._lastSavedStateHash = JSON.stringify(
              this._buildStatePayload()
            );
          }
          return state;
        })
        .catch((error) => {
          const message = String(error?.body?.message || error?.message || "");
          const normalized = message.toUpperCase();
          const isConflict = normalized.includes("STATE_CONFLICT");
          const isLockContention =
            normalized.includes("UNABLE_TO_LOCK_ROW") ||
            normalized.includes("EXCLUSIVE ACCESS");

          if ((isConflict || isLockContention) && attempt < 2) {
            this._stateLastModified = null;
            return this._delay((attempt + 1) * 120).then(() =>
              attemptIntent(attempt + 1, null)
            );
          }
          throw error;
        });

    return attemptIntent(0, requestPayload.expectedLastModified);
  }

  _persistBetsState() {
    this._betPersistQueued = true;
    if (this._betPersistInFlight) {
      return this._betPersistPromise || Promise.resolve();
    }

    this._betPersistInFlight = true;
    this._betPersistPromise = this._flushBetPersistQueue().finally(() => {
      this._betPersistInFlight = false;
      this._betPersistPromise = null;
    });
    return this._betPersistPromise;
  }

  async _flushBetPersistQueue() {
    let retryCount = 0;
    while (this._betPersistQueued) {
      this._betPersistQueued = false;
      const betsJson = JSON.stringify(this.betsByNumber || {});
      try {
        await this._applySiteIntent("PLACE_BET", { betsJson });
        retryCount = 0;
      } catch (error) {
        if (this._isRetryableBetPersistError(error) && retryCount < 4) {
          retryCount += 1;
          this._betPersistQueued = true;
          await this._delay(retryCount * 120);
          continue;
        }
        retryCount = 0;
        this._syncStateFromServer();
      }
    }
  }

  _isRetryableBetPersistError(error) {
    const message = String(
      error?.body?.message || error?.message || ""
    ).toLowerCase();
    return (
      message.includes("state_conflict") ||
      message.includes("unable_to_lock_row") ||
      message.includes("exclusive access") ||
      message.includes("timeout") ||
      message.includes("network") ||
      message.includes("invalid session")
    );
  }

  _delay(ms) {
    return new Promise((resolve) => {
      window.setTimeout(resolve, ms);
    });
  }

  _setBetOkHighlighted(isHighlighted) {
    this.isBetOkHighlighted = isHighlighted;
    const value = isHighlighted ? "1" : "0";

    try {
      window.localStorage.setItem(BET_OK_HIGHLIGHT_STORAGE_KEY, value);
    } catch (error) {
      // no-op
    }

    try {
      window.sessionStorage.setItem(BET_OK_HIGHLIGHT_STORAGE_KEY, value);
    } catch (error) {
      // no-op
    }
  }

  _restoreBetOkHighlight() {
    let saved = null;

    try {
      saved = window.localStorage.getItem(BET_OK_HIGHLIGHT_STORAGE_KEY);
    } catch (error) {
      // no-op
    }

    if (saved === null) {
      try {
        saved = window.sessionStorage.getItem(BET_OK_HIGHLIGHT_STORAGE_KEY);
      } catch (error) {
        // no-op
      }
    }

    this.isBetOkHighlighted = saved === "1" || saved === "true";
  }

  _scheduleScaleUpdate() {
    if (this._resizeRafId) {
      return;
    }
    this._resizeRafId = window.requestAnimationFrame(() => {
      this._resizeRafId = null;
      this._applyResponsiveScale();
    });
  }

  _applyResponsiveScale() {
    const frame = this.template.querySelector(".frame");
    if (!frame) {
      return;
    }
    const width = frame.getBoundingClientRect().width;
    if (!width || width <= 0) {
      return;
    }
    const scale = width / 1024;
    if (Math.abs(scale - this._lastAppliedScale) < 0.001) {
      return;
    }
    this._lastAppliedScale = scale;
    this.template.host.style.setProperty("--scale", scale.toString());
  }

  _initializeSounds() {
    this._sounds = Object.keys(SOUND_FILES).reduce((acc, key) => {
      const audio = new Audio(SOUND_FILES[key]);
      audio.preload = "auto";
      acc[key] = audio;
      return acc;
    }, {});
  }

  _disposeSounds() {
    Object.values(this._sounds).forEach((audio) => {
      try {
        audio.pause();
        audio.currentTime = 0;
      } catch (error) {
        // no-op
      }
    });
    this._sounds = {};
  }

  _registerAudioUnlockListeners() {
    if (this._audioUnlockHandler) {
      return;
    }
    this._audioUnlockHandler = () => {
      this._unlockAudioFromGesture();
    };
    window.addEventListener("pointerdown", this._audioUnlockHandler, true);
    window.addEventListener("touchstart", this._audioUnlockHandler, true);
    window.addEventListener("keydown", this._audioUnlockHandler, true);
  }

  _unregisterAudioUnlockListeners() {
    if (!this._audioUnlockHandler) {
      return;
    }
    window.removeEventListener("pointerdown", this._audioUnlockHandler, true);
    window.removeEventListener("touchstart", this._audioUnlockHandler, true);
    window.removeEventListener("keydown", this._audioUnlockHandler, true);
    this._audioUnlockHandler = null;
  }

  _tryWarmupAudio() {
    // Some browsers allow muted autoplay on load. If successful, wheel sounds work after refresh.
    this._unlockAudio(true);
  }

  _unlockAudioFromGesture() {
    this._unlockAudio(false);
  }

  _unlockAudio(isMutedWarmup) {
    if (this._audioUnlocked || this._audioUnlockInProgress) {
      return;
    }
    const sampleAudio =
      this._sounds.button || this._sounds.bet || Object.values(this._sounds)[0];
    if (!sampleAudio) {
      return;
    }

    this._audioUnlockInProgress = true;
    try {
      sampleAudio.muted = !!isMutedWarmup;
      const playPromise = sampleAudio.play();
      if (playPromise && typeof playPromise.then === "function") {
        playPromise
          .then(() => {
            sampleAudio.pause();
            sampleAudio.currentTime = 0;
            sampleAudio.muted = false;
            this._audioUnlocked = true;
            this._unregisterAudioUnlockListeners();
            if (this._pendingSoundKey) {
              const pending = this._pendingSoundKey;
              this._pendingSoundKey = null;
              this._playSound(pending);
            }
          })
          .catch(() => {
            sampleAudio.muted = false;
          })
          .finally(() => {
            this._audioUnlockInProgress = false;
          });
        return;
      }
      sampleAudio.pause();
      sampleAudio.currentTime = 0;
      sampleAudio.muted = false;
      this._audioUnlocked = true;
      this._unregisterAudioUnlockListeners();
      this._audioUnlockInProgress = false;
    } catch (error) {
      sampleAudio.muted = false;
      this._audioUnlockInProgress = false;
    }
  }

  _playLoadingSoundOnce() {
    if (this._soundLoadingPlayed) {
      return;
    }
    this._soundLoadingPlayed = true;
    this._playSound("loading");
  }

  _playSound(key, options = {}) {
    const { queueOnBlock = true } = options;
    const audio = this._sounds[key];
    if (!audio) {
      return;
    }
    try {
      audio.pause();
      audio.currentTime = 0;
      const playPromise = audio.play();
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {
          if (!queueOnBlock) {
            return;
          }
          // If blocked, queue this sound and retry after any user interaction.
          this._pendingSoundKey = key;
          this._registerAudioUnlockListeners();
        });
      }
    } catch (error) {
      if (!queueOnBlock) {
        return;
      }
      this._pendingSoundKey = key;
      this._registerAudioUnlockListeners();
    }
  }

  _stopSound(key) {
    const audio = this._sounds[key];
    if (!audio) {
      return;
    }
    try {
      audio.pause();
      audio.currentTime = 0;
    } catch (error) {
      // no-op
    }
  }

  _betsSignature() {
    return BET_NUMBER_ORDER.map(
      (value) => `${value}:${this.betsByNumber[value] || 0}`
    ).join("|");
  }

  _betButtonClass(value) {
    const hasBet = (this.betsByNumber[value] || 0) > 0;
    const isResult = this.highlightedBetNumber === value;
    return `bet-number-btn${hasBet ? " selected" : ""}${isResult ? " result" : ""}`;
  }
}
