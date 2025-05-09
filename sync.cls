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
        
        // Create a map to store existing accounts by their Id
        Map<Id, Account> existingAccountsMap = new Map<Id, Account>();
        Set<Id> existingIds = new Set<Id>();
        
        // Collect all existing account IDs from the FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Account_Id__c)) {
                existingIds.add(fs.SF_Account_Id__c);
            }
        }
        
        // Query for existing accounts
        if (!existingIds.isEmpty()) {
            existingAccountsMap = new Map<Id, Account>(
                [SELECT Id, Name, AgencyCode__c, AccountNumber, BillingCity, Partner_Type__c 
                 FROM Account WHERE Id IN :existingIds]
            );
        }

        System.Debug('existingIds.size() ===========>' + existingIds.size());
        
        // Lists for update and insert operations
        List<Account> accountsToUpdate = new List<Account>();
        List<Account> accountsToInsert = new List<Account>();
        
        // Maps to track which finnoneSync record corresponds to which Account
        Map<Id, FinnoneSync__c> accountToFinnoneMap = new Map<Id, FinnoneSync__c>();
        Map<Integer, FinnoneSync__c> newAccountIndexToFinnoneMap = new Map<Integer, FinnoneSync__c>();
        
        // Process each FinnoneSync record
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Account_Id__c) && existingAccountsMap.containsKey(fs.SF_Account_Id__c)) {
                // Update existing account
                Account acc = existingAccountsMap.get(fs.SF_Account_Id__c);
                
                // Update account fields
                for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                    String accountField = finnoneToAccountFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) acc.put(accountField, value);
                }
                
                // Set partner type
                acc.Partner_Type__c = 'Dealer';
                
                // Add to update list
                accountsToUpdate.add(acc);
                accountToFinnoneMap.put(acc.Id, fs);
                
                System.Debug('accountsToUpdate =========>' + accountsToUpdate.size());
            } else {
                // Create new account
                Account acc = new Account();
                
                // Set account fields
                for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                    String accountField = finnoneToAccountFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) acc.put(accountField, value);
                }
                
                // Set record type and partner type
                acc.Partner_Type__c = 'Dealer';
                // if (recordNameId != null) {
                //     acc.RecordTypeId = recordNameId;
                // }
                
                // Add to insert list
                accountsToInsert.add(acc);
                newAccountIndexToFinnoneMap.put(accountsToInsert.size() - 1, fs);
                
            }
        }
        FinnoneSync__c temp = [Select RecordsProcessed__c from FinnoneSync__c where JobType__c = 'CSV Processing' AND Status__c = 'Completed' ORDER BY CreatedDate DESC LIMIT 1];
        System.debug('temp ==========>' + temp);
        System.debug('accountsToUpdate ==========>' + accountsToUpdate.size());
        
        // Update and insert accounts)
        
        recordsInserted += accountsToInsert.size();
        recordsUpdated = (Integer)temp.RecordsProcessed__c - recordsInserted;    
    
        
        // Process updates
        List<FinnoneSync__c> finnoneSyncToUpdate = new List<FinnoneSync__c>();
        String batchId = BC.getJobId();
        
        if (!accountsToUpdate.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(accountsToUpdate, false);
            
            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult result = updateResults[i];
                Account acc = accountsToUpdate[i];
                FinnoneSync__c fs = accountToFinnoneMap.get(acc.Id);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    // recordsUpdated++;
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    
                }
            }
        }
        
        // Process inserts
        if (!accountsToInsert.isEmpty()) {
            List<Database.SaveResult> insertResults = Database.insert(accountsToInsert, false);
            
            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult result = insertResults[i];
                FinnoneSync__c fs = newAccountIndexToFinnoneMap.get(i);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    // recordsInserted++;
                    fs.SF_Account_Id__c = insertResults[i].getId();
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Handle error if needed
                }
            }
        }
        
        // Update FinnoneSync records with new Account IDs and batch ID
        if (!finnoneSyncToUpdate.isEmpty()) {
            update finnoneSyncToUpdate;
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
            
            List<FinnoneSync__c> statusRecords = [   
                SELECT Id 
                FROM FinnoneSync__c 
                WHERE BatchId__c = :BC.getJobId() 
                LIMIT 1
            ];
            
            if (!statusRecords.isEmpty()) {
                FinnoneSync__c statusRecord = statusRecords[0];
                // statusRecord.BatchId__c = BC.getJobId() ;
                statusRecord.Status__c = 'Account Completed';
                statusRecord.RecordsProcessed__c = this.recordsInserted + this.recordsUpdated;
                statusRecord.RecordsInserted__c = this.recordsInserted;
                statusRecord.RecordsSucceeded__c =(this.recordsInserted + this.recordsUpdated) - this.recordsFailed;
                statusRecord.RecordsUpdated__c = this.recordsUpdated;
                statusRecord.RecordsFailed__c = this.recordsFailed;
                statusRecord.EndTime__c = Datetime.now();
                statusRecord.JobMessage__c = this.jobMessage;
                
                update statusRecord;
            }
            
            // Uncomment if you want to chain the Contact batch after this
            // Database.executeBatch(new MapToContactBatch(), 200);
            
        } catch (Exception e) {
            System.debug('Error updating batch job status: ' + e.getMessage());
        }
    }
}
