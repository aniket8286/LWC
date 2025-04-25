List<Database.UpsertResult> results = Database.upsert(accountsToUpsert, Account.Id, false);

List<FinnoneSync__c> toUpdate = new List<FinnoneSync__c>();
List<String> failedRecordInfo = new List<String>(); // To store info about failed records

for (Integer i = 0; i < results.size(); i++) {
    if (results[i].isSuccess()) {
        result.put('mappedCount', result.get('mappedCount') + 1);
        if (String.isBlank(finnoneSyncRecords[i].SF_Account_Id__c)) {
            finnoneSyncRecords[i].SF_Account_Id__c = results[i].getId();
            toUpdate.add(finnoneSyncRecords[i]);
        }
    } else {
        // Collect detailed info about failing records
        String errorInfo = 'Failed record ID: ' + finnoneSyncRecords[i].Id + 
                          ', City_Id__c: ' + finnoneSyncRecords[i].City_Id__c + 
                          ', Name: ' + finnoneSyncRecords[i].Name;
        
        for (Database.Error err : results[i].getErrors()) {
            errorInfo += ', Error: ' + err.getStatusCode() + ' - ' + err.getMessage() + 
                         ', Fields: ' + String.join(err.getFields(), ',');
        }
        
        failedRecordInfo.add(errorInfo);
    }
}

// Log all failed records at once for easier review
if (!failedRecordInfo.isEmpty()) {
    System.debug('Found ' + failedRecordInfo.size() + ' failed records:');
    for (String info : failedRecordInfo) {
        System.debug(info);
    }
}
