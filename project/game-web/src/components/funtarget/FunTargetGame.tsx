"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSupabaseClient } from "../../lib/supabaseClient";
import type { FunTargetStateRow } from "../../lib/types";
import { LogoAnimator } from "./LogoAnimator";
import styles from "./FunTargetGame.module.css";

const SEGMENTS = 10;
const SEGMENT_ANGLE = 360 / SEGMENTS;
const POINTER_ALIGNMENT_OFFSET = 0;
const BET_BUTTON_LEFT_SHIFT = -15;
const BET_NUMBER_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] as const;
const BET_OK_HIGHLIGHT_STORAGE_KEY = "funTargetGame.betOkHighlighted";
const DEFAULT_FOOTER_MESSAGE = "You can either Make a Bet or press BET OK button";
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

type RoundPhase = "BETTING" | "SPINNING" | "RESULT" | "LOCKED";

const ROUND_PHASE: Record<RoundPhase, RoundPhase> = {
  BETTING: "BETTING",
  SPINNING: "SPINNING",
  RESULT: "RESULT",
  LOCKED: "LOCKED",
};

const ASSET_BASE = "/funTargrtAsset/media/FunTargetImages";
const SOUND_BASE = "/funTargrtAsset/Sounds";
const SOUND_FILES: Record<string, string> = {
  bet: `${SOUND_BASE}/bet.wav`,
  button: `${SOUND_BASE}/button.WAV`,
  exit: `${SOUND_BASE}/exit.wav`,
  loading: `${SOUND_BASE}/loading.wav`,
  lose: `${SOUND_BASE}/lose.wav`,
  take: `${SOUND_BASE}/take.wav`,
  wheelEnd: `${SOUND_BASE}/wheelEnd.wav`,
  wheelStart: `${SOUND_BASE}/wheelStart.wav`,
  win: `${SOUND_BASE}/win.WAV`,
};

const COIN_BUTTONS = [
  { value: 1, image: `${ASSET_BASE}/oneCoin.jpg`, left: 0, top: 369 },
  { value: 5, image: `${ASSET_BASE}/fiveCoin.jpg`, left: 58, top: 369 },
  { value: 10, image: `${ASSET_BASE}/tenCoin.jpg`, left: 115, top: 369 },
  { value: 50, image: `${ASSET_BASE}/fiftyCoin.jpg`, left: 172, top: 369 },
  { value: 100, image: `${ASSET_BASE}/hundredCoin.jpg`, left: 798, top: 369 },
  { value: 500, image: `${ASSET_BASE}/fiveHundredCoin.jpg`, left: 855, top: 369 },
  { value: 1000, image: `${ASSET_BASE}/thousandCoin.jpg`, left: 910, top: 369 },
  { value: 5000, image: `${ASSET_BASE}/fiveThousandCoin.jpg`, left: 968, top: 369 },
];

const BET_NUMBER_ROW_TOP = 657;
const BET_NUMBER_START_LEFT = 25;
const BET_NUMBER_STEP = 103;
const BET_AMOUNT_ROW_TOP = BET_NUMBER_ROW_TOP - 26;
const BET_NUMBER_BUTTONS = BET_NUMBER_ORDER.map((value, index) => ({
  value,
  left: BET_NUMBER_START_LEFT + index * BET_NUMBER_STEP,
  top: BET_NUMBER_ROW_TOP,
}));

type PrevBet = {
  betsByNumber: Record<number, number>;
  numbers: number[];
  number: number | null;
  chip: number;
};

function normalizeBetsJson(value: unknown): Record<number, number> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const obj = value as Record<string, unknown>;
  const out: Record<number, number> = {};
  for (const key of Object.keys(obj)) {
    const numericKey = Number(key);
    const numericValue = Number(obj[key]);
    if (
      Number.isInteger(numericKey) &&
      numericKey >= 0 &&
      numericKey <= 9 &&
      Number.isFinite(numericValue) &&
      numericValue > 0
    ) {
      out[numericKey] = numericValue;
    }
  }
  return out;
}

function normalizeWheelNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 9) return null;
  return parsed;
}

function safeIso(value: unknown): string | null {
  if (!value) return null;
  try {
    const d = new Date(String(value));
    if (Number.isNaN(d.getTime())) return null;
    return d.toISOString();
  } catch {
    return null;
  }
}

export function FunTargetGame() {
  const supabase = getSupabaseClient();

  const hostRef = useRef<HTMLDivElement | null>(null);
  const timeValueRef = useRef<HTMLDivElement | null>(null);

  const [email, setEmail] = useState<string | null>(null);
  const [userId, setUserId] = useState<string | null>(null);

  const [selectedNumber, setSelectedNumber] = useState<number | null>(null);
  const [selectedNumbers, setSelectedNumbers] = useState<number[]>([]);
  const [betsByNumber, setBetsByNumber] = useState<Record<number, number>>({});
  const [pendingPayout, setPendingPayout] = useState<number>(0);
  const [winnerValue, setWinnerValue] = useState<number>(0);
  const [highlightedBetNumber, setHighlightedBetNumber] = useState<number | null>(null);
  const [isBetOkHighlighted, setIsBetOkHighlighted] = useState<boolean>(false);
  const [isBetConfirmed, setIsBetConfirmed] = useState<boolean>(false);
  const [showPrevBet, setShowPrevBet] = useState<boolean>(false);
  const [selectedChip, setSelectedChip] = useState<number>(1);
  const [currentNumber, setCurrentNumber] = useState<number>(0);
  const [coins, setCoins] = useState<number>(1000);
  const [rotation, setRotation] = useState<number>(0);
  const [isSpinning, setIsSpinning] = useState<boolean>(false);
  const [lastResults, setLastResults] = useState<number[]>([...DEFAULT_LAST_RESULTS]);
  const [footerMessage, setFooterMessage] = useState<string>(DEFAULT_FOOTER_MESSAGE);
  const [isFinalTenSeconds, setIsFinalTenSeconds] = useState<boolean>(false);
  const [logoResetToken, setLogoResetToken] = useState<number>(0);
  const [roundPhase, setRoundPhase] = useState<RoundPhase>(ROUND_PHASE.BETTING);
  const [spinDuration, setSpinDuration] = useState<string>("2.8s");
  const [spinEasing, setSpinEasing] = useState<string>("cubic-bezier(0.22, 0.9, 0.26, 1.05)");

  const prevBetRef = useRef<PrevBet | null>(null);

  const timerTextRef = useRef<string>("0:59");
  const timeLeftSecondsRef = useRef<number>(59);
  const lastTimerSecondRef = useRef<number | null>(null);

  const autoSpinActiveRef = useRef<boolean>(false);
  const autoSpinResultRef = useRef<number | null>(null);
  const roundPredefinedNumberRef = useRef<number | null>(null);
  const predefinedWheelNumberRef = useRef<number | null>(null);
  const roundStartInProgressRef = useRef<boolean>(false);

  const countdownTimerRef = useRef<number | null>(null);
  const spinRafRef = useRef<number | null>(null);
  const spinTimerRef = useRef<number | null>(null);

  const resizeRafRef = useRef<number | null>(null);
  const lastAppliedScaleRef = useRef<number>(1);

  const stateInitializedRef = useRef<boolean>(false);
  const stateDirtyRef = useRef<boolean>(false);
  const stateSaveInFlightRef = useRef<boolean>(false);
  const stateSaveTimerRef = useRef<number | null>(null);
  const lastSavedStateHashRef = useRef<string>("");
  const lastRoundAtIsoRef = useRef<string | null>(null);
  const fallbackRoundAnchorMsRef = useRef<number | null>(null);

  const liveStateSyncTimerRef = useRef<number | null>(null);
  const liveStateSyncInFlightRef = useRef<boolean>(false);

  const soundsRef = useRef<Record<string, HTMLAudioElement>>({});
  const soundLoadingPlayedRef = useRef<boolean>(false);
  const audioUnlockedRef = useRef<boolean>(false);
  const audioUnlockInProgressRef = useRef<boolean>(false);
  const pendingSoundKeyRef = useRef<string | null>(null);
  const audioUnlockHandlerRef = useRef<(() => void) | null>(null);

  const stageStyle = useMemo(() => ({ backgroundImage: `url(${ASSET_BASE}/Bg.jpg)` }), []);
  const wheelUrl = `${ASSET_BASE}/Wheel5.png`;
  const arrowUrl = `${ASSET_BASE}/Arrow.png`;
  const arrowGlowUrl = `${ASSET_BASE}/ArrowGlow.png`;
  const targetTimeGlowUrl = `${ASSET_BASE}/TargetTimeGlow.jpg`;
  const targetTimeOffUrl = `${ASSET_BASE}/TargetTimeGlow2.png`;
  const titleUrl = `${ASSET_BASE}/Title.png`;

  const takeGlowUrl = `${ASSET_BASE}/Take_Glow.jpg`;
  const takeOffUrl = `${ASSET_BASE}/Take_Glow2.png`;
  const betOkGlowUrl = `${ASSET_BASE}/BetOk_Glow.jpg`;
  const betOkOffUrl = `${ASSET_BASE}/BetOk_Glow2.png`;
  const cancelGlowUrl = `${ASSET_BASE}/Cancel-Bet-Glow.png`;
  const cancelOffUrl = `${ASSET_BASE}/Cancel-Bet.png`;
  const prevGlowUrl = `${ASSET_BASE}/PrevBetGlow.jpg`;
  const prevOffUrl = `${ASSET_BASE}/PrevBetGlow2.png`;
  const exitGlowUrl = `${ASSET_BASE}/exit_Glow.png`;
  const exitOffUrl = `${ASSET_BASE}/exit_Glow2.png`;

  const totalBetAmount = useMemo(
    () => Object.values(betsByNumber).reduce((sum, amount) => sum + amount, 0),
    [betsByNumber]
  );

  const lastResultsText = useMemo(() => [...lastResults].reverse().join(" "), [lastResults]);

  const shouldBlinkBetOk = useMemo(
    () => !showPrevBet && !isBetConfirmed && totalBetAmount > 0,
    [isBetConfirmed, showPrevBet, totalBetAmount]
  );

  const isGlowDisabledWindow = useMemo(
    () => !isSpinning && isFinalTenSeconds,
    [isFinalTenSeconds, isSpinning]
  );

  const arrowStackClassName = useMemo(() => {
    const classes = [styles["arrow-stack"]];
    if (isSpinning) classes.push(styles.spinning);
    if (isGlowDisabledWindow) classes.push(styles["no-glow"]);
    return classes.join(" ");
  }, [isGlowDisabledWindow, isSpinning]);

  const timerGlowClassName = useMemo(() => {
    const classes = [styles["timer-glow-stack"]];
    if (isFinalTenSeconds) classes.push(styles.blinking);
    return classes.join(" ");
  }, [isFinalTenSeconds]);

  const isBetNumberDisabled = useMemo(
    () => roundPhase !== ROUND_PHASE.BETTING || isBetConfirmed,
    [isBetConfirmed, roundPhase]
  );

  const isBetOkDisabled = useMemo(
    () => roundPhase !== ROUND_PHASE.BETTING || isBetConfirmed || totalBetAmount <= 0,
    [isBetConfirmed, roundPhase, totalBetAmount]
  );

  const betOkButtonClassName = useMemo(() => {
    const classes = [styles["action-btn"], styles.betok];
    if (showPrevBet) classes.push(styles.hidden);
    if (shouldBlinkBetOk) classes.push(styles.blink);
    return classes.join(" ");
  }, [shouldBlinkBetOk, showPrevBet]);

  const prevButtonClassName = useMemo(() => {
    const classes = [styles["action-btn"], styles.prev];
    if (showPrevBet) classes.push(styles.blink);
    else classes.push(styles.hidden);
    return classes.join(" ");
  }, [showPrevBet]);

  const takeButtonClassName = useMemo(() => {
    const classes = [styles["action-btn"], styles.take];
    if (pendingPayout > 0) classes.push(styles.blink);
    return classes.join(" ");
  }, [pendingPayout]);

  const coinButtons = useMemo(
    () =>
      COIN_BUTTONS.map((item) => ({
        ...item,
        isSelected: selectedChip === item.value,
        ariaLabel: `Select coin ${item.value}`,
        className: [styles["coin-btn"], selectedChip === item.value ? styles.active : ""]
          .filter(Boolean)
          .join(" "),
        style: { left: item.left, top: item.top } as React.CSSProperties,
      })),
    [selectedChip]
  );

  const betsSignature = useMemo(
    () => BET_NUMBER_ORDER.map((value) => `${value}:${betsByNumber[value] || 0}`).join("|"),
    [betsByNumber]
  );

  const betNumberButtons = useMemo(() => {
    return BET_NUMBER_BUTTONS.map((item) => {
      const hasBet = (betsByNumber[item.value] || 0) > 0;
      const isResult = highlightedBetNumber === item.value;
      const className = [
        styles["bet-number-btn"],
        hasBet ? styles.selected : "",
        isResult ? styles.result : "",
      ]
        .filter(Boolean)
        .join(" ");
      return {
        value: item.value,
        ariaLabel: `Bet ${item.value}`,
        glowUrl: `${ASSET_BASE}/BetGlow${item.value}.jpg`,
        className,
        isDisabled: isBetNumberDisabled,
        style: { left: item.left + BET_BUTTON_LEFT_SHIFT, top: item.top } as React.CSSProperties,
      };
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [betsSignature, highlightedBetNumber, isBetNumberDisabled]);

  const betAmountVisuals = useMemo(() => {
    return BET_NUMBER_BUTTONS.filter((slot) => (betsByNumber[slot.value] || 0) > 0).map((slot) => ({
      key: `bet-amount-${slot.value}`,
      value: betsByNumber[slot.value],
      style: { left: slot.left + BET_BUTTON_LEFT_SHIFT, top: BET_AMOUNT_ROW_TOP } as React.CSSProperties,
    }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [betsSignature]);

  const wheelStyle = useMemo(() => {
    return {
      ["--wheel-rot" as any]: `${rotation}deg`,
      ["--spin-duration" as any]: spinDuration,
      ["--spin-easing" as any]: spinEasing,
    } as React.CSSProperties;
  }, [rotation, spinDuration, spinEasing]);

  const setBetOkHighlighted = useCallback((isHighlighted: boolean) => {
    setIsBetOkHighlighted(isHighlighted);
    const value = isHighlighted ? "1" : "0";
    try {
      window.localStorage.setItem(BET_OK_HIGHLIGHT_STORAGE_KEY, value);
    } catch {
      // ignore
    }
    try {
      window.sessionStorage.setItem(BET_OK_HIGHLIGHT_STORAGE_KEY, value);
    } catch {
      // ignore
    }
  }, []);

  const restoreBetOkHighlight = useCallback(() => {
    let saved: string | null = null;
    try {
      saved = window.localStorage.getItem(BET_OK_HIGHLIGHT_STORAGE_KEY);
    } catch {
      // ignore
    }
    if (saved === null) {
      try {
        saved = window.sessionStorage.getItem(BET_OK_HIGHLIGHT_STORAGE_KEY);
      } catch {
        // ignore
      }
    }
    setIsBetOkHighlighted(saved === "1" || saved === "true");
  }, []);

  const initializeSounds = useCallback(() => {
    const sounds: Record<string, HTMLAudioElement> = {};
    for (const key of Object.keys(SOUND_FILES)) {
      const audio = new Audio(SOUND_FILES[key] ?? "");
      audio.preload = "auto";
      sounds[key] = audio;
    }
    soundsRef.current = sounds;
  }, []);

  const disposeSounds = useCallback(() => {
    for (const audio of Object.values(soundsRef.current)) {
      try {
        audio.pause();
        audio.currentTime = 0;
      } catch {
        // ignore
      }
    }
    soundsRef.current = {};
  }, []);

  const unregisterAudioUnlockListeners = useCallback(() => {
    if (!audioUnlockHandlerRef.current) return;
    window.removeEventListener("pointerdown", audioUnlockHandlerRef.current, true);
    window.removeEventListener("touchstart", audioUnlockHandlerRef.current, true);
    window.removeEventListener("keydown", audioUnlockHandlerRef.current, true);
    audioUnlockHandlerRef.current = null;
  }, []);

  const unlockAudio = useCallback(
    (isMutedWarmup: boolean) => {
      if (audioUnlockedRef.current || audioUnlockInProgressRef.current) return;
      const sampleAudio =
        soundsRef.current.button ||
        soundsRef.current.bet ||
        Object.values(soundsRef.current)[0];
      if (!sampleAudio) return;

      audioUnlockInProgressRef.current = true;
      try {
        sampleAudio.muted = !!isMutedWarmup;
        const playPromise = sampleAudio.play();
        if (playPromise && typeof (playPromise as Promise<void>).then === "function") {
          (playPromise as Promise<void>)
            .then(() => {
              sampleAudio.pause();
              sampleAudio.currentTime = 0;
              sampleAudio.muted = false;
              audioUnlockedRef.current = true;
              unregisterAudioUnlockListeners();
              if (pendingSoundKeyRef.current) {
                const pending = pendingSoundKeyRef.current;
                pendingSoundKeyRef.current = null;
                // fire and forget
                try {
                  soundsRef.current[pending]?.play();
                } catch {
                  // ignore
                }
              }
            })
            .catch(() => {
              sampleAudio.muted = false;
            })
            .finally(() => {
              audioUnlockInProgressRef.current = false;
            });
          return;
        }

        sampleAudio.pause();
        sampleAudio.currentTime = 0;
        sampleAudio.muted = false;
        audioUnlockedRef.current = true;
        unregisterAudioUnlockListeners();
      } catch {
        sampleAudio.muted = false;
      } finally {
        audioUnlockInProgressRef.current = false;
      }
    },
    [unregisterAudioUnlockListeners]
  );

  const registerAudioUnlockListeners = useCallback(() => {
    if (audioUnlockHandlerRef.current) return;
    audioUnlockHandlerRef.current = () => unlockAudio(false);
    window.addEventListener("pointerdown", audioUnlockHandlerRef.current, true);
    window.addEventListener("touchstart", audioUnlockHandlerRef.current, true);
    window.addEventListener("keydown", audioUnlockHandlerRef.current, true);
  }, [unlockAudio]);

  const playSound = useCallback(
    (key: string, opts: { queueOnBlock?: boolean } = {}) => {
      const { queueOnBlock = true } = opts;
      const audio = soundsRef.current[key];
      if (!audio) return;
      try {
        audio.pause();
        audio.currentTime = 0;
        const p = audio.play();
        if (p && typeof (p as Promise<void>).catch === "function") {
          (p as Promise<void>).catch(() => {
            if (!queueOnBlock) return;
            pendingSoundKeyRef.current = key;
            registerAudioUnlockListeners();
          });
        }
      } catch {
        if (!queueOnBlock) return;
        pendingSoundKeyRef.current = key;
        registerAudioUnlockListeners();
      }
    },
    [registerAudioUnlockListeners]
  );

  const stopSound = useCallback((key: string) => {
    const audio = soundsRef.current[key];
    if (!audio) return;
    try {
      audio.pause();
      audio.currentTime = 0;
    } catch {
      // ignore
    }
  }, []);

  const playLoadingSoundOnce = useCallback(() => {
    if (soundLoadingPlayedRef.current) return;
    soundLoadingPlayedRef.current = true;
    playSound("loading");
  }, [playSound]);

  const renderTimerTextToDom = useCallback(() => {
    if (!timeValueRef.current) return;
    if (timeValueRef.current.textContent === timerTextRef.current) return;
    timeValueRef.current.textContent = timerTextRef.current;
  }, []);

  const updateTimerText = useCallback(() => {
    const seconds = String(timeLeftSecondsRef.current).padStart(2, "0");
    timerTextRef.current = `0:${seconds}`;
    renderTimerTextToDom();
  }, [renderTimerTextToDom]);

  const getRoundAnchorMs = useCallback(() => {
    if (lastRoundAtIsoRef.current) {
      const parsed = new Date(lastRoundAtIsoRef.current).getTime();
      if (Number.isFinite(parsed)) return parsed;
    }
    if (fallbackRoundAnchorMsRef.current !== null && Number.isFinite(fallbackRoundAnchorMsRef.current)) {
      return fallbackRoundAnchorMsRef.current;
    }
    fallbackRoundAnchorMsRef.current = Date.now() - ANCHOR_SHIFT_TO_59_MS;
    return fallbackRoundAnchorMsRef.current;
  }, []);

  const computeTimerSecond = useCallback(() => {
    const anchorMs = getRoundAnchorMs();
    if (!Number.isFinite(anchorMs)) return 59;
    const elapsedSeconds = Math.max(0, Math.floor((Date.now() - anchorMs) / 1000));
    return (SPIN_RESULT_SECOND - (elapsedSeconds % ROUND_SECONDS) + ROUND_SECONDS) % ROUND_SECONDS;
  }, [getRoundAnchorMs]);

  const crossedTimerSecond = useCallback((prev: number | null, curr: number, target: number) => {
    if (prev === null || prev === undefined) return curr === target;
    if (prev === curr) return false;
    let cursor = prev;
    for (let idx = 0; idx < ROUND_SECONDS; idx += 1) {
      cursor = (cursor - 1 + ROUND_SECONDS) % ROUND_SECONDS;
      if (cursor === target) return true;
      if (cursor === curr) return false;
    }
    return false;
  }, []);

  const refreshRoundPhase = useCallback(() => {
    let next: RoundPhase = ROUND_PHASE.BETTING;
    if (isSpinning) next = ROUND_PHASE.SPINNING;
    else if (pendingPayout > 0) next = ROUND_PHASE.RESULT;
    else if (isFinalTenSeconds) next = ROUND_PHASE.LOCKED;
    if (next !== roundPhase) setRoundPhase(next);
  }, [isFinalTenSeconds, isSpinning, pendingPayout, roundPhase]);

  const syncFinalTenState = useCallback(() => {
    const isFinalTen = timeLeftSecondsRef.current >= 0 && timeLeftSecondsRef.current <= 10;
    if (isFinalTen !== isFinalTenSeconds) {
      setIsFinalTenSeconds(isFinalTen);
      restartLiveStateSync();
    }
    // round phase depends on final ten
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isFinalTenSeconds]);

  const handleTimerSecondChange = useCallback(
    (prev: number | null, curr: number) => {
      syncFinalTenState();
      if (!stateInitializedRef.current) return;

      if (crossedTimerSecond(prev, curr, RESULT_HIGHLIGHT_CLEAR_SECOND)) {
        setHighlightedBetNumber(null);
      }

      if (crossedTimerSecond(prev, curr, FINAL_TEN_SECOND)) {
        setBetOkHighlighted(false);
      }

      if (crossedTimerSecond(prev, curr, PAYOUT_FORFEIT_SECOND)) {
        if (winnerValue > 0 || pendingPayout > 0) {
          setWinnerValue(0);
          setPendingPayout(0);
          queueStateSave(true);
        }
      }

      if (crossedTimerSecond(prev, curr, SPIN_START_SECOND)) {
        startAutoSpinRound();
      }

      if (autoSpinActiveRef.current && crossedTimerSecond(prev, curr, SPIN_RESULT_SECOND)) {
        finalizeAutoSpinRound();
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [crossedTimerSecond, pendingPayout, winnerValue]
  );

  const updateTimerFromAnchor = useCallback(() => {
    const nextSecond = computeTimerSecond();
    if (nextSecond === lastTimerSecondRef.current) return;

    const prev = lastTimerSecondRef.current;
    lastTimerSecondRef.current = nextSecond;
    timeLeftSecondsRef.current = nextSecond;
    handleTimerSecondChange(prev, nextSecond);
    updateTimerText();
    refreshRoundPhase();
  }, [computeTimerSecond, handleTimerSecondChange, refreshRoundPhase, updateTimerText]);

  const runCountdownTick = useCallback(() => {
    countdownTimerRef.current = null;
    updateTimerFromAnchor();

    const nowMs = Date.now();
    const msToNextSecond = 1000 - (nowMs % 1000);
    const nextDelay = Math.min(1000, Math.max(120, msToNextSecond + 12));
    countdownTimerRef.current = window.setTimeout(() => runCountdownTick(), nextDelay);
  }, [updateTimerFromAnchor]);

  const startCountdown = useCallback(() => {
    if (countdownTimerRef.current) return;
    runCountdownTick();
  }, [runCountdownTick]);

  const stopCountdown = useCallback(() => {
    if (!countdownTimerRef.current) return;
    window.clearTimeout(countdownTimerRef.current);
    countdownTimerRef.current = null;
  }, []);

  const delay = useCallback((ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms)), []);

  const buildStatePayload = useCallback(() => {
    return {
      score: Math.max(0, coins),
      last10_results: lastResults,
      total_bet_amount: totalBetAmount,
      winner_amount: winnerValue,
      bets_json: betsByNumber,
      last_updated_from: "Site",
      last_round_at: lastRoundAtIsoRef.current,
    };
  }, [betsByNumber, coins, lastResults, totalBetAmount, winnerValue]);

  const flushStateSave = useCallback(async () => {
    if (!supabase || !userId) return;
    if (!stateDirtyRef.current || stateSaveInFlightRef.current) return;

    const payload = buildStatePayload();
    const payloadHash = JSON.stringify(payload);
    if (payloadHash === lastSavedStateHashRef.current) {
      stateDirtyRef.current = false;
      return;
    }

    stateDirtyRef.current = false;
    stateSaveInFlightRef.current = true;
    try {
      const { error } = await supabase
        .from("fun_target_state")
        .update(payload)
        .eq("user_id", userId);
      if (error) throw error;
      lastSavedStateHashRef.current = payloadHash;
    } catch {
      stateDirtyRef.current = true;
    } finally {
      stateSaveInFlightRef.current = false;
      if (stateDirtyRef.current) queueStateSave();
    }
  }, [buildStatePayload, supabase, userId]);

  const queueStateSave = useCallback(
    (immediate = false) => {
      if (!stateInitializedRef.current) return;

      stateDirtyRef.current = true;
      if (stateSaveTimerRef.current) {
        window.clearTimeout(stateSaveTimerRef.current);
        stateSaveTimerRef.current = null;
      }

      if (immediate) {
        void flushStateSave();
        return;
      }

      stateSaveTimerRef.current = window.setTimeout(() => void flushStateSave(), SAVE_DEBOUNCE_MS);
    },
    [flushStateSave]
  );

  const scheduleScaleUpdate = useCallback(() => {
    if (resizeRafRef.current) return;
    resizeRafRef.current = window.requestAnimationFrame(() => {
      resizeRafRef.current = null;
      const host = hostRef.current;
      if (!host) return;
      const frame = host.querySelector(`.${styles.frame}`) as HTMLDivElement | null;
      if (!frame) return;
      const width = frame.getBoundingClientRect().width;
      if (!width || width <= 0) return;
      const scale = width / 1024;
      if (Math.abs(scale - lastAppliedScaleRef.current) < 0.001) return;
      lastAppliedScaleRef.current = scale;
      host.style.setProperty("--scale", scale.toString());
    });
  }, []);

  const startLiveStateSync = useCallback(() => {
    if (liveStateSyncTimerRef.current) return;
    scheduleNextLiveStateSync(getLiveStateSyncDelayMs());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const stopLiveStateSync = useCallback(() => {
    if (!liveStateSyncTimerRef.current) return;
    window.clearTimeout(liveStateSyncTimerRef.current);
    liveStateSyncTimerRef.current = null;
  }, []);

  const restartLiveStateSync = useCallback(() => {
    stopLiveStateSync();
    startLiveStateSync();
  }, [startLiveStateSync, stopLiveStateSync]);

  const getLiveStateSyncDelayMs = useCallback(() => {
    return timeLeftSecondsRef.current >= 0 && timeLeftSecondsRef.current <= 10
      ? LIVE_STATE_SYNC_FINAL_TEN_MS
      : LIVE_STATE_SYNC_MS;
  }, []);

  const syncStateFromServer = useCallback(async () => {
    if (!supabase || !userId) return;
    if (!stateInitializedRef.current) return;
    if (liveStateSyncInFlightRef.current || stateSaveInFlightRef.current || stateDirtyRef.current) return;

    liveStateSyncInFlightRef.current = true;
    try {
      const { data, error } = await supabase
        .from("fun_target_state")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw error;
      if (!data) return;
      applyLoadedState(data as FunTargetStateRow);
    } catch {
      // ignore
    } finally {
      liveStateSyncInFlightRef.current = false;
    }
  }, [supabase, userId]);

  const scheduleNextLiveStateSync = useCallback(
    (delayMs: number) => {
      liveStateSyncTimerRef.current = window.setTimeout(() => {
        liveStateSyncTimerRef.current = null;
        void syncStateFromServer();
        scheduleNextLiveStateSync(getLiveStateSyncDelayMs());
      }, delayMs);
    },
    [getLiveStateSyncDelayMs, syncStateFromServer]
  );

  const applyLoadedState = useCallback(
    (row: FunTargetStateRow) => {
      setCoins(Number(row.score ?? 0));
      setLastResults(Array.isArray(row.last10_results) && row.last10_results.length ? row.last10_results : [...DEFAULT_LAST_RESULTS]);
      const winAmount = Number(row.winner_amount ?? 0);
      setWinnerValue(winAmount);
      setPendingPayout(winAmount);
      const bets = normalizeBetsJson(row.bets_json);
      setBetsByNumber(bets);
      const numbers = Object.keys(bets).map(Number);
      setSelectedNumbers(numbers);
      setSelectedNumber(numbers.length ? numbers[numbers.length - 1] ?? null : null);
      predefinedWheelNumberRef.current = normalizeWheelNumber(row.predefined_wheel_number);
      lastRoundAtIsoRef.current = safeIso(row.last_round_at);
      if (lastRoundAtIsoRef.current) {
        fallbackRoundAnchorMsRef.current = null;
      } else {
        if (fallbackRoundAnchorMsRef.current === null) fallbackRoundAnchorMsRef.current = Date.now() - ANCHOR_SHIFT_TO_59_MS;
      }
      lastTimerSecondRef.current = null;
      updateTimerFromAnchor();
      refreshRoundPhase();
      // eslint-disable-next-line react-hooks/exhaustive-deps
    },
    [refreshRoundPhase, updateTimerFromAnchor]
  );

  const initState = useCallback(async () => {
    if (!supabase) return;
    const { data: userRes } = await supabase.auth.getUser();
    const uid = userRes.user?.id ?? null;
    if (!uid) {
      setUserId(null);
      setEmail(null);
      return;
    }
    setUserId(uid);
    setEmail(userRes.user?.email ?? null);

    await supabase.from("fun_target_state").upsert({ user_id: uid }, { onConflict: "user_id" });
    const { data } = await supabase.from("fun_target_state").select("*").eq("user_id", uid).maybeSingle();
    if (data) applyLoadedState(data as FunTargetStateRow);
    stateInitializedRef.current = true;
    lastSavedStateHashRef.current = JSON.stringify(buildStatePayload());
  }, [applyLoadedState, buildStatePayload, supabase]);

  const targetAngleForNumber = useCallback((value: number) => {
    return 360 - (value * SEGMENT_ANGLE + POINTER_ALIGNMENT_OFFSET);
  }, []);

  const startSpinAnimation = useCallback((targetRotation: number) => {
    if (spinRafRef.current) {
      window.cancelAnimationFrame(spinRafRef.current);
      spinRafRef.current = null;
    }
    spinRafRef.current = window.requestAnimationFrame(() => {
      setRotation(targetRotation);
      spinRafRef.current = null;
    });
  }, []);

  const resolveRoundBets = useCallback(
    (result: number) => {
      const winningStake = betsByNumber[result] || 0;
      const winValue = winningStake > 0 ? winningStake * 9 : 0;
      setWinnerValue(winValue);
      setPendingPayout(winValue);
      setBetsByNumber({});
      setSelectedNumber(null);
      setSelectedNumbers([]);
    },
    [betsByNumber]
  );

  const startAutoSpinRound = useCallback(() => {
    if (autoSpinActiveRef.current || roundStartInProgressRef.current) return;
    roundStartInProgressRef.current = true;
    try {
      setHighlightedBetNumber(null);
      setBetOkHighlighted(false);
      setIsBetConfirmed(true);
      setFooterMessage(SPIN_FOOTER_MESSAGE);
      queueStateSave(true);

      const predefined = predefinedWheelNumberRef.current;
      const result = predefined !== null ? predefined : Math.floor(Math.random() * SEGMENTS);
      const targetAngle = targetAngleForNumber(result);
      const normalized = ((rotation % 360) + 360) % 360;
      const delta = (targetAngle - normalized + 360) % 360;

      roundPredefinedNumberRef.current = predefined;
      autoSpinResultRef.current = result;
      autoSpinActiveRef.current = true;
      setIsSpinning(true);
      setSpinDuration(AUTO_SPIN_DURATION);
      setSpinEasing("cubic-bezier(0.1, 0.95, 0.15, 1)");
      playSound("wheelStart");
      startSpinAnimation(rotation + 12 * 360 + delta);
    } finally {
      roundStartInProgressRef.current = false;
    }
  }, [playSound, queueStateSave, rotation, startSpinAnimation, targetAngleForNumber, setBetOkHighlighted]);

  const finalizeAutoSpinRound = useCallback(() => {
    const result = autoSpinResultRef.current;
    if (!autoSpinActiveRef.current || result === null) return;

    setCurrentNumber(result);
    setHighlightedBetNumber(result);
    setLastResults((prev) => [result, ...prev].slice(0, 10));
    resolveRoundBets(result);
    setIsSpinning(false);
    stopSound("wheelStart");
    playSound("wheelEnd");
    const stake = betsByNumber[result] || 0;
    const winValue = stake > 0 ? stake * 9 : 0;
    playSound(winValue > 0 ? "win" : "lose");
    autoSpinActiveRef.current = false;
    autoSpinResultRef.current = null;
    roundPredefinedNumberRef.current = null;
    predefinedWheelNumberRef.current = null;
    setIsBetConfirmed(false);
    setFooterMessage(POST_SPIN_FOOTER_MESSAGE);
    setSpinDuration("2.8s");
    setSpinEasing("cubic-bezier(0.22, 0.9, 0.26, 1.05)");
    lastRoundAtIsoRef.current = new Date().toISOString();
    fallbackRoundAnchorMsRef.current = null;
    refreshRoundPhase();
    queueStateSave(true);
  }, [betsByNumber, playSound, queueStateSave, refreshRoundPhase, resolveRoundBets, stopSound]);

  const selectNumberClick = useCallback(
    (value: number) => {
      if (!selectedChip || isBetNumberDisabled) return;
      if (coins < selectedChip) return;

      const updated: Record<number, number> = { ...betsByNumber };
      updated[value] = (updated[value] || 0) + selectedChip;
      setBetsByNumber(updated);
      setShowPrevBet(false);
      setFooterMessage(DEFAULT_FOOTER_MESSAGE);
      playSound("bet");

      setCoins((c) => c - selectedChip);
      const nums = Object.keys(updated).map(Number);
      setSelectedNumbers(nums);
      setSelectedNumber(value);
      queueStateSave();
    },
    [betsByNumber, coins, isBetNumberDisabled, playSound, queueStateSave, selectedChip]
  );

  const selectChipClick = useCallback(
    (value: number) => {
      setSelectedChip(value);
      playSound("button");
    },
    [playSound]
  );

  const placeBet = useCallback(() => {
    if (isBetOkDisabled) return;
    if (!selectedNumbers.length || totalBetAmount <= 0) return;
    playSound("bet");
    setIsBetConfirmed(true);
    setShowPrevBet(false);
    setFooterMessage("Your bet has been Accepted");
    setBetOkHighlighted(false);
    prevBetRef.current = {
      betsByNumber: { ...betsByNumber },
      numbers: [...selectedNumbers],
      number: selectedNumber,
      chip: selectedChip,
    };
    queueStateSave();
  }, [
    betsByNumber,
    isBetOkDisabled,
    playSound,
    queueStateSave,
    selectedChip,
    selectedNumber,
    selectedNumbers,
    setBetOkHighlighted,
    totalBetAmount,
  ]);

  const cancelBet = useCallback(() => {
    playSound("button");
    setSelectedNumber(null);
    setSelectedNumbers([]);
    setHighlightedBetNumber(null);
    const refund = Object.values(betsByNumber).reduce((sum, amount) => sum + amount, 0);
    setCoins((c) => c + refund);
    setBetsByNumber({});
    setIsBetConfirmed(false);
    setFooterMessage(DEFAULT_FOOTER_MESSAGE);
    refreshRoundPhase();
    queueStateSave();
  }, [betsByNumber, playSound, queueStateSave, refreshRoundPhase]);

  const cancelSpecificBet = useCallback(() => {
    if (selectedNumber === null) return;
    playSound("button");

    const target = selectedNumber;
    const updated: Record<number, number> = { ...betsByNumber };
    const refund = updated[target] || 0;
    delete updated[target];
    setCoins((c) => c + refund);
    setBetsByNumber(updated);
    const nums = Object.keys(updated).map(Number);
    setSelectedNumbers(nums);
    setSelectedNumber(null);
    setIsBetConfirmed(false);
    setFooterMessage(DEFAULT_FOOTER_MESSAGE);
    refreshRoundPhase();
    queueStateSave();
  }, [betsByNumber, playSound, queueStateSave, refreshRoundPhase, selectedNumber]);

  const takePayout = useCallback(() => {
    if (!pendingPayout) return;
    playSound("take");
    setCoins((c) => c + pendingPayout);
    setPendingPayout(0);
    setWinnerValue(0);
    setHighlightedBetNumber(null);
    setIsBetConfirmed(false);
    setShowPrevBet(true);
    setFooterMessage(DEFAULT_FOOTER_MESSAGE);
    setBetOkHighlighted(true);
    refreshRoundPhase();
    queueStateSave(true);
  }, [pendingPayout, playSound, queueStateSave, refreshRoundPhase, setBetOkHighlighted]);

  const prevBet = useCallback(() => {
    if (isSpinning || isFinalTenSeconds || isBetConfirmed) return;
    playSound("button");
    setShowPrevBet(false);
    const prev = prevBetRef.current;
    if (!prev) return;
    const previousBets = { ...(prev.betsByNumber || {}) };
    const previousTotal = Object.values(previousBets).reduce((sum, amount) => sum + amount, 0);
    if (coins < previousTotal) return;

    setBetsByNumber(previousBets);
    setCoins((c) => c - previousTotal);
    const nums = Object.keys(previousBets).map(Number);
    setSelectedNumbers(nums);
    setSelectedNumber(nums.length ? nums[nums.length - 1] ?? prev.number ?? null : prev.number ?? null);
    setSelectedChip(prev.chip ?? selectedChip);
    setIsBetConfirmed(false);
    setFooterMessage(DEFAULT_FOOTER_MESSAGE);
    refreshRoundPhase();
    queueStateSave();
  }, [coins, isBetConfirmed, isFinalTenSeconds, isSpinning, playSound, queueStateSave, refreshRoundPhase, selectedChip]);

  const resetGame = useCallback(() => {
    playSound("exit");
    setSelectedNumber(null);
    setSelectedNumbers([]);
    setBetsByNumber({});
    setPendingPayout(0);
    setWinnerValue(0);
    setHighlightedBetNumber(null);
    setBetOkHighlighted(false);
    setIsBetConfirmed(false);
    setShowPrevBet(false);
    setFooterMessage(DEFAULT_FOOTER_MESSAGE);
    setSelectedChip(1);
    setCurrentNumber(0);
    setRotation(0);
    setIsSpinning(false);
    setSpinDuration("2.8s");
    setSpinEasing("cubic-bezier(0.22, 0.9, 0.26, 1.05)");
    setCoins(0);
    setLastResults([...DEFAULT_LAST_RESULTS]);
    timeLeftSecondsRef.current = 59;
    lastTimerSecondRef.current = null;
    autoSpinActiveRef.current = false;
    autoSpinResultRef.current = null;
    fallbackRoundAnchorMsRef.current = Date.now() - ANCHOR_SHIFT_TO_59_MS;
    prevBetRef.current = null;
    if (spinTimerRef.current) window.clearTimeout(spinTimerRef.current);
    spinTimerRef.current = null;
    if (spinRafRef.current) window.cancelAnimationFrame(spinRafRef.current);
    spinRafRef.current = null;
    setLogoResetToken((t) => t + 1);
    lastRoundAtIsoRef.current = null;
    updateTimerFromAnchor();
    refreshRoundPhase();
    queueStateSave(true);
  }, [playSound, queueStateSave, refreshRoundPhase, setBetOkHighlighted, updateTimerFromAnchor]);

  useEffect(() => {
    initializeSounds();
    registerAudioUnlockListeners();
    unlockAudio(true);
    playLoadingSoundOnce();
    restoreBetOkHighlight();
    startCountdown();
    void initState();
    startLiveStateSync();
    void syncStateFromServer();

    const onResize = () => scheduleScaleUpdate();
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);
    const onFocus = () => void syncStateFromServer();
    window.addEventListener("focus", onFocus);
    const onVisibility = () => {
      if (document.visibilityState !== "hidden") {
        startLiveStateSync();
        void syncStateFromServer();
        return;
      }
      stopLiveStateSync();
    };
    document.addEventListener("visibilitychange", onVisibility);

    const { data: sub } = supabase?.auth.onAuthStateChange((_evt, s) => {
      setUserId(s?.user?.id ?? null);
      setEmail(s?.user?.email ?? null);
    }) ?? { data: null as any };

    return () => {
      disposeSounds();
      unregisterAudioUnlockListeners();
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onVisibility);
      if (resizeRafRef.current) window.cancelAnimationFrame(resizeRafRef.current);
      resizeRafRef.current = null;
      stopCountdown();
      if (spinTimerRef.current) window.clearTimeout(spinTimerRef.current);
      if (spinRafRef.current) window.cancelAnimationFrame(spinRafRef.current);
      if (stateSaveTimerRef.current) window.clearTimeout(stateSaveTimerRef.current);
      stopLiveStateSync();
      try {
        sub?.subscription?.unsubscribe();
      } catch {
        // ignore
      }
      if (stateInitializedRef.current && stateDirtyRef.current && !stateSaveInFlightRef.current) {
        void flushStateSave();
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    scheduleScaleUpdate();
    renderTimerTextToDom();
  }, [renderTimerTextToDom, scheduleScaleUpdate]);

  if (!supabase) {
    return (
      <div className="container">
        <div className="card">Missing Supabase env vars.</div>
      </div>
    );
  }

  if (!userId) {
    return (
      <div className="container">
        <div className="card">
          Not signed in. <Link href="/">Go to login</Link>
        </div>
      </div>
    );
  }

  return (
    <div ref={hostRef} className={styles.host}>
      <div className={styles.frame}>
        <section className={styles.stage} style={stageStyle}>
          <div className={styles.overlay}>
            <div className={timerGlowClassName}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className={styles["timer-glow-on"]} src={targetTimeGlowUrl} alt="" />
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className={styles["timer-glow-off"]} src={targetTimeOffUrl} alt="" />
            </div>
            <div className={`${styles["score-value"]} ${styles["value-box"]}`}>{coins}</div>
            <div ref={timeValueRef} className={`${styles["time-value"]} ${styles["value-box"]}`}>
              0:59
            </div>
            <div className={`${styles["winner-value"]} ${styles["value-box"]}`}>{winnerValue}</div>
            <div className={`${styles["last-value"]} ${styles["value-box"]}`}>{lastResultsText}</div>
          </div>

          <div className={styles["wheel-layer"]}>
            <div className={arrowStackClassName}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className={styles["arrow-glow-img"]} src={arrowGlowUrl} alt="" />
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className={styles["arrow-img"]} src={arrowUrl} alt="Arrow" />
            </div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles.wheel} src={wheelUrl} alt="Wheel" style={wheelStyle} />
            <div className={styles["wheel-center"]}>
              <div className={styles["center-ball-host"]}>
                <LogoAnimator spinning={isSpinning} resetToken={logoResetToken} />
              </div>
            </div>
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className={styles["title-front"]} src={titleUrl} alt="Fun Target Title" />

          <div className={styles["coin-layer"]}>
            {coinButtons.map((item) => (
              <button
                key={item.value}
                type="button"
                className={item.className}
                style={item.style}
                data-chip={item.value}
                aria-pressed={item.isSelected}
                aria-label={item.ariaLabel}
                title={item.ariaLabel}
                onClick={() => selectChipClick(item.value)}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={item.image} alt={String(item.value)} />
              </button>
            ))}
          </div>

          <div className={styles["bet-number-layer"]}>
            {betNumberButtons.map((item) => (
              <button
                key={item.value}
                type="button"
                className={item.className}
                style={item.style}
                data-number={item.value}
                aria-label={item.ariaLabel}
                title={item.ariaLabel}
                disabled={item.isDisabled}
                onClick={() => selectNumberClick(item.value)}
              >
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img className={styles["bet-glow-img"]} src={item.glowUrl} alt="" />
              </button>
            ))}
          </div>

          <div className={styles["bet-amount-layer"]}>
            {betAmountVisuals.map((amount) => (
              <div key={amount.key} className={styles["bet-amount"]} style={amount.style}>
                {amount.value}
              </div>
            ))}
          </div>

          <div className={styles["total-bet-amount"]}>{totalBetAmount}</div>

          <button className={takeButtonClassName} onClick={takePayout}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={takeGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={takeOffUrl} alt="" />
            <span className={styles["btn-label"]}>Take</span>
          </button>

          <button className={`${styles["action-btn"]} ${styles.cancel}`} onClick={cancelBet}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={cancelGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={cancelOffUrl} alt="" />
            <span className={styles["btn-label"]}>Cancel Bet</span>
          </button>

          <button className={`${styles["action-btn"]} ${styles["cancel-specific"]}`} onClick={cancelSpecificBet}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={cancelGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={cancelOffUrl} alt="" />
            <span className={styles["btn-label"]}>Cancel Specific Bet</span>
          </button>

          <button className={betOkButtonClassName} onClick={placeBet} disabled={isBetOkDisabled}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={betOkGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={betOkOffUrl} alt="" />
            <span className={styles["btn-label"]}>Bet Ok</span>
          </button>

          <button className={prevButtonClassName} onClick={prevBet}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={prevGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={prevOffUrl} alt="" />
            <span className={styles["btn-label"]}>Prev Bet</span>
          </button>

          <button className={`${styles["action-btn"]} ${styles.exit}`} onClick={resetGame}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-on-img"]} src={exitGlowUrl} alt="" />
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className={styles["btn-glow-off-img"]} src={exitOffUrl} alt="" />
            <span className={styles["btn-label"]}>Exit</span>
          </button>

          <div className={styles["footer-note"]}>{footerMessage}</div>
        </section>
      </div>
    </div>
  );
}
