@IsTest
private class SubscriptionAdminControllerTest {

    private class FakeDataAccess implements SubscriptionAccessControlService.IDataAccess {
        public Id psgId = (Id) '0PG000000000001';
        public List<PermissionSetAssignment> deleted = new List<PermissionSetAssignment>();

        public Id getPermissionSetGroupId(String developerName) {
            return psgId;
        }

        public List<PermissionSetAssignment> getAssignments(Id permissionSetGroupId, Set<Id> userIds) {
            List<PermissionSetAssignment> results = new List<PermissionSetAssignment>();
            for (Id userId : userIds) {
                PermissionSetAssignment psa = new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetGroupId = permissionSetGroupId
                );
                psa.Id = (Id) ('0Pa0000000000' + String.valueOf(100 + results.size())).left(15);
                results.add(psa);
            }
            return results;
        }

        public void deleteAssignments(List<PermissionSetAssignment> assignmentsToDelete) {
            if (assignmentsToDelete != null) {
                deleted.addAll(assignmentsToDelete);
            }
        }
    }

    private class FakeUserLoginAccess implements SubscriptionAccessControlService.IUserLoginAccess {
        public Map<Id, Boolean> frozenByUserId = new Map<Id, Boolean>();

        public Map<Id, Boolean> getFrozenByUserId(Set<Id> userIds) {
            Map<Id, Boolean> results = new Map<Id, Boolean>();
            for (Id userId : userIds) {
                results.put(userId, (frozenByUserId.get(userId) == true));
            }
            return results;
        }

        public SubscriptionAccessControlService.DmlOutcome updateFrozenFlags(Map<Id, Boolean> desiredFrozenByUserId) {
            if (desiredFrozenByUserId == null || desiredFrozenByUserId.isEmpty()) {
                return new SubscriptionAccessControlService.DmlOutcome(0, new List<String>());
            }
            for (Id userId : desiredFrozenByUserId.keySet()) {
                frozenByUserId.put(userId, (desiredFrozenByUserId.get(userId) == true));
            }
            return new SubscriptionAccessControlService.DmlOutcome(desiredFrozenByUserId.size(), new List<String>());
        }
    }

    private static User makeUser(Date subscriptionEndDate) {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' ORDER BY Id LIMIT 1];
        String unique = String.valueOf(DateTime.now().getTime()) + String.valueOf(Math.abs(Crypto.getRandomInteger()));

        User u = new User(
            ProfileId = p.Id,
            Username = 'subadmintest+' + unique + '@example.com',
            Email = 'subadmintest+' + unique + '@example.com',
            Alias = 'sat' + unique.substring(0, 2),
            LastName = 'User',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        u.Subscription_End_Date__c = subscriptionEndDate;
        insert u;
        return [SELECT Id, Username, IsActive, UserType, Subscription_End_Date__c FROM User WHERE Id = :u.Id];
    }

    @IsTest
    static void listUsers_returnsUsersAndSubscriptionFields() {
        SubscriptionAdminController.cachedProfileName = 'System Administrator';

        User u = makeUser(Date.today().addDays(5));
        List<SubscriptionAdminController.UserRow> rows = SubscriptionAdminController.listUsers(String.valueOf(u.Username), 50);

        System.assertEquals(1, rows.size(), 'Expected search to return created user');
        System.assertEquals(u.Id, rows[0].id);
        System.assertEquals(u.Subscription_End_Date__c, rows[0].subscriptionEndDate);
        System.assertEquals(true, rows[0].isSubscriptionActive, 'Future date should be active');
    }

    @IsTest
    static void updateSubscriptionDates_allowsClearingDate_andFreezes() {
        SubscriptionAdminController.cachedProfileName = 'System Administrator';

        FakeDataAccess fakeDa = new FakeDataAccess();
        SubscriptionAccessControlService.dataAccess = fakeDa;

        FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
        SubscriptionAccessControlService.userLoginAccess = fakeLogin;

        User u = makeUser(Date.today().addDays(10));
        fakeLogin.frozenByUserId.put(u.Id, false);

        SubscriptionAdminController.UpdateRequest req = new SubscriptionAdminController.UpdateRequest();
        req.userId = u.Id;
        req.subscriptionEndDate = null;

        SubscriptionAccessControlService.FreezeResult result =
            SubscriptionAdminController.updateSubscriptionDates(
                new List<SubscriptionAdminController.UpdateRequest>{ req },
                true
            );

        User updated = [SELECT Subscription_End_Date__c FROM User WHERE Id = :u.Id];
        System.assertEquals(null, updated.Subscription_End_Date__c, 'Should clear the field');
        System.assertEquals(1, result.frozenCount, 'Clearing date should freeze');
        System.assertEquals(true, fakeLogin.frozenByUserId.get(u.Id), 'User should be frozen');
        System.assertEquals(1, result.permissionAssignmentsDeletedCount, 'Should delete legacy PSG assignment');
    }

    @IsTest
    static void syncUsers_unfreezesWhenDateActive() {
        SubscriptionAdminController.cachedProfileName = 'System Administrator';

        FakeDataAccess fakeDa = new FakeDataAccess();
        SubscriptionAccessControlService.dataAccess = fakeDa;

        FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
        SubscriptionAccessControlService.userLoginAccess = fakeLogin;

        User u = makeUser(Date.today().addDays(3));
        fakeLogin.frozenByUserId.put(u.Id, true);

        SubscriptionAccessControlService.FreezeResult result =
            SubscriptionAdminController.syncUsers(new List<Id>{ u.Id });

        System.assertEquals(0, result.frozenCount);
        System.assertEquals(1, result.unfrozenCount, 'Future date should unfreeze');
        System.assertEquals(false, fakeLogin.frozenByUserId.get(u.Id), 'User should be unfrozen');
        System.assertEquals(1, result.permissionAssignmentsDeletedCount, 'Should delete legacy PSG assignment');
    }

    @IsTest
    static void nonAdminIsBlocked() {
        SubscriptionAdminController.cachedProfileName = 'Standard User';
        try {
            SubscriptionAdminController.listUsers(null, 10);
            System.assert(false, 'Expected exception for non-admin');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage(), 'Expected an error message');
        }
    }

    @IsTest
    static void updateSubscriptionDates_parsesIsoLikeStrings() {
        SubscriptionAdminController.cachedProfileName = 'System Administrator';

        FakeDataAccess fakeDa = new FakeDataAccess();
        SubscriptionAccessControlService.dataAccess = fakeDa;

        FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
        SubscriptionAccessControlService.userLoginAccess = fakeLogin;

        User u = makeUser(Date.today().addDays(1));
        fakeLogin.frozenByUserId.put(u.Id, false);

        SubscriptionAdminController.UpdateRequest req = new SubscriptionAdminController.UpdateRequest();
        req.userId = u.Id;
        req.subscriptionEndDate = '2026-05-01T00:00:00.000Z';

        SubscriptionAdminController.updateSubscriptionDates(new List<SubscriptionAdminController.UpdateRequest>{ req }, false);

        User updated = [SELECT Subscription_End_Date__c FROM User WHERE Id = :u.Id];
        System.assertEquals(Date.newInstance(2026, 5, 1), updated.Subscription_End_Date__c, 'Should parse first 10 chars as date');
    }

    @IsTest
    static void freezeOrUnfreeze_currentUser_smoke() {
        SubscriptionAdminController.cachedProfileName = 'System Administrator';

        UserLogin ul = [
            SELECT UserId, IsFrozen
            FROM UserLogin
            WHERE UserId = :UserInfo.getUserId()
            LIMIT 1
        ];

        Integer updated;
        if (ul.IsFrozen == true) {
            updated = SubscriptionAdminController.unfreezeUsers(new List<Id>{ ul.UserId });
        } else {
            updated = SubscriptionAdminController.freezeUsers(new List<Id>{ ul.UserId });
        }
        System.assert(updated >= 0, 'Should return a non-negative count');
    }
}
