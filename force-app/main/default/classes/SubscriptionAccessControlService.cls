public without sharing class SubscriptionAccessControlService {

    @TestVisible
    private static IDataAccess dataAccess;

    @TestVisible
    private static IUserLoginAccess userLoginAccess;

    public class MissingPermissionSetGroupException extends Exception {}

    public class FreezeResult {
        @AuraEnabled public Integer frozenCount { get; private set; }
        @AuraEnabled public Integer unfrozenCount { get; private set; }
        @AuraEnabled public Integer permissionAssignmentsDeletedCount { get; private set; }

        public FreezeResult(Integer frozenCount, Integer unfrozenCount, Integer permissionAssignmentsDeletedCount) {
            this.frozenCount = frozenCount;
            this.unfrozenCount = unfrozenCount;
            this.permissionAssignmentsDeletedCount = permissionAssignmentsDeletedCount;
        }
    }

    public class DmlOutcome {
        public Integer successCount { get; private set; }
        public List<String> errors { get; private set; }

        public DmlOutcome(Integer successCount, List<String> errors) {
            this.successCount = (successCount == null) ? 0 : successCount;
            this.errors = (errors == null) ? new List<String>() : errors;
        }
    }

    public interface IDataAccess {
        Id getPermissionSetGroupId(String developerName);
        List<PermissionSetAssignment> getAssignments(Id permissionSetGroupId, Set<Id> userIds);
        void deleteAssignments(List<PermissionSetAssignment> assignmentsToDelete);
    }

    public interface IUserLoginAccess {
        Map<Id, Boolean> getFrozenByUserId(Set<Id> userIds);
        DmlOutcome updateFrozenFlags(Map<Id, Boolean> desiredFrozenByUserId);
    }

    private class DefaultUserLoginAccess implements IUserLoginAccess {
        public Map<Id, Boolean> getFrozenByUserId(Set<Id> userIds) {
            Map<Id, Boolean> frozenByUserId = new Map<Id, Boolean>();
            if (userIds == null || userIds.isEmpty()) {
                return frozenByUserId;
            }
            for (UserLogin ul : [
                SELECT UserId, IsFrozen
                FROM UserLogin
                WHERE UserId IN :userIds
            ]) {
                frozenByUserId.put(ul.UserId, (ul.IsFrozen == true));
            }
            return frozenByUserId;
        }

        public DmlOutcome updateFrozenFlags(Map<Id, Boolean> desiredFrozenByUserId) {
            if (desiredFrozenByUserId == null || desiredFrozenByUserId.isEmpty()) {
                return new DmlOutcome(0, new List<String>());
            }

            List<UserLogin> toUpdate = new List<UserLogin>();
            for (UserLogin ul : [
                SELECT Id, UserId, IsFrozen
                FROM UserLogin
                WHERE UserId IN :desiredFrozenByUserId.keySet()
            ]) {
                Boolean desired = (desiredFrozenByUserId.get(ul.UserId) == true);
                Boolean current = (ul.IsFrozen == true);
                if (desired != current) {
                    toUpdate.add(new UserLogin(
                        Id = ul.Id,
                        IsFrozen = desired
                    ));
                }
            }

            if (toUpdate.isEmpty()) {
                return new DmlOutcome(0, new List<String>());
            }

            Database.SaveResult[] results = Database.update(toUpdate, false);
            Integer successCount = 0;
            List<String> errors = new List<String>();
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error e : sr.getErrors()) {
                        errors.add(e.getMessage());
                    }
                }
            }
            return new DmlOutcome(successCount, errors);
        }
    }

    private virtual class DefaultDataAccess implements IDataAccess {
        public Id getPermissionSetGroupId(String developerName) {
            List<PermissionSetGroup> groups =
                [SELECT Id FROM PermissionSetGroup WHERE DeveloperName = :developerName LIMIT 1];
            if (groups.isEmpty()) {
                throw new MissingPermissionSetGroupException(
                    'Permission Set Group not found: ' + developerName
                );
            }
            return groups[0].Id;
        }

        public List<PermissionSetAssignment> getAssignments(Id permissionSetGroupId, Set<Id> userIds) {
            if (permissionSetGroupId == null || userIds == null || userIds.isEmpty()) {
                return new List<PermissionSetAssignment>();
            }
            return [
                SELECT Id, AssigneeId, PermissionSetGroupId
                FROM PermissionSetAssignment
                WHERE PermissionSetGroupId = :permissionSetGroupId
                AND AssigneeId IN :userIds
            ];
        }

        public virtual void deleteAssignments(List<PermissionSetAssignment> assignmentsToDelete) {
            if (assignmentsToDelete == null || assignmentsToDelete.isEmpty()) {
                return;
            }
            Database.delete(assignmentsToDelete, false);
        }
    }

    private static IDataAccess getDataAccess() {
        if (dataAccess == null) {
            dataAccess = new DefaultDataAccess();
        }
        return dataAccess;
    }

    private static IUserLoginAccess getUserLoginAccess() {
        if (userLoginAccess == null) {
            userLoginAccess = new DefaultUserLoginAccess();
        }
        return userLoginAccess;
    }

    public static Id getSubscribedUserPermissionSetGroupId() {
        return getDataAccess().getPermissionSetGroupId('Subscribed_User');
    }

    public static FreezeResult syncSubscriptionFreezesByUserIds(Set<Id> userIds) {
        return syncSubscriptionFreezesByUserIdsInternal(userIds, false);
    }

    public static FreezeResult syncSubscriptionFreezesByUserIdsStrict(Set<Id> userIds) {
        return syncSubscriptionFreezesByUserIdsInternal(userIds, true);
    }

    private static FreezeResult syncSubscriptionFreezesByUserIdsInternal(Set<Id> userIds, Boolean strictDml) {
        if (userIds == null || userIds.isEmpty()) {
            return new FreezeResult(0, 0, 0);
        }

        List<User> users = [
            SELECT Id, IsActive, UserType, Subscription_End_Date__c
            FROM User
            WHERE Id IN :userIds
        ];
        return syncSubscriptionFreezesByUsersInternal(users, strictDml);
    }

    public static FreezeResult syncSubscriptionFreezesByUsers(List<User> users) {
        return syncSubscriptionFreezesByUsersInternal(users, false);
    }

    public static FreezeResult syncSubscriptionFreezesByUsersStrict(List<User> users) {
        return syncSubscriptionFreezesByUsersInternal(users, true);
    }

    private static FreezeResult syncSubscriptionFreezesByUsersInternal(List<User> users, Boolean strictDml) {
        if (users == null || users.isEmpty()) {
            return new FreezeResult(0, 0, 0);
        }

        Date today = Date.today();

        Set<Id> userIds = new Set<Id>();
        Map<Id, User> usersById = new Map<Id, User>();
        for (User u : users) {
            if (u == null || u.Id == null) {
                continue;
            }
            if (u.UserType == 'Guest') {
                continue;
            }
            if (u.IsActive != true) {
                continue;
            }
            userIds.add(u.Id);
            usersById.put(u.Id, u);
        }
        if (userIds.isEmpty()) {
            return new FreezeResult(0, 0, 0);
        }

        Map<Id, Boolean> currentFrozenByUserId = getUserLoginAccess().getFrozenByUserId(userIds);

        Map<Id, Boolean> desiredFrozenByUserId = new Map<Id, Boolean>();
        Integer toFreezeCount = 0;
        Integer toUnfreezeCount = 0;

        for (Id userId : userIds) {
            User u = usersById.get(userId);
            Date endDate = u.Subscription_End_Date__c;
            Boolean desiredFrozen = (endDate == null || endDate < today);

            if (!currentFrozenByUserId.containsKey(userId)) {
                continue;
            }

            Boolean currentFrozen = (currentFrozenByUserId.get(userId) == true);
            if (currentFrozen != desiredFrozen) {
                desiredFrozenByUserId.put(userId, desiredFrozen);
                if (desiredFrozen == true) {
                    toFreezeCount++;
                } else {
                    toUnfreezeCount++;
                }
            }
        }

        DmlOutcome freezeOutcome = getUserLoginAccess().updateFrozenFlags(desiredFrozenByUserId);
        if (strictDml == true && freezeOutcome != null && freezeOutcome.errors != null && !freezeOutcome.errors.isEmpty()) {
            throw new AuraHandledException(String.join(freezeOutcome.errors, '; '));
        }

        DmlOutcome psaOutcome = deleteSubscribedUserPermissionAssignments(userIds);
        if (strictDml == true && psaOutcome != null && psaOutcome.errors != null && !psaOutcome.errors.isEmpty()) {
            throw new AuraHandledException(String.join(psaOutcome.errors, '; '));
        }

        return new FreezeResult(toFreezeCount, toUnfreezeCount, (psaOutcome == null ? 0 : psaOutcome.successCount));
    }

    private static DmlOutcome deleteSubscribedUserPermissionAssignments(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new DmlOutcome(0, new List<String>());
        }

        Id psgId;
        try {
            psgId = getSubscribedUserPermissionSetGroupId();
        } catch (Exception e) {
            return new DmlOutcome(0, new List<String>());
        }

        List<PermissionSetAssignment> toDelete = getDataAccess().getAssignments(psgId, userIds);
        if (toDelete.isEmpty()) {
            return new DmlOutcome(0, new List<String>());
        }

        getDataAccess().deleteAssignments(toDelete);
        return new DmlOutcome(toDelete.size(), new List<String>());
    }
}
