Id uId = UserInfo.getUserId();
System.debug('Current user: ' + uId);

SubscriptionAdminController.UpdateRequest r = new SubscriptionAdminController.UpdateRequest();
r.userId = uId;
r.subscriptionEndDate = String.valueOf(Date.today().addDays(7));

SubscriptionAccessControlService.SyncResult res =
    SubscriptionAdminController.updateSubscriptionDates(new List<SubscriptionAdminController.UpdateRequest>{ r }, false);

System.debug('Result inserted=' + res.insertedCount + ', deleted=' + res.deletedCount);
System.debug([
    SELECT Id, Subscription_End_Date__c
    FROM User
    WHERE Id = :uId
]);

