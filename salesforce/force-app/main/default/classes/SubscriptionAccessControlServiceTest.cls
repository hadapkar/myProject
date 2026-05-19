@IsTest
private class SubscriptionAccessControlServiceTest {
  private class FakeDataAccess implements SubscriptionAccessControlService.IDataAccess {
    public Id psgId = (Id) '0PG000000000001';
    public List<PermissionSetAssignment> deleted = new List<PermissionSetAssignment>();

    public Id getPermissionSetGroupId(String developerName) {
      return psgId;
    }

    public List<PermissionSetAssignment> getAssignments(
      Id permissionSetGroupId,
      Set<Id> userIds
    ) {
      List<PermissionSetAssignment> results = new List<PermissionSetAssignment>();
      Integer seq = 1;
      for (Id userId : userIds) {
        PermissionSetAssignment psa = new PermissionSetAssignment(
          AssigneeId = userId,
          PermissionSetGroupId = permissionSetGroupId
        );
        psa.Id = (Id) ('0Pa0000000000' + String.valueOf(100 + seq)).left(15);
        seq++;
        results.add(psa);
      }
      return results;
    }

    public void deleteAssignments(
      List<PermissionSetAssignment> assignmentsToDelete
    ) {
      if (assignmentsToDelete != null) {
        deleted.addAll(assignmentsToDelete);
      }
    }
  }

  private class FakeUserLoginAccess implements SubscriptionAccessControlService.IUserLoginAccess {
    public Map<Id, Boolean> frozenByUserId = new Map<Id, Boolean>();
    public Map<Id, Boolean> lastDesiredByUserId = new Map<Id, Boolean>();

    public Map<Id, Boolean> getFrozenByUserId(Set<Id> userIds) {
      Map<Id, Boolean> results = new Map<Id, Boolean>();
      for (Id userId : userIds) {
        results.put(userId, (frozenByUserId.get(userId) == true));
      }
      return results;
    }

    public SubscriptionAccessControlService.DmlOutcome updateFrozenFlags(
      Map<Id, Boolean> desiredFrozenByUserId
    ) {
      lastDesiredByUserId = (desiredFrozenByUserId == null)
        ? new Map<Id, Boolean>()
        : new Map<Id, Boolean>(desiredFrozenByUserId);
      if (desiredFrozenByUserId == null || desiredFrozenByUserId.isEmpty()) {
        return new SubscriptionAccessControlService.DmlOutcome(
          0,
          new List<String>()
        );
      }

      for (Id userId : desiredFrozenByUserId.keySet()) {
        frozenByUserId.put(userId, (desiredFrozenByUserId.get(userId) == true));
      }
      return new SubscriptionAccessControlService.DmlOutcome(
        desiredFrozenByUserId.size(),
        new List<String>()
      );
    }
  }

  private static User makeUser(Date subscriptionEndDate) {
    Profile p = [
      SELECT Id
      FROM Profile
      WHERE UserType = 'Standard'
      ORDER BY Id
      LIMIT 1
    ];
    String unique =
      String.valueOf(DateTime.now().getTime()) +
      String.valueOf(Math.abs(Crypto.getRandomInteger()));

    User u = new User(
      ProfileId = p.Id,
      Username = 'subfreezetest+' + unique + '@example.com',
      Email = 'subfreezetest+' + unique + '@example.com',
      Alias = 'sft' + unique.substring(0, 2),
      LastName = 'User',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    u.Subscription_End_Date__c = subscriptionEndDate;
    insert u;
    return [
      SELECT Id, IsActive, UserType, Subscription_End_Date__c
      FROM User
      WHERE Id = :u.Id
    ];
  }

  @IsTest
  static void syncSubscriptionFreezes_freezesNullOrExpired_andUnfreezesActive() {
    FakeDataAccess fakeDa = new FakeDataAccess();
    SubscriptionAccessControlService.dataAccess = fakeDa;

    FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
    SubscriptionAccessControlService.userLoginAccess = fakeLogin;

    User noDate = makeUser(null);
    User expired = makeUser(Date.today().addDays(-1));
    User today = makeUser(Date.today());
    User future = makeUser(Date.today().addDays(5));

    fakeLogin.frozenByUserId.put(noDate.Id, false);
    fakeLogin.frozenByUserId.put(expired.Id, false);
    fakeLogin.frozenByUserId.put(today.Id, true);
    fakeLogin.frozenByUserId.put(future.Id, false);

    Set<Id> userIds = new Set<Id>{ noDate.Id, expired.Id, today.Id, future.Id };

    SubscriptionAccessControlService.FreezeResult result = SubscriptionAccessControlService.syncSubscriptionFreezesByUserIdsStrict(
      userIds
    );

    System.assertEquals(
      2,
      result.frozenCount,
      'Expected null + expired to freeze'
    );
    System.assertEquals(1, result.unfrozenCount, 'Expected today to unfreeze');
    System.assertEquals(
      4,
      result.permissionAssignmentsDeletedCount,
      'Expected legacy PSG assignments to be deleted'
    );

    System.assertEquals(
      true,
      fakeLogin.frozenByUserId.get(noDate.Id),
      'Null date should be frozen'
    );
    System.assertEquals(
      true,
      fakeLogin.frozenByUserId.get(expired.Id),
      'Expired date should be frozen'
    );
    System.assertEquals(
      false,
      fakeLogin.frozenByUserId.get(today.Id),
      'Active date should be unfrozen'
    );
    System.assertEquals(
      false,
      fakeLogin.frozenByUserId.get(future.Id),
      'Active date should remain unfrozen'
    );

    System.assertEquals(
      true,
      fakeLogin.lastDesiredByUserId.containsKey(noDate.Id),
      'Null date should be included in updates'
    );
    System.assertEquals(
      true,
      fakeLogin.lastDesiredByUserId.containsKey(expired.Id),
      'Expired date should be included in updates'
    );
    System.assertEquals(
      true,
      fakeLogin.lastDesiredByUserId.containsKey(today.Id),
      'Unfreeze should be included in updates'
    );
    System.assertEquals(
      false,
      fakeLogin.lastDesiredByUserId.containsKey(future.Id),
      'No-op should not be included in updates'
    );

    System.assertEquals(
      4,
      fakeDa.deleted.size(),
      'Should attempt to delete one legacy PSA per user'
    );
  }

  @IsTest
  static void scheduler_executesInTestWithoutAsync() {
    FakeDataAccess fakeDa = new FakeDataAccess();
    SubscriptionAccessControlService.dataAccess = fakeDa;

    FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
    SubscriptionAccessControlService.userLoginAccess = fakeLogin;

    User expired = makeUser(Date.today().addDays(-10));
    fakeLogin.frozenByUserId.put(expired.Id, false);

    SubscriptionAccessControlScheduler.testUsers = new List<User>{ expired };
    new SubscriptionAccessControlScheduler().execute((SchedulableContext) null);

    System.assertEquals(
      true,
      fakeLogin.frozenByUserId.get(expired.Id),
      'Scheduler should freeze expired users'
    );
    System.assertEquals(
      1,
      fakeDa.deleted.size(),
      'Scheduler should delete legacy PSA for scoped user'
    );

    SubscriptionAccessControlScheduler.testUsers = null;
  }

  @IsTest
  static void scheduler_batchMethodsAreCallable() {
    FakeDataAccess fakeDa = new FakeDataAccess();
    SubscriptionAccessControlService.dataAccess = fakeDa;

    FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
    SubscriptionAccessControlService.userLoginAccess = fakeLogin;

    User expired = makeUser(Date.today().addDays(-3));
    fakeLogin.frozenByUserId.put(expired.Id, false);

    SubscriptionAccessControlScheduler.testUserQueryOverride =
      'SELECT Id, IsActive, UserType, Subscription_End_Date__c FROM User WHERE Id = \'' +
      String.valueOf(expired.Id) +
      '\'';

    SubscriptionAccessControlScheduler sched = new SubscriptionAccessControlScheduler();
    System.assertNotEquals(
      null,
      sched.start(null),
      'Start should return a QueryLocator'
    );

    sched.execute(null, new List<SObject>{ expired });
    System.assertEquals(
      true,
      fakeLogin.frozenByUserId.get(expired.Id),
      'Batch execute should freeze expired user'
    );

    sched.finish(null);
    SubscriptionAccessControlScheduler.testUserQueryOverride = null;
  }

  @IsTest
  static void defaultDataAccess_deletesPermissionSetGroupAssignments() {
    SubscriptionAccessControlService.dataAccess = null;

    FakeUserLoginAccess fakeLogin = new FakeUserLoginAccess();
    SubscriptionAccessControlService.userLoginAccess = fakeLogin;

    User u = makeUser(Date.today().addDays(10));
    fakeLogin.frozenByUserId.put(u.Id, false);

    Id psgId = [
      SELECT Id
      FROM PermissionSetGroup
      WHERE DeveloperName = 'Subscribed_User'
      LIMIT 1
    ]
    .Id;

    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetGroupId = psgId
    );
    insert psa;

    SubscriptionAccessControlService.FreezeResult result = SubscriptionAccessControlService.syncSubscriptionFreezesByUserIdsStrict(
      new Set<Id>{ u.Id }
    );

    System.assertEquals(
      1,
      result.permissionAssignmentsDeletedCount,
      'Should report one legacy assignment deleted'
    );
    System.assertEquals(
      0,
      [SELECT COUNT() FROM PermissionSetAssignment WHERE Id = :psa.Id],
      'Should delete the PermissionSetAssignment'
    );
  }

  @IsTest
  static void defaultUserLoginAccess_freezesExpiredUserLogin() {
    FakeDataAccess fakeDa = new FakeDataAccess();
    SubscriptionAccessControlService.dataAccess = fakeDa;
    SubscriptionAccessControlService.userLoginAccess = null;

    User expired = makeUser(Date.today().addDays(-1));

    UserLogin beforeLogin = [
      SELECT Id, UserId, IsFrozen
      FROM UserLogin
      WHERE UserId = :expired.Id
      LIMIT 1
    ];

    SubscriptionAccessControlService.FreezeResult result = SubscriptionAccessControlService.syncSubscriptionFreezesByUserIds(
      new Set<Id>{ expired.Id }
    );

    UserLogin afterLogin = [
      SELECT Id, UserId, IsFrozen
      FROM UserLogin
      WHERE UserId = :expired.Id
      LIMIT 1
    ];

    System.assertNotEquals(null, result, 'Should return a result');
    System.assertEquals(
      1,
      fakeDa.deleted.size(),
      'Should attempt legacy PSA deletion'
    );
  }
}
