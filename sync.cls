public class MapToBankBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Map<String, Integer> result;
    private Integer recordsProcessed = 0;
    private Integer recordsInserted = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsSucceeded = 0;
    private Integer recordsFailed = 0;
    private String jobMessage = '';
    
    public MapToBankBatch() {
        this.result = new Map<String, Integer>{
            'mappedCount' => 0, 
            'insertedCount' => 0, 
            'updatedCount' => 0
        };
    }
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        Map<String, String> finnoneToBankFieldMap = new Map<String, String>{
            'AgencyCode__c' => 'AgencyCode__c',
            'Cash_Bank_Account__c' => 'Cash_Bank_Account__c',
            'Cash_Bank_Acc_Desc__c' => 'Cash_Bank_Acc_Desc__c',
            'Payment_Mode__c' => 'Payment_Mode__c',
            'Name' => 'Name',
            'Bank_Ac_No__c' => 'Bank_Ac_No__c',
            'IFSC_Code__c' => 'IFSC_Code__c',
            'City_ID__c' => 'City_ID__c',
            'FT_Mode__c' => 'FT_Mode__c',
            'Disburse_To__c' => 'Disburse_To__c',
            'MICRCode__c' => 'MICRCode__c'
        };
        
        String query = 'SELECT Id, SF_Bank_Id__c, Composite_Key_bank__c';
        for (String f : finnoneToBankFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c LIMIT 10000';
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<FinnoneSync__c> finnoneSyncRecords = (List<FinnoneSync__c>)scope;
        
        Map<String, String> finnoneToBankFieldMap = new Map<String, String>{
            'AgencyCode__c' => 'AgencyCode__c',
            'Cash_Bank_Account__c' => 'Cash_Bank_Account__c',
            'Cash_Bank_Acc_Desc__c' => 'Cash_Bank_Acc_Desc__c',
            'Payment_Mode__c' => 'Payment_Mode__c',
            'Name' => 'Name',
            'Bank_Ac_No__c' => 'Bank_Ac_No__c',
            'IFSC_Code__c' => 'IFSC_Code__c',
            'City_ID__c' => 'City_ID__c',
            'FT_Mode__c' => 'FT_Mode__c',
            'Disburse_To__c' => 'Disburse_To__c',
            'MICRCode__c' => 'MICRCode__c'
        };
        
        // Collect IDs of bank records referenced by FinnoneSync
        Set<Id> bankIdsToFetch = new Set<Id>();
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Bank_Id__c)) {
                bankIdsToFetch.add((Id)fs.SF_Bank_Id__c);
            }
        }
        
        // Query existing bank records by ID
        Map<Id, BankMstr__c> existingBanksById = new Map<Id, BankMstr__c>();
        if (!bankIdsToFetch.isEmpty()) {
            existingBanksById = new Map<Id, BankMstr__c>([
                SELECT Id, AgencyCode__c, Cash_Bank_Account__c, MICRCode__c, 
                    IFSC_Code__c, City_ID__c, Bank_Ac_No__c
                FROM BankMstr__c
                WHERE Id IN :bankIdsToFetch
            ]);
        }
        
        List<BankMstr__c> banksToUpsert = new List<BankMstr__c>();
        
        // Process FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            BankMstr__c bank;
            
            if (String.isNotBlank(fs.SF_Bank_Id__c) && existingBanksById.containsKey(fs.SF_Bank_Id__c)) {
                bank = existingBanksById.get(fs.SF_Bank_Id__c);
                recordsUpdated++;
                // result.put('updatedCount', result.get('updatedCount') + 1);
            } else {
                bank = new BankMstr__c();
                // result.put('insertedCount', result.get('insertedCount') + 1);
                recordsInserted++;
            }
            
            // Map fields from FinnoneSync to BankMstr
            for (String finnoneField : finnoneToBankFieldMap.keySet()) {
                String bankField = finnoneToBankFieldMap.get(finnoneField);
                Object value = fs.get(finnoneField);
                if (value != null) bank.put(bankField, value);
            }
            
            banksToUpsert.add(bank);
        }
        
        // Perform DML operations
        if (!banksToUpsert.isEmpty()) {
            List<Database.UpsertResult> bankResults = Database.upsert(banksToUpsert, false);
            
            // Update FinnoneSync records with new Bank IDs
            List<FinnoneSync__c> finnoneSyncToUpdate = new List<FinnoneSync__c>();
            
            for (Integer i = 0; i < bankResults.size(); i++) {
                if (bankResults[i].isSuccess()) {
                    // result.put('mappedCount', result.get('mappedCount') + 1);
                    
                    FinnoneSync__c fs = finnoneSyncRecords[i];
                    if (String.isBlank(fs.SF_Bank_Id__c)) {
                        fs.SF_Bank_Id__c = bankResults[i].getId();
                        finnoneSyncToUpdate.add(fs);
                    }
                }
            }
            
            if (!finnoneSyncToUpdate.isEmpty()) {
                update finnoneSyncToUpdate;
            }
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
                statusRecord.Status__c = 'Bank Completed';
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
