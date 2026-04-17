@IsTest
private class FunTargetStateControllerTest {
    private static final String TEST_LAST10 = '8,8,9,0,2,9,6,4,3,7';

    @IsTest
    static void testPlaceBetIntentAdjustsScoreAndTotals() {
        FunTargetStateController.StateDTO state = FunTargetStateController.getCurrentState();
        System.assertEquals(1000, state.score);

        FunTargetStateController.SiteIntentRequest request = new FunTargetStateController.SiteIntentRequest();
        request.intent = 'PLACE_BET';
        request.betsJson = '{"1":10,"2":20}';

        FunTargetStateController.StateDTO placed = FunTargetStateController.applySiteIntent(
            request,
            state.lastModifiedDate
        );
        System.assertEquals(970, placed.score);
        System.assertEquals(30, placed.totalBetAmount);
        Map<String, Object> placedBets = (Map<String, Object>) JSON.deserializeUntyped(placed.betsJson);
        System.assertEquals(2, placedBets.size());
        System.assertEquals(10, Decimal.valueOf(String.valueOf(placedBets.get('1'))));
        System.assertEquals(20, Decimal.valueOf(String.valueOf(placedBets.get('2'))));

        request.betsJson = '{"1":10}';
        FunTargetStateController.StateDTO reduced = FunTargetStateController.applySiteIntent(
            request,
            placed.lastModifiedDate
        );
        System.assertEquals(990, reduced.score);
        System.assertEquals(10, reduced.totalBetAmount);
        Map<String, Object> reducedBets = (Map<String, Object>) JSON.deserializeUntyped(reduced.betsJson);
        System.assertEquals(1, reducedBets.size());
        System.assertEquals(10, Decimal.valueOf(String.valueOf(reducedBets.get('1'))));

        request.betsJson = '{}';
        FunTargetStateController.StateDTO cleared = FunTargetStateController.applySiteIntent(
            request,
            reduced.lastModifiedDate
        );
        System.assertEquals(1000, cleared.score);
        System.assertEquals(0, cleared.totalBetAmount);
        System.assertEquals('{}', cleared.betsJson);
    }

    @IsTest
    static void testSaveSpinResultSetsWinnerAndClearsBets() {
        FunTargetStateController.StateDTO state = FunTargetStateController.getCurrentState();

        FunTargetStateController.SiteIntentRequest placeRequest = new FunTargetStateController.SiteIntentRequest();
        placeRequest.intent = 'PLACE_BET';
        placeRequest.betsJson = '{"3":50}';
        FunTargetStateController.StateDTO placed = FunTargetStateController.applySiteIntent(
            placeRequest,
            state.lastModifiedDate
        );
        System.assertEquals(950, placed.score);
        System.assertEquals(50, placed.totalBetAmount);

        FunTargetStateController.StateDTO spin = FunTargetStateController.saveSpinResult(
            3,
            false,
            placed.lastModifiedDate
        );
        System.assertEquals(450, spin.winnerAmount);
        System.assertEquals(0, spin.totalBetAmount);
        System.assertEquals('{}', spin.betsJson);
        System.assert(spin.last10Results.startsWith('3,'));
    }

    @IsTest
    static void testTakeAndForfeitPayoutIntents() {
        FunTargetStateController.StateDTO state = FunTargetStateController.getCurrentState();
        Id userId = UserInfo.getUserId();

        FunTargetState__c row = [
            SELECT Id, Score__c, WinnerAmount__c, UserIdKey__c
            FROM FunTargetState__c
            WHERE UserIdKey__c = :String.valueOf(userId)
            LIMIT 1
        ];
        row.Score__c = 100;
        row.WinnerAmount__c = 90;
        update row;

        FunTargetState__c refreshed = [
            SELECT LastModifiedDate
            FROM FunTargetState__c
            WHERE Id = :row.Id
            LIMIT 1
        ];

        FunTargetStateController.SiteIntentRequest take = new FunTargetStateController.SiteIntentRequest();
        take.intent = 'TAKE_PAYOUT';
        FunTargetStateController.StateDTO taken = FunTargetStateController.applySiteIntent(
            take,
            refreshed.LastModifiedDate
        );
        System.assertEquals(190, taken.score);
        System.assertEquals(0, taken.winnerAmount);

        FunTargetState__c forfeitSeed = [
            SELECT Id, WinnerAmount__c, LastModifiedDate
            FROM FunTargetState__c
            WHERE UserIdKey__c = :String.valueOf(userId)
            LIMIT 1
        ];
        forfeitSeed.WinnerAmount__c = 50;
        update forfeitSeed;

        FunTargetState__c forfeitFresh = [
            SELECT LastModifiedDate
            FROM FunTargetState__c
            WHERE Id = :forfeitSeed.Id
            LIMIT 1
        ];

        FunTargetStateController.SiteIntentRequest forfeit = new FunTargetStateController.SiteIntentRequest();
        forfeit.intent = 'FORFEIT_PAYOUT';
        FunTargetStateController.StateDTO forfeited = FunTargetStateController.applySiteIntent(
            forfeit,
            forfeitFresh.LastModifiedDate
        );
        System.assertEquals(190, forfeited.score);
        System.assertEquals(0, forfeited.winnerAmount);
    }

    @IsTest
    static void testSaveStateDerivesSiteScoreMath() {
        FunTargetStateController.StateDTO initial = FunTargetStateController.getCurrentState();

        FunTargetStateController.StateDTO payload = new FunTargetStateController.StateDTO();
        payload.score = 1000;
        payload.last10Results = TEST_LAST10;
        payload.totalBetAmount = 50;
        payload.winnerAmount = 0;
        payload.betsJson = '{"1":25,"2":25}';
        payload.lastUpdatedFrom = 'Site';
        payload.lastRoundAt = System.now();

        FunTargetStateController.StateDTO afterAdd = FunTargetStateController.saveState(
            payload,
            initial.lastModifiedDate
        );
        System.assertEquals(950, afterAdd.score);
        System.assertEquals(50, afterAdd.totalBetAmount);

        payload.score = afterAdd.score;
        payload.totalBetAmount = 0;
        payload.betsJson = '{}';
        payload.winnerAmount = 0;
        payload.lastRoundAt = null;

        FunTargetStateController.StateDTO afterRefund = FunTargetStateController.saveState(
            payload,
            afterAdd.lastModifiedDate
        );
        System.assertEquals(1000, afterRefund.score);
        System.assertEquals(0, afterRefund.totalBetAmount);
    }

    @IsTest
    static void testOptimisticLockConflictForIntent() {
        FunTargetStateController.StateDTO state = FunTargetStateController.getCurrentState();
        Id userId = UserInfo.getUserId();

        FunTargetState__c row = [
            SELECT Id, LastUpdatedFrom__c
            FROM FunTargetState__c
            WHERE UserIdKey__c = :String.valueOf(userId)
            LIMIT 1
        ];
        row.LastUpdatedFrom__c = 'Admin';
        update row;

        FunTargetStateController.SiteIntentRequest request = new FunTargetStateController.SiteIntentRequest();
        request.intent = 'CONFIRM_BET';

        try {
            FunTargetStateController.applySiteIntent(request, state.lastModifiedDate.addSeconds(-1));
            System.assert(false, 'Expected optimistic lock conflict.');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex);
        }
    }

    @IsTest
    static void testPredefinedWheelLifecycle() {
        FunTargetStateController.StateDTO initial = FunTargetStateController.getCurrentState();
        System.assertEquals(null, initial.predefinedWheelNumber);

        FunTargetStateController.StateDTO updated = FunTargetStateController.updatePredefinedWheelNumber(7);
        System.assertEquals(7, updated.predefinedWheelNumber);
        System.assertEquals(7, FunTargetStateController.getMyPredefinedWheelNumber());

        FunTargetStateController.StateDTO cleared = FunTargetStateController.clearMyPredefinedWheelNumber();
        System.assertEquals(null, cleared.predefinedWheelNumber);
        System.assertEquals(null, FunTargetStateController.getMyPredefinedWheelNumber());
    }

    @IsTest
    static void testUpdateMyScoreOperations() {
        FunTargetStateController.getCurrentState();

        FunTargetStateController.StateDTO add = FunTargetStateController.updateMyScore(100, 'ADD');
        System.assertEquals(1100, add.score);

        FunTargetStateController.StateDTO subtract = FunTargetStateController.updateMyScore(40, 'SUBTRACT');
        System.assertEquals(1060, subtract.score);

        FunTargetStateController.StateDTO setValue = FunTargetStateController.updateMyScore(5, 'SET');
        System.assertEquals(5, setValue.score);
    }

    @IsTest
    static void testInvalidIntentThrows() {
        FunTargetStateController.getCurrentState();
        FunTargetStateController.SiteIntentRequest request = new FunTargetStateController.SiteIntentRequest();
        request.intent = 'UNKNOWN';
        try {
            FunTargetStateController.applySiteIntent(request, null);
            System.assert(false, 'Expected invalid intent error');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex);
        }
    }
}
