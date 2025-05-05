// MapToAccountBatch.cls
public class MapToAccountBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Map<String, Integer> result;
    private static String recordNameId = [Select id from RecordType where Name = 'Business Account' LIMIT 1].Id;
    
    private Integer recordsProcessed = 0;
    private Integer recordsInserted = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsSucceeded = 0;
    private Integer recordsFailed = 0;
    private String jobMessage = '';
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        Map<String, String> finnoneToAccountFieldMap = new Map<String, String>{
            'Name' => 'Name',
            'AgencyCode__c' => 'AgencyCode__c',
            'Bank_Ac_No__c' => 'AccountNumber',
            'City_Id__c' => 'BillingCity'
        };
        
        String query = 'SELECT Id, SF_Account_Id__c, SF_Contact_Id__c, SF_BatchId__c ';
        for (String f : finnoneToAccountFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c ';
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<FinnoneSync__c> finnoneSyncRecords = (List<FinnoneSync__c>)scope;
        
        Map<String, String> finnoneToAccountFieldMap = new Map<String, String>{
            'Name' => 'Name',
            'AgencyCode__c' => 'AgencyCode__c',
            'Bank_Ac_No__c' => 'AccountNumber',
             'City_Id__c' => 'BillingCity'
        };
        
        Map<Id, Account> existingAccountsMap = new Map<Id, Account>();
        Set<Id> existingIds = new Set<Id>();
        
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Account_Id__c)) existingIds.add((String)fs.SF_Account_Id__c);
        }
        
        if (!existingIds.isEmpty()) {
            existingAccountsMap = new Map<Id, Account>(
                [SELECT Id, Name FROM Account WHERE Id IN :existingIds]
            );
        }
        
        List<Account> accountsToUpsert = new List<Account>();
        
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            Account acc;
            if (String.isNotBlank(fs.SF_Account_Id__c) && existingAccountsMap.containsKey(fs.SF_Account_Id__c)) {
                // result.put('updatedCount', result.get('updatedCount') + 1);
                recordsUpdated++;
                acc = existingAccountsMap.get(fs.SF_Account_Id__c);
            } else {
                // result.put('insertedCount', result.get('insertedCount') + 1);
                recordsInserted++;
                acc = new Account();
            }
            
            for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                String accountField = finnoneToAccountFieldMap.get(finnoneField);
                Object value = fs.get(finnoneField);
                if (value != null) acc.put(accountField, value);
            }
            
            // Set record type and partner type
            acc.put('Partner_Type__c', 'Dealer');
            // if (recordNameId != null) {
            //     acc.RecordTypeId = recordNameId;
            // }
            
            accountsToUpsert.add(acc);
        }
        
        if (!accountsToUpsert.isEmpty()) {
            List<Database.UpsertResult> results = Database.upsert(accountsToUpsert, Account.Id, false);
            
            List<FinnoneSync__c> toUpdate = new List<FinnoneSync__c>();
            String batchId = BC.getJobId();
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    finnoneSyncRecords[i].SF_BatchId__c = batchId;
                   
                    if (String.isBlank(finnoneSyncRecords[i].SF_Account_Id__c)) {
                        finnoneSyncRecords[i].SF_Account_Id__c = results[i].getId();
                        // finnoneSyncRecords[i].SF_BatchId__c = batchId;
                        System.debug('finnoneSyncRecords[i].SF_BatchId__c ==========> ' + finnoneSyncRecords[i].SF_BatchId__c  );
                        System.debug('batchId -===============> ' + batchId);
                        toUpdate.add(finnoneSyncRecords[i]);
                    }

                }
            }
            
            if (!toUpdate.isEmpty()) update toUpdate;
        }
    }
    
    public void finish(Database.BatchableContext BC) {
        // Update the batch job status record
        try {
            // Query for AsyncApexJob to get total job items
            AsyncApexJob job = [
                SELECT Id, TotalJobItems, NumberOfErrors
                FROM AsyncApexJob 
                WHERE Id = :BC.getJobId()
            ];
            
            
            List<BatchJobStatus__c> statusRecords = [   
                SELECT Id 
                FROM BatchJobStatus__c 
                WHERE BatchId__c = :BC.getJobId() 
                LIMIT 1
            ];

            
            // BatchJobStatus__c statusRecord = new BatchJobStatus__c();
            
            if (!statusRecords.isEmpty()) {
                BatchJobStatus__c statusRecord = statusRecords[0];
                // statusRecord.BatchId__c = BC.getJobId() ;
                statusRecord.Status__c = 'Account Completed';
                statusRecord.RecordsProcessed__c = this.recordsInserted + this.recordsUpdated;
                statusRecord.RecordsInserted__c = this.recordsInserted;
                statusRecord.RecordsSucceeded__c = (this.recordsInserted + this.recordsUpdated) - this.recordsFailed;
                statusRecord.RecordsUpdated__c = this.recordsUpdated;
                statusRecord.RecordsFailed__c = this.recordsFailed;
                statusRecord.EndTime__c = Datetime.now();
                statusRecord.JobMessage__c = this.jobMessage;
                
                update statusRecord;
            }

            // statusRecord.BatchId__c = BC.getJobId() ;
            // statusRecord.Status__c = 'Account Completed';
            // statusRecord.RecordsProcessed__c = this.recordsInserted + this.recordsUpdated;
            // statusRecord.RecordsInserted__c = this.recordsInserted;
            // statusRecord.RecordsSucceeded__c = (this.recordsInserted + this.recordsUpdated) - this.recordsFailed;
            // statusRecord.RecordsUpdated__c = this.recordsUpdated;
            // statusRecord.RecordsFailed__c = this.recordsFailed;
            // statusRecord.EndTime__c = Datetime.now();
            // statusRecord.JobMessage__c = this.jobMessage;
            
            // insert statusRecord;
            
            // Database.executeBatch(new MapToContactBatch(), 200);
            
        } catch (Exception e) {
            System.debug('Error updating batch job status: ' + e.getMessage());
        }

    }
}
