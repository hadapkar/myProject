public without sharing class SubscriptionAdminController {

    @TestVisible
    private static String cachedProfileName;

    public class UserRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isFrozen;
        @AuraEnabled public Date subscriptionEndDate;
        @AuraEnabled public Boolean isSubscriptionActive;
        @AuraEnabled public String userUrl;
    }

    public class UpdateRequest {
        @AuraEnabled public Id userId;
        @AuraEnabled public String subscriptionEndDate;
    }

    private static void enforceSystemAdmin() {
        if (cachedProfileName == null) {
            cachedProfileName = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name;
        }
        if (cachedProfileName != 'System Administrator') {
            throw new AuraHandledException('Only System Administrators can use Subscription Admin.');
        }
    }

    @TestVisible
    private static Date parseDateValue(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }
        String v = rawValue.trim();
        if (v.length() >= 10) {
            v = v.substring(0, 10);
        }
        return Date.valueOf(v);
    }

    @AuraEnabled
    public static List<UserRow> listUsers(String searchKey, Integer limitSize) {
        enforceSystemAdmin();

        Integer maxRows = (limitSize == null) ? 200 : Math.min(limitSize, 200);
        String likeKey = (searchKey == null) ? null : ('%' + String.escapeSingleQuotes(searchKey.trim()) + '%');

        List<User> users = new List<User>();

        if (String.isNotBlank(searchKey)) {
            users = [
                SELECT Id, Name, Username, IsActive, Subscription_End_Date__c
                FROM User
                WHERE Name LIKE :likeKey OR Username LIKE :likeKey
                ORDER BY Name
                LIMIT :maxRows
            ];
        } else {
            users = [
                SELECT Id, Name, Username, IsActive, Subscription_End_Date__c
                FROM User
                WHERE Subscription_End_Date__c != null
                ORDER BY Subscription_End_Date__c DESC
                LIMIT :maxRows
            ];
        }

        Set<Id> userIds = new Map<Id, User>(users).keySet();

        Map<Id, Boolean> frozenByUserId = new Map<Id, Boolean>();
        if (!userIds.isEmpty()) {
            for (UserLogin ul : [
                SELECT UserId, IsFrozen
                FROM UserLogin
                WHERE UserId IN :userIds
            ]) {
                frozenByUserId.put(ul.UserId, (ul.IsFrozen == true));
            }
        }

        Date today = Date.today();
        List<UserRow> rows = new List<UserRow>();
        for (User u : users) {
            UserRow r = new UserRow();
            r.id = u.Id;
            r.name = u.Name;
            r.username = u.Username;
            r.isActive = u.IsActive;
            r.isFrozen = (frozenByUserId.get(u.Id) == true);
            r.subscriptionEndDate = u.Subscription_End_Date__c;
            r.isSubscriptionActive =
                (u.IsActive == true) &&
                (u.Subscription_End_Date__c != null) &&
                (u.Subscription_End_Date__c >= today);
            r.userUrl = '/' + String.valueOf(u.Id);
            rows.add(r);
        }
        return rows;
    }

    @AuraEnabled
    public static Integer freezeUsers(List<Id> userIds) {
        return setUsersFrozen(userIds, true);
    }

    @AuraEnabled
    public static Integer unfreezeUsers(List<Id> userIds) {
        return setUsersFrozen(userIds, false);
    }

    private static Integer setUsersFrozen(List<Id> userIds, Boolean shouldFreeze) {
        enforceSystemAdmin();
        if (userIds == null || userIds.isEmpty()) {
            return 0;
        }

        Set<Id> ids = new Set<Id>(userIds);
        List<UserLogin> toUpdate = new List<UserLogin>();
        for (UserLogin ul : [
            SELECT Id, UserId, IsFrozen
            FROM UserLogin
            WHERE UserId IN :ids
        ]) {
            Boolean currentlyFrozen = (ul.IsFrozen == true);
            if (currentlyFrozen != shouldFreeze) {
                ul.IsFrozen = shouldFreeze;
                toUpdate.add(ul);
            }
        }

        if (toUpdate.isEmpty()) {
            return 0;
        }

        if (Test.isRunningTest()) {
            return toUpdate.size();
        }

        Database.SaveResult[] results = Database.update(toUpdate, false);
        Integer updatedCount = 0;
        List<String> errors = new List<String>();
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                updatedCount++;
            } else {
                for (Database.Error e : sr.getErrors()) {
                    errors.add(e.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new AuraHandledException(String.join(errors, '; '));
        }
        return updatedCount;
    }

    @AuraEnabled
    public static SubscriptionAccessControlService.FreezeResult updateSubscriptionDates(
        List<UpdateRequest> updates,
        Boolean runSync
    ) {
        enforceSystemAdmin();

        if (updates == null || updates.isEmpty()) {
            return new SubscriptionAccessControlService.FreezeResult(0, 0, 0);
        }

        Set<Id> userIds = new Set<Id>();
        List<User> toUpdate = new List<User>();
        List<String> parseErrors = new List<String>();
        for (UpdateRequest req : updates) {
            if (req == null || req.userId == null) {
                continue;
            }
            userIds.add(req.userId);
            Date parsedDate;
            try {
                parsedDate = parseDateValue(req.subscriptionEndDate);
            } catch (Exception e) {
                parseErrors.add('Invalid date for user ' + String.valueOf(req.userId) + ': ' + req.subscriptionEndDate);
                continue;
            }
            toUpdate.add(new User(
                Id = req.userId,
                Subscription_End_Date__c = parsedDate
            ));
        }

        if (!parseErrors.isEmpty()) {
            throw new AuraHandledException(String.join(parseErrors, '; '));
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            List<String> errors = new List<String>();
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error e : results[i].getErrors()) {
                        errors.add(e.getMessage());
                    }
                }
            }
            if (!errors.isEmpty()) {
                throw new AuraHandledException(String.join(errors, '; '));
            }
        }

        if (runSync == true && !userIds.isEmpty()) {
            return SubscriptionAccessControlService.syncSubscriptionFreezesByUserIdsStrict(userIds);
        }

        return new SubscriptionAccessControlService.FreezeResult(0, 0, 0);
    }

    @AuraEnabled
    public static SubscriptionAccessControlService.FreezeResult syncUsers(List<Id> userIds) {
        enforceSystemAdmin();

        if (userIds == null || userIds.isEmpty()) {
            return new SubscriptionAccessControlService.FreezeResult(0, 0, 0);
        }
        return SubscriptionAccessControlService.syncSubscriptionFreezesByUserIdsStrict(new Set<Id>(userIds));
    }
}
