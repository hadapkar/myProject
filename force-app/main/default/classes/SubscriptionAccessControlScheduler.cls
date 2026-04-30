public without sharing class SubscriptionAccessControlScheduler implements Schedulable, Database.Batchable<SObject> {

    @TestVisible
    private static List<User> testUsers;

    @TestVisible
    private static String testUserQueryOverride;

    public void execute(SchedulableContext sc) {
        if (Test.isRunningTest() && testUsers != null) {
            SubscriptionAccessControlService.syncSubscriptionFreezesByUsers(testUsers);
            return;
        }
        Database.executeBatch(new SubscriptionAccessControlScheduler(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (Test.isRunningTest() && testUserQueryOverride != null) {
            return Database.getQueryLocator(testUserQueryOverride);
        }

        return Database.getQueryLocator([
            SELECT Id, IsActive, UserType, Subscription_End_Date__c
            FROM User
            WHERE IsActive = true
            AND UserType != 'Guest'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<User> users = (List<User>) scope;
        SubscriptionAccessControlService.syncSubscriptionFreezesByUsers(users);
    }

    public void finish(Database.BatchableContext bc) {
    }
}
