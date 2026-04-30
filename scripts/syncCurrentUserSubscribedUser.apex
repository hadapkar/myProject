Id uId = UserInfo.getUserId();
SubscriptionAccessControlService.SyncResult res =
    SubscriptionAccessControlService.syncUserIds(new Set<Id>{ uId });
System.debug('Attempted inserted=' + res.insertedCount + ' deleted=' + res.deletedCount);

Id psgId = [SELECT Id FROM PermissionSetGroup WHERE DeveloperName='Subscribed_User' LIMIT 1].Id;
System.debug([
    SELECT Id, AssigneeId, PermissionSetGroupId
    FROM PermissionSetAssignment
    WHERE AssigneeId = :uId
    AND PermissionSetGroupId = :psgId
]);

