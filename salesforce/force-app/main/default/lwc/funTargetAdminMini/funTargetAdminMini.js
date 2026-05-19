import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMyStateForAdmin from "@salesforce/apex/FunTargetStateController.getMyStateForAdmin";
import updateMyScore from "@salesforce/apex/FunTargetStateController.updateMyScore";
import updatePredefinedWheelNumber from "@salesforce/apex/FunTargetStateController.updatePredefinedWheelNumber";
import clearMyPredefinedWheelNumber from "@salesforce/apex/FunTargetStateController.clearMyPredefinedWheelNumber";

const WHEEL_NUMBERS_ROW_1 = [1, 2, 3, 4, 5];
const WHEEL_NUMBERS_ROW_2 = [6, 7, 8, 9, 0];
const DATE_TIME_FORMATTER = new Intl.DateTimeFormat(undefined, {
  year: "numeric",
  month: "short",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit"
});
const SESSION_RETRY_MAX_ATTEMPTS = 3;
const SESSION_RETRY_DELAY_MS = 700;
const INITIAL_LOAD_DELAY_MS = 250;

export default class FunTargetAdminMini extends LightningElement {
  @track amount = 0;
  @track score = 0;
  @track selectedWheelNumber = null;
  @track lastUpdatedFrom = "-";
  @track lastUpdatedAt = null;
  @track isSaving = false;
  @track isWheelNumberSaving = false;
  isLoading = false;
  loadQueued = false;
  stateFingerprint = "";
  bootstrapTimer = null;
  activeSections = [];

  connectedCallback() {
    this.bootstrapTimer = window.setTimeout(() => {
      this.loadState();
    }, INITIAL_LOAD_DELAY_MS);
  }

  disconnectedCallback() {
    if (this.bootstrapTimer) {
      window.clearTimeout(this.bootstrapTimer);
      this.bootstrapTimer = null;
    }
  }

  get scoreDisplay() {
    return Number(this.score || 0).toFixed(2);
  }

  get isRefreshDisabled() {
    return this.isLoading || this.isSaving || this.isWheelNumberSaving;
  }

  get isSetDisabled() {
    return (
      this.isSaving ||
      this.isWheelNumberSaving ||
      this.isLoading ||
      !Number.isFinite(this.amount) ||
      this.amount <= 0
    );
  }

  get isResetDisabled() {
    return this.isSaving || this.isWheelNumberSaving || this.isLoading;
  }

  get isClearWheelDisabled() {
    return (
      this.isWheelNumberSaving ||
      this.isSaving ||
      this.isLoading ||
      this.selectedWheelNumber === null
    );
  }

  get wheelNumbersRow1() {
    return WHEEL_NUMBERS_ROW_1.map((value) => this.buildWheelNumber(value));
  }

  get wheelNumbersRow2() {
    return WHEEL_NUMBERS_ROW_2.map((value) => this.buildWheelNumber(value));
  }

  get lastUpdatedAtDisplay() {
    if (!this.lastUpdatedAt) {
      return "-";
    }
    try {
      return DATE_TIME_FORMATTER.format(new Date(this.lastUpdatedAt));
    } catch (error) {
      return this.lastUpdatedAt;
    }
  }

  handleAmountChange(event) {
    const value = Number(event.detail.value);
    this.amount = Number.isFinite(value) && value >= 0 ? value : 0;
  }

  handleSet() {
    this.applySetOperation();
  }

  handleResetScore() {
    this.applyResetOperation();
  }

  handleManualRefresh() {
    if (this.isRefreshDisabled) {
      return;
    }
    this.loadState({ silent: false, force: true });
    this.refreshLivePanel(true);
  }

  handleAccordionToggle(event) {
    this.activeSections = event.detail.openSections || [];
  }

  handleWheelNumberSelect(event) {
    const value = Number(event.currentTarget.dataset.number);
    if (!Number.isInteger(value) || value < 0 || value > 9) {
      return;
    }

    if (
      this.isWheelNumberSaving ||
      this.isSaving ||
      this.isLoading ||
      value === this.selectedWheelNumber
    ) {
      return;
    }

    const previousValue = this.selectedWheelNumber;
    this.selectedWheelNumber = value;
    this.isWheelNumberSaving = true;

    this._callApexWithSessionRetry(updatePredefinedWheelNumber, {
      wheelNumber: value
    })
      .then((state) => {
        if (state) {
          this.applyState(state);
          this.stateFingerprint = this.buildStateFingerprint(state);
          this.refreshLivePanel(true);
        }
      })
      .catch((error) => {
        this.selectedWheelNumber = previousValue;
        this.showError(error);
      })
      .finally(() => {
        this.isWheelNumberSaving = false;
      });
  }

  handleClearWheelNumber() {
    if (this.isClearWheelDisabled) {
      return;
    }

    const previousValue = this.selectedWheelNumber;
    this.selectedWheelNumber = null;
    this.isWheelNumberSaving = true;

    this._callApexWithSessionRetry(clearMyPredefinedWheelNumber)
      .then((state) => {
        if (state) {
          this.applyState(state);
          this.stateFingerprint = this.buildStateFingerprint(state);
          this.refreshLivePanel(true);
        }
      })
      .catch((error) => {
        this.selectedWheelNumber = previousValue;
        this.showError(error);
      })
      .finally(() => {
        this.isWheelNumberSaving = false;
      });
  }

  loadState(options = {}) {
    const { silent = false, force = false } = options;
    if (this.isLoading) {
      this.loadQueued = true;
      return;
    }

    this.isLoading = true;
    this._callApexWithSessionRetry(getMyStateForAdmin)
      .then((state) => {
        const nextFingerprint = this.buildStateFingerprint(state);
        if (force || nextFingerprint !== this.stateFingerprint) {
          this.applyState(state);
          this.stateFingerprint = nextFingerprint;
        }
      })
      .catch((error) => {
        if (this._isInvalidSessionError(error)) {
          // Mobile cold start can briefly return INVALID_SESSION_ID while token refresh completes.
          // Suppress noisy toast and allow retry on next refresh/interaction.
          return;
        }
        if (!silent) {
          this.showError(error);
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

  applySetOperation() {
    if (this.isSaving) {
      return;
    }
    if (!Number.isFinite(this.amount) || this.amount <= 0) {
      return;
    }

    this.isSaving = true;
    this._callApexWithSessionRetry(updateMyScore, {
      amount: this.amount,
      operation: "ADD"
    })
      .then((state) => {
        this.applyState(state);
        this.stateFingerprint = this.buildStateFingerprint(state);
        this.refreshLivePanel(true);
        this.amount = 0;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Saved",
            message: "Amount added to current score",
            variant: "success"
          })
        );
      })
      .catch((error) => {
        this.showError(error);
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  applyResetOperation() {
    if (this.isSaving) {
      return;
    }

    this.isSaving = true;
    this._callApexWithSessionRetry(updateMyScore, {
      amount: 0,
      operation: "SET"
    })
      .then((state) => {
        this.applyState(state);
        this.stateFingerprint = this.buildStateFingerprint(state);
        this.refreshLivePanel(true);
        this.amount = 0;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Saved",
            message: "Score reset to zero",
            variant: "success"
          })
        );
      })
      .catch((error) => {
        this.showError(error);
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  applyState(state) {
    this.score = Number(state?.score || 0);
    this.selectedWheelNumber = state?.predefinedWheelNumber ?? null;
    this.lastUpdatedFrom = state?.lastUpdatedFrom || "-";
    this.lastUpdatedAt = state?.lastModifiedDate || null;
  }

  buildWheelNumber(value) {
    return {
      value,
      className: `wheel-number-btn${value === this.selectedWheelNumber ? " selected" : ""}`
    };
  }

  buildStateFingerprint(state) {
    const score = Number(state?.score || 0);
    const wheel = state?.predefinedWheelNumber ?? "";
    const source = state?.lastUpdatedFrom || "";
    const modified = state?.lastModifiedDate || "";
    return `${score}|${wheel}|${source}|${modified}`;
  }

  showError(error) {
    let message = "Unexpected error";
    if (error?.body?.message) {
      message = error.body.message;
    } else if (error?.message) {
      message = error.message;
    }
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Error",
        message,
        variant: "error"
      })
    );
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

  refreshLivePanel(force = false) {
    const livePanel = this.template.querySelector("c-fun-target-admin-live");
    if (!livePanel || typeof livePanel.refreshData !== "function") {
      return;
    }
    livePanel.refreshData(force);
  }
}
