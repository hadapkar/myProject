String jobName = 'Subscription Access Control Daily';
List<CronTrigger> existing = [
    SELECT Id, CronJobDetail.Name, State
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
    AND State != 'DELETED'
];

if (existing.isEmpty()) {
    System.schedule(jobName, '0 0 2 * * ?', new SubscriptionAccessControlScheduler());
    System.debug('Scheduled: ' + jobName);
} else {
    System.debug('Already scheduled: ' + jobName + ' => ' + existing[0].Id);
}

