String jobName = 'Subscription Access Control Daily';
List<CronTrigger> triggers = [
    SELECT Id, CronJobDetail.Name, State
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
    AND State != 'DELETED'
];

for (CronTrigger ct : triggers) {
    System.abortJob(ct.Id);
    System.debug('Aborted: ' + ct.Id + ' (' + ct.State + ')');
}

if (triggers.isEmpty()) {
    System.debug('No scheduled jobs found for: ' + jobName);
}

