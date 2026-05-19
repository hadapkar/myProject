import { LightningElement, api, track } from "lwc";
import getMyStateForAdmin from "@salesforce/apex/FunTargetStateController.getMyStateForAdmin";

const WHEEL_NUMBERS_ROW_1 = [1, 2, 3, 4, 5];
const WHEEL_NUMBERS_ROW_2 = [6, 7, 8, 9, 0];
const LIVE_SYNC_INTERVAL_MS = 1000;
const ROUND_SECONDS = 60;
const SPIN_RESULT_SECOND = 55;
const ANCHOR_SHIFT_TO_59_MS = 56000;
const SESSION_RETRY_MAX_ATTEMPTS = 3;
const SESSION_RETRY_DELAY_MS = 700;

export default class FunTargetAdminLive extends LightningElement {
  @track betsByNumber = {};
  @track totalBetAmount = 0;
  @track syncedTimerText = "--";
  @track lastTenResults = [];

  isLoading = false;
  loadQueued = false;
  stateFingerprint = "";
  spinAnchorMs = null;
  fallbackAnchorMs = null;
  serverClockOffsetMs = 0;
  liveSyncTimer = null;

  connectedCallback() {
    this.loadState({ silent: true, force: true });
    this.startLiveSync();
  }

  disconnectedCallback() {
    this.stopLiveSync();
  }

  @api
  refreshData(force = false) {
    this.loadState({ silent: true, force: force === true });
  }

  get liveBetRow1() {
    return WHEEL_NUMBERS_ROW_1.map((value) => this.buildLiveBetCell(value));
  }

  get liveBetRow2() {
    return WHEEL_NUMBERS_ROW_2.map((value) => this.buildLiveBetCell(value));
  }

  get lastTenResultsDisplay() {
    if (!this.lastTenResults.length) {
      return "-";
    }
    return this.lastTenResults.join(" ");
  }

  get totalBetAmountDisplay() {
    return Number(this.totalBetAmount || 0).toFixed(2);
  }

  loadState(options = {}) {
    const { silent = true, force = false } = options;
    if (this.isLoading) {
      this.loadQueued = true;
      return;
    }

    this.isLoading = true;
    this._callApexWithSessionRetry(getMyStateForAdmin)
      .then((state) => {
        this.syncRealtimeClock(state);
        this.updateSyncedTimer();
        const nextFingerprint = this.buildStateFingerprint(state);
        if (force || nextFingerprint !== this.stateFingerprint) {
          this.applyState(state);
          this.stateFingerprint = nextFingerprint;
        }
      })
      .catch((error) => {
        if (this._isInvalidSessionError(error)) {
          return;
        }
        if (!silent) {
          // Keep child quiet by default; parent handles toasts.
          // no-op
        }
      })
      .finally(() => {
        this.isLoading = false;
        if (this.loadQueued) {
          this.loadQueued = false;
          this.loadState({ silent: true });
        }
      });
  }

  startLiveSync() {
    if (this.liveSyncTimer) {
      return;
    }
    this.liveSyncTimer = window.setInterval(() => {
      this.updateSyncedTimer();
      this.loadState({ silent: true });
    }, LIVE_SYNC_INTERVAL_MS);
  }

  stopLiveSync() {
    if (!this.liveSyncTimer) {
      return;
    }
    window.clearInterval(this.liveSyncTimer);
    this.liveSyncTimer = null;
  }

  applyState(state) {
    this.betsByNumber = this.parseBetsJson(state?.betsJson);
    this.totalBetAmount = Number(state?.totalBetAmount || 0);
    const parsedLast10 = this.parseLast10Results(state?.last10Results);
    this.lastTenResults = parsedLast10.slice(0, 10).reverse();
  }

  buildStateFingerprint(state) {
    const betsJson = state?.betsJson || "";
    const totalBetAmount = Number(state?.totalBetAmount || 0);
    const last10 = state?.last10Results || "";
    const roundAt = state?.lastRoundAt || "";
    const modified = state?.lastModifiedDate || "";
    return `${betsJson}|${totalBetAmount}|${last10}|${roundAt}|${modified}`;
  }

  syncRealtimeClock(state) {
    this.syncServerClock(state?.serverNow);
    this.syncTimerAnchor(state?.lastRoundAt, state?.lastModifiedDate);
  }

  syncServerClock(serverNowValue) {
    if (!serverNowValue) {
      return;
    }
    const parsedServerNowMs = new Date(serverNowValue).getTime();
    if (!Number.isFinite(parsedServerNowMs)) {
      return;
    }
    this.serverClockOffsetMs = parsedServerNowMs - Date.now();
  }

  getServerNowMs() {
    return Date.now() + this.serverClockOffsetMs;
  }

  syncTimerAnchor(lastRoundAt, lastModifiedDate) {
    if (lastRoundAt) {
      const parsedRoundMs = new Date(lastRoundAt).getTime();
      if (Number.isFinite(parsedRoundMs)) {
        this.spinAnchorMs = parsedRoundMs;
        this.fallbackAnchorMs = null;
        return;
      }
    }

    if (this.spinAnchorMs !== null) {
      return;
    }

    if (lastModifiedDate) {
      const parsedModifiedMs = new Date(lastModifiedDate).getTime();
      if (Number.isFinite(parsedModifiedMs)) {
        this.fallbackAnchorMs = parsedModifiedMs - ANCHOR_SHIFT_TO_59_MS;
        this.spinAnchorMs = this.fallbackAnchorMs;
        return;
      }
    }

    if (this.fallbackAnchorMs === null) {
      this.fallbackAnchorMs = this.getServerNowMs() - ANCHOR_SHIFT_TO_59_MS;
    }
    this.spinAnchorMs = this.fallbackAnchorMs;
  }

  updateSyncedTimer() {
    if (this.spinAnchorMs === null) {
      this.syncedTimerText = "--";
      return;
    }

    const elapsedSeconds = Math.max(
      0,
      Math.floor((this.getServerNowMs() - this.spinAnchorMs) / 1000)
    );
    const value =
      (SPIN_RESULT_SECOND - (elapsedSeconds % ROUND_SECONDS) + ROUND_SECONDS) %
      ROUND_SECONDS;
    this.syncedTimerText = `0:${String(value).padStart(2, "0")}`;
  }

  buildLiveBetCell(value) {
    const amount = Number(this.betsByNumber[value] || 0);
    return {
      value,
      amountText: this.formatBetAmount(amount),
      className: `live-bet-cell${amount > 0 ? " active" : ""}`
    };
  }

  parseBetsJson(rawJson) {
    if (!rawJson) {
      return {};
    }
    try {
      const parsed = JSON.parse(rawJson);
      if (!parsed || typeof parsed !== "object") {
        return {};
      }

      return Object.keys(parsed).reduce((acc, key) => {
        const betNumber = Number(key);
        const amount = Number(parsed[key]);
        if (
          Number.isInteger(betNumber) &&
          betNumber >= 0 &&
          betNumber <= 9 &&
          Number.isFinite(amount) &&
          amount > 0
        ) {
          acc[betNumber] = amount;
        }
        return acc;
      }, {});
    } catch (error) {
      return {};
    }
  }

  parseLast10Results(rawValue) {
    if (!rawValue || typeof rawValue !== "string") {
      return [];
    }
    return rawValue
      .split(",")
      .map((value) => Number(value.trim()))
      .filter((value) => Number.isInteger(value) && value >= 0 && value <= 9);
  }

  formatBetAmount(amount) {
    if (!Number.isFinite(amount) || amount <= 0) {
      return "0";
    }
    return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
  }

  _callApexWithSessionRetry(
    apexMethod,
    params,
    maxAttempts = SESSION_RETRY_MAX_ATTEMPTS
  ) {
    const invoke = (attempt) => {
      const request = params === undefined ? apexMethod() : apexMethod(params);
      return request.catch((error) => {
        if (attempt + 1 < maxAttempts && this._isInvalidSessionError(error)) {
          return this._delay(SESSION_RETRY_DELAY_MS * (attempt + 1)).then(() =>
            invoke(attempt + 1)
          );
        }
        throw error;
      });
    };

    return invoke(0);
  }

  _isInvalidSessionError(error) {
    const message = String(
      error?.body?.message || error?.message || ""
    ).toLowerCase();
    return (
      message.includes("invalid_session_id") ||
      message.includes("invalid session") ||
      message.includes("session expired") ||
      message.includes("sessionheader")
    );
  }

  _delay(ms) {
    return new Promise((resolve) => {
      window.setTimeout(resolve, ms);
    });
  }
}
