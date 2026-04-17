import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyStateForAdmin from '@salesforce/apex/FunTargetStateController.getMyStateForAdmin';
import updateMyScore from '@salesforce/apex/FunTargetStateController.updateMyScore';
import updatePredefinedWheelNumber from '@salesforce/apex/FunTargetStateController.updatePredefinedWheelNumber';
import clearMyPredefinedWheelNumber from '@salesforce/apex/FunTargetStateController.clearMyPredefinedWheelNumber';

const WHEEL_NUMBERS_ROW_1 = [1, 2, 3, 4, 5];
const WHEEL_NUMBERS_ROW_2 = [6, 7, 8, 9, 0];
const DATE_TIME_FORMATTER = new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
});
const SESSION_RETRY_MAX_ATTEMPTS = 3;
const SESSION_RETRY_DELAY_MS = 700;
const INITIAL_LOAD_DELAY_MS = 250;
const LIVE_SYNC_INTERVAL_MS = 1000;

export default class FunTargetAdminMini extends LightningElement {
    @track amount = 0;
    @track score = 0;
    @track selectedWheelNumber = null;
    @track betsByNumber = {};
    @track totalBetAmount = 0;
    @track syncedTimerText = '--';
    @track lastThreeResults = [];
    @track lastUpdatedFrom = '-';
    @track lastUpdatedAt = null;
    @track isSaving = false;
    @track isWheelNumberSaving = false;
    isLoading = false;
    loadQueued = false;
    stateFingerprint = '';
    bootstrapTimer = null;
    liveSyncTimer = null;
    spinAnchorMs = null;
    lastSpinResult = null;

    connectedCallback() {
        this.bootstrapTimer = window.setTimeout(() => {
            this.loadState();
        }, INITIAL_LOAD_DELAY_MS);
        this.startLiveSync();
    }

    disconnectedCallback() {
        if (this.bootstrapTimer) {
            window.clearTimeout(this.bootstrapTimer);
            this.bootstrapTimer = null;
        }
        this.stopLiveSync();
    }

    get scoreDisplay() {
        return Number(this.score || 0).toFixed(2);
    }

    get isRefreshDisabled() {
        return this.isLoading || this.isSaving || this.isWheelNumberSaving;
    }

    get isSetDisabled() {
        return this.isSaving || this.isWheelNumberSaving || this.isLoading || !Number.isFinite(this.amount) || this.amount <= 0;
    }

    get isResetDisabled() {
        return this.isSaving || this.isWheelNumberSaving || this.isLoading;
    }

    get isClearWheelDisabled() {
        return this.isWheelNumberSaving || this.isSaving || this.isLoading || this.selectedWheelNumber === null;
    }

    get wheelNumbersRow1() {
        return WHEEL_NUMBERS_ROW_1.map((value) => this.buildWheelNumber(value));
    }

    get wheelNumbersRow2() {
        return WHEEL_NUMBERS_ROW_2.map((value) => this.buildWheelNumber(value));
    }

    get liveBetRow1() {
        return WHEEL_NUMBERS_ROW_1.map((value) => this.buildLiveBetCell(value));
    }

    get liveBetRow2() {
        return WHEEL_NUMBERS_ROW_2.map((value) => this.buildLiveBetCell(value));
    }

    get lastThreeResultsDisplay() {
        if (!this.lastThreeResults.length) {
            return '-';
        }
        return this.lastThreeResults.join(' ');
    }

    get totalBetAmountDisplay() {
        return Number(this.totalBetAmount || 0).toFixed(2);
    }

    get lastUpdatedAtDisplay() {
        if (!this.lastUpdatedAt) {
            return '-';
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
    }

    handleWheelNumberSelect(event) {
        const value = Number(event.currentTarget.dataset.number);
        if (!Number.isInteger(value) || value < 0 || value > 9) {
            return;
        }

        if (this.isWheelNumberSaving || this.isSaving || this.isLoading || value === this.selectedWheelNumber) {
            return;
        }

        const previousValue = this.selectedWheelNumber;
        this.selectedWheelNumber = value;
        this.isWheelNumberSaving = true;

        this._callApexWithSessionRetry(updatePredefinedWheelNumber, { wheelNumber: value })
            .then((state) => {
                if (state) {
                    this.applyState(state);
                    this.stateFingerprint = this.buildStateFingerprint(state);
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
        this._callApexWithSessionRetry(updateMyScore, { amount: this.amount, operation: 'ADD' })
            .then((state) => {
                this.applyState(state);
                this.stateFingerprint = this.buildStateFingerprint(state);
                this.amount = 0;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Saved',
                        message: 'Amount added to current score',
                        variant: 'success'
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
        this._callApexWithSessionRetry(updateMyScore, { amount: 0, operation: 'SET' })
            .then((state) => {
                this.applyState(state);
                this.stateFingerprint = this.buildStateFingerprint(state);
                this.amount = 0;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Saved',
                        message: 'Score reset to zero',
                        variant: 'success'
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
        this.betsByNumber = this.parseBetsJson(state?.betsJson);
        this.totalBetAmount = Number(state?.totalBetAmount || 0);
        const parsedLast10 = this.parseLast10Results(state?.last10Results);
        this.lastThreeResults = parsedLast10.slice(0, 3);
        this.syncTimerAnchor(parsedLast10, state?.lastModifiedDate);
        this.updateSyncedTimer();
        this.lastUpdatedFrom = state?.lastUpdatedFrom || '-';
        this.lastUpdatedAt = state?.lastModifiedDate || null;
    }

    buildWheelNumber(value) {
        return {
            value,
            className: `wheel-number-btn${value === this.selectedWheelNumber ? ' selected' : ''}`
        };
    }

    buildLiveBetCell(value) {
        const amount = Number(this.betsByNumber[value] || 0);
        return {
            value,
            amountText: this.formatBetAmount(amount),
            className: `live-bet-cell${amount > 0 ? ' active' : ''}`
        };
    }

    buildStateFingerprint(state) {
        const score = Number(state?.score || 0);
        const wheel = state?.predefinedWheelNumber ?? '';
        const betsJson = state?.betsJson || '';
        const totalBetAmount = Number(state?.totalBetAmount || 0);
        const last10 = state?.last10Results || '';
        const source = state?.lastUpdatedFrom || '';
        const modified = state?.lastModifiedDate || '';
        return `${score}|${wheel}|${betsJson}|${totalBetAmount}|${last10}|${source}|${modified}`;
    }

    showError(error) {
        let message = 'Unexpected error';
        if (error?.body?.message) {
            message = error.body.message;
        } else if (error?.message) {
            message = error.message;
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }

    _callApexWithSessionRetry(apexMethod, params, maxAttempts = SESSION_RETRY_MAX_ATTEMPTS) {
        const invoke = (attempt) => {
            const request = params === undefined ? apexMethod() : apexMethod(params);
            return request.catch((error) => {
                if (attempt + 1 < maxAttempts && this._isInvalidSessionError(error)) {
                    return this._delay(SESSION_RETRY_DELAY_MS * (attempt + 1)).then(() => invoke(attempt + 1));
                }
                throw error;
            });
        };

        return invoke(0);
    }

    _isInvalidSessionError(error) {
        const message = String(error?.body?.message || error?.message || '').toLowerCase();
        return (
            message.includes('invalid_session_id') ||
            message.includes('invalid session') ||
            message.includes('session expired') ||
            message.includes('sessionheader')
        );
    }

    _delay(ms) {
        return new Promise((resolve) => {
            window.setTimeout(resolve, ms);
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

    syncTimerAnchor(last10Values, lastModifiedDate) {
        const latestResult = last10Values.length ? last10Values[0] : null;
        if (latestResult !== null && latestResult !== this.lastSpinResult) {
            this.lastSpinResult = latestResult;
            this.spinAnchorMs = Date.now();
            return;
        }

        if (this.spinAnchorMs === null && lastModifiedDate) {
            const parsedMs = new Date(lastModifiedDate).getTime();
            if (Number.isFinite(parsedMs)) {
                this.spinAnchorMs = parsedMs;
            }
        }
    }

    updateSyncedTimer() {
        if (this.spinAnchorMs === null) {
            this.syncedTimerText = '--';
            return;
        }

        const elapsedSeconds = Math.max(0, Math.floor((Date.now() - this.spinAnchorMs) / 1000));
        let value;
        if (elapsedSeconds <= 55) {
            value = 55 - elapsedSeconds;
        } else {
            value = 59 - ((elapsedSeconds - 56) % 60);
        }
        this.syncedTimerText = `0:${String(value).padStart(2, '0')}`;
    }

    parseBetsJson(rawJson) {
        if (!rawJson) {
            return {};
        }
        try {
            const parsed = JSON.parse(rawJson);
            if (!parsed || typeof parsed !== 'object') {
                return {};
            }

            return Object.keys(parsed).reduce((acc, key) => {
                const betNumber = Number(key);
                const amount = Number(parsed[key]);
                if (Number.isInteger(betNumber) && betNumber >= 0 && betNumber <= 9 && Number.isFinite(amount) && amount > 0) {
                    acc[betNumber] = amount;
                }
                return acc;
            }, {});
        } catch (error) {
            return {};
        }
    }

    parseLast10Results(rawValue) {
        if (!rawValue || typeof rawValue !== 'string') {
            return [];
        }
        return rawValue
            .split(',')
            .map((value) => Number(value.trim()))
            .filter((value) => Number.isInteger(value) && value >= 0 && value <= 9);
    }

    formatBetAmount(amount) {
        if (!Number.isFinite(amount) || amount <= 0) {
            return '0';
        }
        return Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
    }
}
