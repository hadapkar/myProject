Id currentUserId = UserInfo.getUserId();
Id targetUserId = '005gL00000H87TxQAJ';

System.debug('Current=' + currentUserId + ' Target=' + targetUserId);

SubscriptionAdminController.UpdateRequest r = new SubscriptionAdminController.UpdateRequest();
r.userId = targetUserId;
r.subscriptionEndDate = String.valueOf(Date.today().addDays(14));

try {
    SubscriptionAccessControlService.SyncResult res =
        SubscriptionAdminController.updateSubscriptionDates(
            new List<SubscriptionAdminController.UpdateRequest>{ r },
            true
        );
    System.debug('Update ok. inserted=' + res.insertedCount + ' deleted=' + res.deletedCount);
} catch (Exception e) {
    System.debug('Update failed: ' + e.getTypeName() + ' ' + e.getMessage());
}

System.debug([
    SELECT Id, Username, Subscription_End_Date__c
    FROM User
    WHERE Id IN :new List<Id>{ currentUserId, targetUserId }
]);

