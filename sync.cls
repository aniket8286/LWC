public class MapToBankBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Map<String, Integer> result;
    
    private Integer recordsProcessed = 0;
    private Integer recordsInserted = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsSucceeded = 0;
    private Integer recordsFailed = 0;
    private String jobMessage = '';
    
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
        
        String query = 'SELECT Id, SF_Bank_Id__c, SF_BatchId__c, Composite_Key_bank__c';
        for (String f : finnoneToBankFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c';
        
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
        
        // Create a map to store existing banks by their Id
        Map<Id, BankMstr__c> existingBanksMap = new Map<Id, BankMstr__c>();
        Set<Id> existingIds = new Set<Id>();
        
        // Collect all existing bank IDs from the FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Bank_Id__c)) {
                existingIds.add((Id)fs.SF_Bank_Id__c);
            }
        }
        
        // Query for existing banks
        if (!existingIds.isEmpty()) {
            existingBanksMap = new Map<Id, BankMstr__c>(
                [SELECT Id, AgencyCode__c, Cash_Bank_Account__c, Cash_Bank_Acc_Desc__c, 
                 Payment_Mode__c, Name, Bank_Ac_No__c, IFSC_Code__c, City_ID__c, 
                 FT_Mode__c, Disburse_To__c, MICRCode__c
                 FROM BankMstr__c WHERE Id IN :existingIds]
            );
        }

        System.Debug('existingIds.size() ===========>' + existingIds.size());
        
        // Lists for update and insert operations
        List<BankMstr__c> banksToUpdate = new List<BankMstr__c>();
        List<BankMstr__c> banksToInsert = new List<BankMstr__c>();
        
        // Maps to track which finnoneSync record corresponds to which Bank
        Map<Id, FinnoneSync__c> bankToFinnoneMap = new Map<Id, FinnoneSync__c>();
        Map<Integer, FinnoneSync__c> newBankIndexToFinnoneMap = new Map<Integer, FinnoneSync__c>();
        
        // Process each FinnoneSync record
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Bank_Id__c) && existingBanksMap.containsKey(fs.SF_Bank_Id__c)) {
                // Update existing bank
                BankMstr__c bank = existingBanksMap.get(fs.SF_Bank_Id__c);
                
                // Update bank fields
                for (String finnoneField : finnoneToBankFieldMap.keySet()) {
                    String bankField = finnoneToBankFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) bank.put(bankField, value);
                }
                
                // Add to update list
                banksToUpdate.add(bank);
                bankToFinnoneMap.put(bank.Id, fs);
                
                System.Debug('banksToUpdate =========>' + banksToUpdate.size());
            } else {
                // Create new bank
                BankMstr__c bank = new BankMstr__c();
                
                // Set bank fields
                for (String finnoneField : finnoneToBankFieldMap.keySet()) {
                    String bankField = finnoneToBankFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) bank.put(bankField, value);
                }
                
                // Add to insert list
                banksToInsert.add(bank);
                newBankIndexToFinnoneMap.put(banksToInsert.size() - 1, fs);
            }
        }
        
        FinnoneSync__c temp = [Select RecordsProcessed__c from FinnoneSync__c where JobType__c = 'CSV Processing' AND Status__c = 'Completed' ORDER BY CreatedDate DESC LIMIT 1];
        System.debug('temp ==========>' + temp);
        System.debug('banksToUpdate ==========>' + banksToUpdate.size());
        
        // Update record counts
        recordsInserted += banksToInsert.size();
        recordsUpdated = (Integer)temp.RecordsProcessed__c - recordsInserted;
        
        // Process updates
        List<FinnoneSync__c> finnoneSyncToUpdate = new List<FinnoneSync__c>();
        String batchId = BC.getJobId();
        
        if (!banksToUpdate.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(banksToUpdate, false);
            
            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult result = updateResults[i];
                BankMstr__c bank = banksToUpdate[i];
                FinnoneSync__c fs = bankToFinnoneMap.get(bank.Id);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Optionally capture error details
                    for (Database.Error err : result.getErrors()) {
                        jobMessage += 'Update Error for Bank ' + bank.Id + ': ' + err.getMessage() + '\n';
                    }
                }
            }
        }
        
        // Process inserts
        if (!banksToInsert.isEmpty()) {
            List<Database.SaveResult> insertResults = Database.insert(banksToInsert, false);
            
            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult result = insertResults[i];
                FinnoneSync__c fs = newBankIndexToFinnoneMap.get(i);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    fs.SF_Bank_Id__c = insertResults[i].getId();
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Optionally capture error details
                    for (Database.Error err : result.getErrors()) {
                        jobMessage += 'Insert Error for new Bank: ' + err.getMessage() + '\n';
                    }
                }
            }
        }
        
        // Update FinnoneSync records with new Bank IDs and batch ID
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
            
            List<BatchJobStatus__c> statusRecords = [
                SELECT Id 
                FROM BatchJobStatus__c 
                WHERE BatchId__c = :BC.getJobId() 
                LIMIT 1
            ];
            
            if (!statusRecords.isEmpty()) {
                BatchJobStatus__c statusRecord = statusRecords[0];
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
            
        } catch (Exception e) {
            System.debug('Error updating batch job status: ' + e.getMessage());
        }
    }
}