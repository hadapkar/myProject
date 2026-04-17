import { createElement } from 'lwc';
import FunTargetGame from 'c/funTargetGame';
import getOrCreateState from '@salesforce/apex/FunTargetStateController.getOrCreateState';
import getCurrentState from '@salesforce/apex/FunTargetStateController.getCurrentState';
import saveSpinResult from '@salesforce/apex/FunTargetStateController.saveSpinResult';
import applySiteIntent from '@salesforce/apex/FunTargetStateController.applySiteIntent';
import saveState from '@salesforce/apex/FunTargetStateController.saveState';

jest.mock(
    '@salesforce/apex/FunTargetStateController.getOrCreateState',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FunTargetStateController.getCurrentState',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FunTargetStateController.saveSpinResult',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FunTargetStateController.applySiteIntent',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FunTargetStateController.saveState',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

const BASE_STATE = {
    score: 1000,
    predefinedWheelNumber: null,
    last10Results: '8,8,9,0,2,9,6,4,3,7',
    totalBetAmount: 0,
    winnerAmount: 0,
    betsJson: '{}',
    lastUpdatedFrom: 'Site',
    lastRoundAt: null,
    lastModifiedDate: '2026-04-07T10:00:00.000Z'
};

const flushPromises = () => Promise.resolve();

describe('c-fun-target-game', () => {
    beforeAll(() => {
        Object.defineProperty(global.HTMLMediaElement.prototype, 'play', {
            configurable: true,
            writable: true,
            value: jest.fn().mockResolvedValue(undefined)
        });
        Object.defineProperty(global.HTMLMediaElement.prototype, 'pause', {
            configurable: true,
            writable: true,
            value: jest.fn()
        });
    });

    beforeEach(() => {
        jest.useFakeTimers();
        getOrCreateState.mockResolvedValue({ ...BASE_STATE });
        getCurrentState.mockResolvedValue({ ...BASE_STATE });
        saveSpinResult.mockResolvedValue({ ...BASE_STATE });
        applySiteIntent.mockResolvedValue({ ...BASE_STATE });
        saveState.mockResolvedValue({ ...BASE_STATE });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.runOnlyPendingTimers();
        jest.useRealTimers();
    });

    it('enables Bet Ok after number click and sends PLACE_BET intent', async () => {
        const element = createElement('c-fun-target-game', {
            is: FunTargetGame
        });
        document.body.appendChild(element);
        await flushPromises();

        const betButtons = element.shadowRoot.querySelectorAll('.bet-number-btn');
        expect(betButtons.length).toBeGreaterThan(0);
        betButtons[0].click();
        await flushPromises();

        const betOkButton = element.shadowRoot.querySelector('.action-btn.betok');
        expect(betOkButton).not.toBeNull();
        expect(betOkButton.disabled).toBe(false);

        betOkButton.click();
        await flushPromises();

        expect(applySiteIntent).toHaveBeenCalledWith(
            expect.objectContaining({
                request: expect.objectContaining({
                    intent: 'PLACE_BET'
                })
            })
        );
    });

    it('disables bet number buttons during spinning phase', async () => {
        const element = createElement('c-fun-target-game', {
            is: FunTargetGame
        });
        document.body.appendChild(element);
        await flushPromises();

        jest.advanceTimersByTime(59000);
        await flushPromises();

        const firstBetButton = element.shadowRoot.querySelector('.bet-number-btn');
        expect(firstBetButton.disabled).toBe(true);
    });

    it('adds blink class to Take button when payout is available', async () => {
        saveSpinResult.mockResolvedValue({
            ...BASE_STATE,
            winnerAmount: 90,
            betsJson: '{}',
            totalBetAmount: 0,
            last10Results: '1,8,8,9,0,2,9,6,4,3',
            lastModifiedDate: '2026-04-07T10:01:00.000Z'
        });

        const element = createElement('c-fun-target-game', {
            is: FunTargetGame
        });
        document.body.appendChild(element);
        await flushPromises();

        const betButtons = element.shadowRoot.querySelectorAll('.bet-number-btn');
        betButtons[0].click();
        await flushPromises();

        jest.advanceTimersByTime(64000);
        await flushPromises();
        await flushPromises();

        const takeButton = element.shadowRoot.querySelector('.action-btn.take');
        expect(takeButton.className).toContain('blink');
    });

    it('blinks timer only in final ten-second window', async () => {
        const element = createElement('c-fun-target-game', {
            is: FunTargetGame
        });
        document.body.appendChild(element);
        await flushPromises();

        const initialClass = element.shadowRoot.querySelector('.timer-glow-stack').className;
        expect(initialClass).not.toContain('blinking');

        jest.advanceTimersByTime(49000);
        await flushPromises();
        const finalTenClass = element.shadowRoot.querySelector('.timer-glow-stack').className;
        expect(finalTenClass).toContain('blinking');
    });
});
