public with sharing class FunTargetStateController {
    private static final String FALLBACK_LAST10 = '8,8,9,0,2,9,6,4,3,7';

    public class StateDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Integer predefinedWheelNumber;
        @AuraEnabled public String last10Results;
        @AuraEnabled public Decimal totalBetAmount;
        @AuraEnabled public Decimal winnerAmount;
        @AuraEnabled public String betsJson;
        @AuraEnabled public String lastUpdatedFrom;
        @AuraEnabled public Datetime lastRoundAt;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class SiteIntentRequest {
        @AuraEnabled public String intent;
        @AuraEnabled public String betsJson;
    }

    @AuraEnabled(cacheable=true)
    public static StateDTO getOrCreateState() {
        FunTargetState__c existingRecord = getStateRecord(false, false);
        return existingRecord == null ? buildDefaultDto() : toDto(existingRecord);
    }

    @AuraEnabled
    public static StateDTO getCurrentState() {
        FunTargetState__c stateRecord = getStateRecord(false, true);
        return toDto(stateRecord);
    }

    @AuraEnabled
    public static Integer getMyPredefinedWheelNumber() {
        FunTargetState__c stateRecord = getStateRecord(false, false);
        if (stateRecord == null || stateRecord.PredefinedWheelNumber__c == null) {
            return null;
        }
        return stateRecord.PredefinedWheelNumber__c.intValue();
    }

    @AuraEnabled
    public static StateDTO clearMyPredefinedWheelNumber() {
        FunTargetState__c stateRecord = getStateRecord(true, false);
        if (stateRecord == null) {
            return buildDefaultDto();
        }
        if (stateRecord.PredefinedWheelNumber__c == null) {
            return toDto(stateRecord);
        }

        stateRecord.PredefinedWheelNumber__c = null;
        stateRecord.LastUpdatedFrom__c = 'Site';
        stateRecord.LastRoundAt__c = System.now();
        update stateRecord;
        return toDto(getStateRecordById(stateRecord.Id));
    }

    @AuraEnabled
    public static StateDTO saveSpinResult(
        Integer spinResult,
        Boolean clearPredefinedWheelNumber,
        Datetime expectedLastModified
    ) {
        if (spinResult == null || spinResult < 0 || spinResult > 9) {
            throw new AuraHandledException('Spin result must be between 0 and 9.');
        }

        FunTargetState__c stateRecord = getStateRecord(true, true);
        assertOptimisticLock(expectedLastModified, stateRecord.LastModifiedDate);
        Map<Integer, Decimal> existingBets = parseBetsJson(stateRecord.BetsJson__c);
        Decimal winningStake = existingBets.containsKey(spinResult) ? existingBets.get(spinResult) : 0;
        List<Integer> previousValues = parseLast10(stateRecord.Last10Results__c);
        List<Integer> values = new List<Integer>{ spinResult };
        values.addAll(previousValues);
        while (values.size() > 10) {
            values.remove(values.size() - 1);
        }

        List<String> serialized = new List<String>();
        for (Integer item : values) {
            serialized.add(String.valueOf(item));
        }

        stateRecord.Last10Results__c = String.join(serialized, ',');
        stateRecord.BetsJson__c = '{}';
        stateRecord.TotalBetAmount__c = 0;
        stateRecord.WinnerAmount__c = winningStake > 0 ? winningStake * 9 : 0;
        if (clearPredefinedWheelNumber == true) {
            stateRecord.PredefinedWheelNumber__c = null;
        }
        stateRecord.LastUpdatedFrom__c = 'Site';
        stateRecord.LastRoundAt__c = System.now();
        update stateRecord;

        return toDto(getStateRecordById(stateRecord.Id));
    }

    @AuraEnabled
    public static StateDTO applySiteIntent(SiteIntentRequest request, Datetime expectedLastModified) {
        String intent = request == null || String.isBlank(request.intent)
            ? null
            : request.intent.trim().toUpperCase();
        if (String.isBlank(intent)) {
            throw new AuraHandledException('Intent is required.');
        }

        FunTargetState__c stateRecord = getStateRecord(true, true);
        assertOptimisticLock(expectedLastModified, stateRecord.LastModifiedDate);
        Decimal currentScore = stateRecord.Score__c == null ? 0 : stateRecord.Score__c;
        Boolean changed = false;

        if (intent == 'PLACE_BET') {
            Map<Integer, Decimal> oldBets = parseBetsJson(stateRecord.BetsJson__c);
            Decimal oldTotal = sumBetAmounts(oldBets);
            Map<Integer, Decimal> newBets = parseBetsJson(request != null ? request.betsJson : null);
            Decimal newTotal = sumBetAmounts(newBets);
            Decimal delta = newTotal - oldTotal;

            if (delta > 0 && currentScore < delta) {
                throw new AuraHandledException('Insufficient score balance for bet placement.');
            }

            if (delta != 0) {
                stateRecord.Score__c = Math.max(0, currentScore - delta);
                changed = true;
            }
            if (stateRecord.TotalBetAmount__c != newTotal) {
                stateRecord.TotalBetAmount__c = newTotal;
                changed = true;
            }

            String serializedBets = serializeBetsJson(newBets);
            if (stateRecord.BetsJson__c != serializedBets) {
                stateRecord.BetsJson__c = serializedBets;
                changed = true;
            }
        } else if (intent == 'TAKE_PAYOUT') {
            Decimal payout = stateRecord.WinnerAmount__c == null ? 0 : stateRecord.WinnerAmount__c;
            if (payout > 0) {
                stateRecord.Score__c = currentScore + payout;
                changed = true;
            }
            if (stateRecord.WinnerAmount__c != 0) {
                stateRecord.WinnerAmount__c = 0;
                changed = true;
            }
        } else if (intent == 'FORFEIT_PAYOUT') {
            if (stateRecord.WinnerAmount__c != 0) {
                stateRecord.WinnerAmount__c = 0;
                changed = true;
            }
        } else if (intent == 'RESET_GAME') {
            stateRecord.Score__c = 0;
            stateRecord.Last10Results__c = getDefaultLast10();
            stateRecord.TotalBetAmount__c = 0;
            stateRecord.WinnerAmount__c = 0;
            stateRecord.BetsJson__c = '{}';
            stateRecord.LastRoundAt__c = null;
            changed = true;
        } else if (intent == 'CONFIRM_BET') {
            // Client uses this to validate lock and keep consistent flow.
            // No field update is required here.
        } else {
            throw new AuraHandledException('Unsupported site intent: ' + intent);
        }

        if (changed) {
            stateRecord.LastUpdatedFrom__c = 'Site';
            stateRecord.LastRoundAt__c = stateRecord.LastRoundAt__c == null && intent == 'RESET_GAME'
                ? null
                : System.now();
            update stateRecord;
            return toDto(getStateRecordById(stateRecord.Id));
        }

        return toDto(stateRecord);
    }

    @AuraEnabled
    public static StateDTO getMyStateForAdmin() {
        FunTargetState__c existingRecord = getStateRecord(false, false);
        return existingRecord == null ? buildDefaultDto() : toDto(existingRecord);
    }

    @AuraEnabled
    public static StateDTO saveState(StateDTO payload, Datetime expectedLastModified) {
        FunTargetState__c stateRecord = getStateRecord(true, true);
        assertOptimisticLock(expectedLastModified, stateRecord.LastModifiedDate);

        Id userId = UserInfo.getUserId();
        FunTargetState__c existingRecord = stateRecord;
        Decimal existingScore = existingRecord != null && existingRecord.Score__c != null ? existingRecord.Score__c : 1000;
        String existingLast10 = existingRecord != null && String.isNotBlank(existingRecord.Last10Results__c)
            ? existingRecord.Last10Results__c
            : getDefaultLast10();
        Decimal existingTotalBetAmount = existingRecord != null && existingRecord.TotalBetAmount__c != null
            ? existingRecord.TotalBetAmount__c
            : 0;
        Decimal existingWinnerAmount = existingRecord != null && existingRecord.WinnerAmount__c != null
            ? existingRecord.WinnerAmount__c
            : 0;
        String existingBetsJson = existingRecord != null && String.isNotBlank(existingRecord.BetsJson__c)
            ? existingRecord.BetsJson__c
            : '{}';
        Datetime existingLastRoundAt = existingRecord != null ? existingRecord.LastRoundAt__c : null;

        Map<Integer, Decimal> sanitizedBets = payload != null
            ? parseBetsJson(payload.betsJson)
            : parseBetsJson(existingBetsJson);
        Decimal computedTotalBetAmount = 0;
        for (Decimal item : sanitizedBets.values()) {
            computedTotalBetAmount += item;
        }

        Decimal incomingWinnerAmount = payload != null && payload.winnerAmount != null
            ? Math.max(0, payload.winnerAmount)
            : existingWinnerAmount;
        Decimal maxWinnerAmount = computedTotalBetAmount * 9;
        Decimal safeWinnerAmount = Math.min(incomingWinnerAmount, maxWinnerAmount);

        String safeLast10 = payload != null
            ? sanitizeLast10(payload.last10Results, existingLast10)
            : existingLast10;
        String safeSource = sanitizeUpdateSource(payload != null ? payload.lastUpdatedFrom : null);
        Datetime incomingLastRoundAt = payload != null ? payload.lastRoundAt : existingLastRoundAt;
        Decimal incomingRequestedScore = payload != null ? payload.score : existingScore;
        Decimal safeScore = safeSource == 'Admin'
            ? Math.max(0, incomingRequestedScore == null ? existingScore : incomingRequestedScore)
            : deriveSiteScore(
                existingScore,
                existingTotalBetAmount,
                existingWinnerAmount,
                computedTotalBetAmount,
                safeWinnerAmount,
                incomingLastRoundAt,
                existingLastRoundAt,
                incomingRequestedScore
            );

        stateRecord.UserIdKey__c = String.valueOf(userId);
        stateRecord.User__c = userId;
        stateRecord.Score__c = payload != null ? safeScore : existingScore;
        stateRecord.Last10Results__c = safeLast10;
        stateRecord.TotalBetAmount__c = payload != null ? computedTotalBetAmount : existingTotalBetAmount;
        stateRecord.WinnerAmount__c = payload != null ? safeWinnerAmount : existingWinnerAmount;
        stateRecord.BetsJson__c = payload != null ? serializeBetsJson(sanitizedBets) : existingBetsJson;
        stateRecord.LastUpdatedFrom__c = safeSource;
        stateRecord.LastRoundAt__c = payload != null && payload.lastRoundAt != null
            ? payload.lastRoundAt
            : existingLastRoundAt;

        update stateRecord;
        return toDto(getStateRecordById(stateRecord.Id));
    }

    @AuraEnabled
    public static StateDTO updateMyScore(Decimal amount, String operation) {
        if (amount == null || amount < 0) {
            throw new AuraHandledException('Amount must be zero or greater.');
        }

        String op = String.isBlank(operation) ? 'SET' : operation.trim().toUpperCase();
        if (op != 'ADD' && op != 'SUBTRACT' && op != 'SET') {
            throw new AuraHandledException('Operation must be ADD, SUBTRACT, or SET.');
        }

        FunTargetState__c stateRecord = getStateRecord(true, true);
        Decimal currentScore = stateRecord.Score__c == null ? 0 : stateRecord.Score__c;

        if (op == 'ADD') {
            stateRecord.Score__c = currentScore + amount;
        } else if (op == 'SUBTRACT') {
            stateRecord.Score__c = Math.max(0, currentScore - amount);
        } else {
            stateRecord.Score__c = amount;
        }

        stateRecord.LastUpdatedFrom__c = 'Admin';
        stateRecord.LastRoundAt__c = System.now();
        update stateRecord;

        return toDto(getStateRecordById(stateRecord.Id));
    }

    @AuraEnabled
    public static StateDTO updatePredefinedWheelNumber(Integer wheelNumber) {
        if (wheelNumber == null || wheelNumber < 0 || wheelNumber > 9) {
            throw new AuraHandledException('Wheel number must be between 0 and 9.');
        }

        Id userId = UserInfo.getUserId();
        FunTargetState__c stateRecord = new FunTargetState__c();
        stateRecord.UserIdKey__c = String.valueOf(userId);
        stateRecord.User__c = userId;
        stateRecord.PredefinedWheelNumber__c = wheelNumber;
        stateRecord.LastUpdatedFrom__c = 'Admin';
        stateRecord.LastRoundAt__c = System.now();

        Database.UpsertResult result = Database.upsert(
            stateRecord,
            FunTargetState__c.Fields.UserIdKey__c,
            false
        );
        if (!result.isSuccess()) {
            Database.Error err = result.getErrors()[0];
            throw new AuraHandledException(err.getStatusCode() + ': ' + err.getMessage());
        }

        Id stateId = result.getId();
        if (stateId == null) {
            FunTargetState__c fallbackRecord = getStateRecord(false, false);
            return fallbackRecord == null ? buildDefaultDto() : toDto(fallbackRecord);
        }
        return toDto(getStateRecordById(stateId));
    }

    private static FunTargetState__c getStateRecord(Boolean lockForUpdate, Boolean createIfMissing) {
        Id userId = UserInfo.getUserId();
        String userKey = String.valueOf(userId);

        List<FunTargetState__c> rows;
        if (lockForUpdate) {
            rows = [
                SELECT Id, Score__c, Last10Results__c, TotalBetAmount__c, WinnerAmount__c,
                       PredefinedWheelNumber__c, BetsJson__c, LastUpdatedFrom__c,
                       LastRoundAt__c, LastModifiedDate
                FROM FunTargetState__c
                WHERE UserIdKey__c = :userKey
                LIMIT 1
                FOR UPDATE
            ];
        } else {
            rows = [
                SELECT Id, Score__c, Last10Results__c, TotalBetAmount__c, WinnerAmount__c,
                       PredefinedWheelNumber__c, BetsJson__c, LastUpdatedFrom__c,
                       LastRoundAt__c, LastModifiedDate
                FROM FunTargetState__c
                WHERE UserIdKey__c = :userKey
                LIMIT 1
            ];
        }

        if (!rows.isEmpty()) {
            return rows[0];
        }

        if (!createIfMissing) {
            return null;
        }

        FunTargetState__c newRow = new FunTargetState__c(
            User__c = userId,
            UserIdKey__c = userKey,
            Score__c = 1000,
            Last10Results__c = getDefaultLast10(),
            TotalBetAmount__c = 0,
            WinnerAmount__c = 0,
            BetsJson__c = '{}',
            LastUpdatedFrom__c = 'Site'
        );

        try {
            insert newRow;
        } catch (DmlException ex) {
            // If another request created it concurrently, read existing row.
        }

        if (lockForUpdate) {
            return [
                SELECT Id, Score__c, Last10Results__c, TotalBetAmount__c, WinnerAmount__c,
                       PredefinedWheelNumber__c, BetsJson__c, LastUpdatedFrom__c,
                       LastRoundAt__c, LastModifiedDate
                FROM FunTargetState__c
                WHERE UserIdKey__c = :userKey
                LIMIT 1
                FOR UPDATE
            ];
        }

        return [
            SELECT Id, Score__c, Last10Results__c, TotalBetAmount__c, WinnerAmount__c,
                   PredefinedWheelNumber__c, BetsJson__c, LastUpdatedFrom__c,
                   LastRoundAt__c, LastModifiedDate
            FROM FunTargetState__c
            WHERE UserIdKey__c = :userKey
            LIMIT 1
        ];
    }

    private static FunTargetState__c getStateRecordById(Id stateId) {
        return [
            SELECT Id, Score__c, Last10Results__c, TotalBetAmount__c, WinnerAmount__c,
                   PredefinedWheelNumber__c, BetsJson__c, LastUpdatedFrom__c,
                   LastRoundAt__c, LastModifiedDate
            FROM FunTargetState__c
            WHERE Id = :stateId
            LIMIT 1
        ];
    }

    private static StateDTO buildDefaultDto() {
        StateDTO dto = new StateDTO();
        dto.score = 1000;
        dto.predefinedWheelNumber = null;
        dto.last10Results = getDefaultLast10();
        dto.totalBetAmount = 0;
        dto.winnerAmount = 0;
        dto.betsJson = '{}';
        dto.lastUpdatedFrom = 'Site';
        dto.lastRoundAt = null;
        dto.lastModifiedDate = null;
        return dto;
    }

    private static void assertOptimisticLock(Datetime expectedLastModified, Datetime actualLastModified) {
        if (expectedLastModified == null || actualLastModified == null) {
            return;
        }
        if (expectedLastModified.getTime() != actualLastModified.getTime()) {
            throw new AuraHandledException('STATE_CONFLICT: Data changed on server. Please refresh.');
        }
    }

    private static Decimal deriveSiteScore(
        Decimal existingScore,
        Decimal existingTotalBetAmount,
        Decimal existingWinnerAmount,
        Decimal incomingTotalBetAmount,
        Decimal incomingWinnerAmount,
        Datetime incomingLastRoundAt,
        Datetime existingLastRoundAt,
        Decimal incomingRequestedScore
    ) {
        Decimal currentScore = existingScore == null ? 0 : existingScore;
        Decimal oldTotal = existingTotalBetAmount == null ? 0 : existingTotalBetAmount;
        Decimal oldWinner = existingWinnerAmount == null ? 0 : existingWinnerAmount;
        Decimal newTotal = incomingTotalBetAmount == null ? 0 : incomingTotalBetAmount;
        Decimal newWinner = incomingWinnerAmount == null ? 0 : incomingWinnerAmount;
        Decimal requestedScore = incomingRequestedScore == null ? currentScore : Math.max(0, incomingRequestedScore);

        // Explicit reset flow from Exit button.
        if (requestedScore == 0 && newTotal == 0 && newWinner == 0) {
            return 0;
        }

        Decimal derivedScore = currentScore;
        if (newTotal > oldTotal) {
            derivedScore = Math.max(0, derivedScore - (newTotal - oldTotal));
        } else if (newTotal < oldTotal) {
            if (!isRoundTransition(incomingLastRoundAt, existingLastRoundAt)) {
                derivedScore += (oldTotal - newTotal);
            }
        }

        // Winner gets transferred to score only when winner bucket is consumed.
        if (oldWinner > 0 && newWinner == 0) {
            derivedScore += oldWinner;
        }

        return Math.max(0, derivedScore);
    }

    private static Boolean isRoundTransition(Datetime incomingLastRoundAt, Datetime existingLastRoundAt) {
        if (incomingLastRoundAt == null) {
            return false;
        }
        if (existingLastRoundAt == null) {
            return true;
        }
        return incomingLastRoundAt.getTime() != existingLastRoundAt.getTime();
    }

    private static List<Integer> parseLast10(String last10Csv) {
        List<Integer> result = new List<Integer>();
        if (String.isBlank(last10Csv)) {
            return result;
        }

        for (String token : last10Csv.split(',')) {
            if (result.size() >= 10) {
                break;
            }
            String trimmed = token == null ? null : token.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            try {
                Integer value = Integer.valueOf(trimmed);
                if (value >= 0 && value <= 9) {
                    result.add(value);
                }
            } catch (Exception ex) {
                // Skip invalid values.
            }
        }
        return result;
    }

    private static String sanitizeLast10(String input, String fallbackValue) {
        String fallback = String.isNotBlank(fallbackValue) ? fallbackValue : getDefaultLast10();
        if (String.isBlank(input)) {
            return fallback;
        }

        List<Integer> parsed = parseLast10(input);
        if (parsed.isEmpty()) {
            return fallback;
        }

        List<String> serialized = new List<String>();
        for (Integer value : parsed) {
            serialized.add(String.valueOf(value));
        }
        return String.join(serialized, ',');
    }

    private static String sanitizeUpdateSource(String value) {
        if (String.isBlank(value)) {
            return 'Site';
        }

        String normalized = value.trim().toLowerCase();
        if (normalized == 'admin') {
            return 'Admin';
        }
        if (normalized == 'site') {
            return 'Site';
        }
        if (normalized == 'mobile') {
            return 'Mobile';
        }
        return 'Site';
    }

    private static Map<Integer, Decimal> parseBetsJson(String rawJson) {
        Map<Integer, Decimal> result = new Map<Integer, Decimal>();
        if (String.isBlank(rawJson)) {
            return result;
        }

        try {
            Object parsed = JSON.deserializeUntyped(rawJson);
            Map<String, Object> values;
            try {
                values = (Map<String, Object>) parsed;
            } catch (Exception castEx) {
                return result;
            }
            for (String key : values.keySet()) {
                Integer slot;
                try {
                    slot = Integer.valueOf(key);
                } catch (Exception ex) {
                    continue;
                }

                if (slot < 0 || slot > 9) {
                    continue;
                }

                Decimal amount = toPositiveDecimal(values.get(key));
                if (amount > 0) {
                    result.put(slot, amount);
                }
            }
        } catch (Exception ex) {
            return new Map<Integer, Decimal>();
        }

        return result;
    }

    private static Decimal toPositiveDecimal(Object value) {
        if (value == null) {
            return 0;
        }

        Decimal parsed;
        try {
            if (value instanceof Decimal) {
                parsed = (Decimal) value;
            } else if (value instanceof String) {
                parsed = Decimal.valueOf(((String) value).trim());
            } else {
                parsed = Decimal.valueOf(String.valueOf(value));
            }
        } catch (Exception ex) {
            return 0;
        }

        return parsed > 0 ? parsed : 0;
    }

    private static Decimal sumBetAmounts(Map<Integer, Decimal> bets) {
        if (bets == null || bets.isEmpty()) {
            return 0;
        }

        Decimal total = 0;
        for (Decimal amount : bets.values()) {
            total += amount == null ? 0 : amount;
        }
        return total;
    }

    private static String serializeBetsJson(Map<Integer, Decimal> bets) {
        if (bets == null || bets.isEmpty()) {
            return '{}';
        }

        List<Integer> keys = new List<Integer>();
        keys.addAll(bets.keySet());
        keys.sort();

        Map<String, Decimal> ordered = new Map<String, Decimal>();
        for (Integer key : keys) {
            ordered.put(String.valueOf(key), bets.get(key));
        }

        return JSON.serialize(ordered);
    }

    private static String getDefaultLast10() {
        DescribeFieldResult describe = FunTargetState__c.Last10Results__c.getDescribe();
        Object configuredDefault = describe.getDefaultValue();
        if (configuredDefault != null) {
            return String.valueOf(configuredDefault);
        }

        String formulaDefault = describe.getDefaultValueFormula();
        if (String.isBlank(formulaDefault)) {
            return FALLBACK_LAST10;
        }

        // Text field defaults are returned as quoted formula strings, e.g. "1,2,3"
        if (formulaDefault.startsWith('"') && formulaDefault.endsWith('"') && formulaDefault.length() >= 2) {
            return formulaDefault.substring(1, formulaDefault.length() - 1);
        }
        return formulaDefault;
    }

    private static StateDTO toDto(FunTargetState__c recordData) {
        StateDTO dto = new StateDTO();
        dto.recordId = recordData.Id;
        dto.score = recordData.Score__c;
        dto.predefinedWheelNumber = recordData.PredefinedWheelNumber__c == null
            ? null
            : recordData.PredefinedWheelNumber__c.intValue();
        dto.last10Results = recordData.Last10Results__c;
        dto.totalBetAmount = recordData.TotalBetAmount__c;
        dto.winnerAmount = recordData.WinnerAmount__c;
        dto.betsJson = recordData.BetsJson__c;
        dto.lastUpdatedFrom = recordData.LastUpdatedFrom__c;
        dto.lastRoundAt = recordData.LastRoundAt__c;
        dto.lastModifiedDate = recordData.LastModifiedDate;
        return dto;
    }
}
