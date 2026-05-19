import { createElement } from "lwc";
import FunTargetGame from "c/funTargetGame";
import getOrCreateState from "@salesforce/apex/FunTargetStateController.getOrCreateState";
import getCurrentState from "@salesforce/apex/FunTargetStateController.getCurrentState";
import saveSpinResult from "@salesforce/apex/FunTargetStateController.saveSpinResult";
import applySiteIntentFlat from "@salesforce/apex/FunTargetStateController.applySiteIntentFlat";
import saveState from "@salesforce/apex/FunTargetStateController.saveState";

jest.mock(
  "@salesforce/apex/FunTargetStateController.getOrCreateState",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FunTargetStateController.getCurrentState",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FunTargetStateController.saveSpinResult",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FunTargetStateController.applySiteIntentFlat",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FunTargetStateController.saveState",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

const BASE_STATE = {
  score: 1000,
  predefinedWheelNumber: null,
  last10Results: "8,8,9,0,2,9,6,4,3,7",
  totalBetAmount: 0,
  winnerAmount: 0,
  betsJson: "{}",
  lastUpdatedFrom: "Site",
  lastRoundAt: "2026-04-07T09:59:04.000Z",
  lastModifiedDate: "2026-04-07T10:00:00.000Z",
  serverNow: "2026-04-07T10:00:00.000Z"
};

const flushPromises = () => Promise.resolve();

describe("c-fun-target-game", () => {
  beforeAll(() => {
    Object.defineProperty(global.HTMLMediaElement.prototype, "play", {
      configurable: true,
      writable: true,
      value: jest.fn().mockResolvedValue(undefined)
    });
    Object.defineProperty(global.HTMLMediaElement.prototype, "pause", {
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
    applySiteIntentFlat.mockResolvedValue({ ...BASE_STATE });
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

  it("enables Bet Ok after number click and sends PLACE_BET intent", async () => {
    const element = createElement("c-fun-target-game", {
      is: FunTargetGame
    });
    document.body.appendChild(element);
    await flushPromises();

    const betButtons = element.shadowRoot.querySelectorAll(".bet-number-btn");
    expect(betButtons.length).toBeGreaterThan(0);
    betButtons[0].click();
    await flushPromises();

    const betOkButton = element.shadowRoot.querySelector(".action-btn.betok");
    expect(betOkButton).not.toBeNull();
    expect(betOkButton.disabled).toBe(false);

    betOkButton.click();
    await flushPromises();

    expect(applySiteIntentFlat).toHaveBeenCalledWith(
      expect.objectContaining({
        intent: "PLACE_BET"
      })
    );
  });
});
