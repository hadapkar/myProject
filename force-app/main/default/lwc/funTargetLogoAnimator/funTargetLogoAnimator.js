import { LightningElement, api, track } from 'lwc';
import funTargrtAsset from '@salesforce/resourceUrl/funTargrtAsset';

const BAD_BASE = `${funTargrtAsset}/media/BAD/golo`;
const FRAME_INTERVAL_MS = 90;
const FRAME_URLS = Array.from({ length: 20 }, (_, idx) => `${BAD_BASE}/Logo${idx}.jpg`);

export default class FunTargetLogoAnimator extends LightningElement {
    @track frameUrl = FRAME_URLS[0];

    _frameIndex = 0;
    _frameTimer;
    _spinning = false;
    _resetToken;

    @api
    get spinning() {
        return this._spinning;
    }

    set spinning(value) {
        const nextValue = Boolean(value);
        if (nextValue === this._spinning) {
            return;
        }

        this._spinning = nextValue;
        if (this._spinning) {
            this._resetToFirstFrame();
            this._startAnimation();
            return;
        }

        this._stopAnimation();
    }

    @api
    get resetToken() {
        return this._resetToken;
    }

    set resetToken(value) {
        if (value === this._resetToken) {
            return;
        }
        this._resetToken = value;
        this._resetToFirstFrame();
    }

    connectedCallback() {
        if (this._spinning) {
            this._startAnimation();
        }
    }

    disconnectedCallback() {
        this._stopAnimation();
    }

    _startAnimation() {
        if (this._frameTimer) {
            return;
        }

        this._frameTimer = window.setInterval(() => {
            this._frameIndex = (this._frameIndex + 1) % FRAME_URLS.length;
            this.frameUrl = FRAME_URLS[this._frameIndex];
        }, FRAME_INTERVAL_MS);
    }

    _stopAnimation() {
        if (!this._frameTimer) {
            return;
        }

        window.clearInterval(this._frameTimer);
        this._frameTimer = null;
    }

    _resetToFirstFrame() {
        this._frameIndex = 0;
        this.frameUrl = FRAME_URLS[0];
    }
}
