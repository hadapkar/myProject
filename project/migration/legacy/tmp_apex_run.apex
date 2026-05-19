public class TmpPayload {
    @AuraEnabled public Id recordId;
    @AuraEnabled public Decimal score;
    @AuraEnabled public Integer predefinedWheelNumber;
    @AuraEnabled public String last10Results;
    @AuraEnabled public Decimal totalBetAmount;
    @AuraEnabled public Decimal winnerAmount;
    @AuraEnabled public String betsJson;
    @AuraEnabled public String lastUpdatedFrom;
    @AuraEnabled public Datetime lastRoundAt;
    @AuraEnabled public Datetime lastModifiedDate;
}
FunTargetStateController.StateDTO p = new FunTargetStateController.StateDTO();
p.betsJson = '{"2":5,"7":10}';
p.totalBetAmount = 15;
p.winnerAmount = 0;
p.last10Results = '1,2,3,4,5,6,7,8,9,0';
p.lastUpdatedFrom = 'Site';
FunTargetStateController.StateDTO s = FunTargetStateController.saveState(p, null);
System.debug('@@RESULT bets=' + s.betsJson + ' total=' + s.totalBetAmount + ' score=' + s.score + ' id=' + s.recordId);
