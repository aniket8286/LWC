public class MapToContactBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Map<String, Integer> result;
    
    private Integer recordsProcessed = 0;
    private Integer recordsInserted = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsSucceeded = 0;
    private Integer recordsFailed = 0;
    private String jobMessage = '';
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        Map<String, String> finnoneToContactFieldMap = new Map<String, String>{
            'Name' => 'LastName',
            // Add more field mappings as needed
            'FirstName__c' => 'FirstName',
            'Email__c' => 'Email',
            'Phone__c' => 'Phone'
        };
        
        String query = 'SELECT Id, SF_Account_Id__c, SF_Contact_Id__c, SF_BatchId__c';
        for (String f : finnoneToContactFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c';
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<FinnoneSync__c> finnoneSyncRecords = (List<FinnoneSync__c>)scope;
        
        Map<String, String> finnoneToContactFieldMap = new Map<String, String>{
            'Name' => 'LastName',
            // Add more field mappings as needed
            'FirstName__c' => 'FirstName',
            'Email__c' => 'Email',
            'Phone__c' => 'Phone'
        };
        
        // Create a map to store existing contacts by their Id
        Map<Id, Contact> existingContactsMap = new Map<Id, Contact>();
        Set<Id> existingIds = new Set<Id>();
        
        // Collect all existing contact IDs from the FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Contact_Id__c)) {
                existingIds.add(fs.SF_Contact_Id__c);
            }
        }
        
        // Query for existing contacts
        if (!existingIds.isEmpty()) {
            existingContactsMap = new Map<Id, Contact>(
                [SELECT Id, LastName, FirstName, Email, Phone, AccountId 
                 FROM Contact WHERE Id IN :existingIds]
            );
        }

        System.Debug('existingIds.size() ===========>' + existingIds.size());
        
        // Lists for update and insert operations
        List<Contact> contactsToUpdate = new List<Contact>();
        List<Contact> contactsToInsert = new List<Contact>();
        
        // Maps to track which finnoneSync record corresponds to which Contact
        Map<Id, FinnoneSync__c> contactToFinnoneMap = new Map<Id, FinnoneSync__c>();
        Map<Integer, FinnoneSync__c> newContactIndexToFinnoneMap = new Map<Integer, FinnoneSync__c>();
        
        // Process each FinnoneSync record
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Contact_Id__c) && existingContactsMap.containsKey(fs.SF_Contact_Id__c)) {
                // Update existing contact
                Contact con = existingContactsMap.get(fs.SF_Contact_Id__c);
                
                // Update contact fields
                for (String finnoneField : finnoneToContactFieldMap.keySet()) {
                    String contactField = finnoneToContactFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) con.put(contactField, value);
                }
                
                // Always set AccountId if present
                if (String.isNotBlank(fs.SF_Account_Id__c)) {
                    con.AccountId = (Id)fs.SF_Account_Id__c;
                }
                
                // Add to update list
                contactsToUpdate.add(con);
                contactToFinnoneMap.put(con.Id, fs);
                
                System.Debug('contactsToUpdate =========>' + contactsToUpdate.size());
            } else {
                // Create new contact
                Contact con = new Contact();
                
                // Set contact fields
                for (String finnoneField : finnoneToContactFieldMap.keySet()) {
                    String contactField = finnoneToContactFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) con.put(contactField, value);
                }
                
                // Always set AccountId if present
                if (String.isNotBlank(fs.SF_Account_Id__c)) {
                    con.AccountId = (Id)fs.SF_Account_Id__c;
                }
                
                // Add to insert list
                contactsToInsert.add(con);
                newContactIndexToFinnoneMap.put(contactsToInsert.size() - 1, fs);
            }
        }
        
        FinnoneSync__c temp = [Select RecordsProcessed__c from FinnoneSync__c where JobType__c = 'CSV Processing' AND Status__c = 'Completed' ORDER BY CreatedDate DESC LIMIT 1];
        System.debug('temp ==========>' + temp);
        System.debug('contactsToUpdate ==========>' + contactsToUpdate.size());
        
        // Update record counts
        recordsInserted += contactsToInsert.size();
        recordsUpdated = (Integer)temp.RecordsProcessed__c - recordsInserted;
        
        // Process updates
        List<FinnoneSync__c> finnoneSyncToUpdate = new List<FinnoneSync__c>();
        String batchId = BC.getJobId();
        
        if (!contactsToUpdate.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(contactsToUpdate, false);
            
            for (Integer i = 0; i < updateResults.size(); i++) {
                Database.SaveResult result = updateResults[i];
                Contact con = contactsToUpdate[i];
                FinnoneSync__c fs = contactToFinnoneMap.get(con.Id);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Optionally capture error details
                    for (Database.Error err : result.getErrors()) {
                        jobMessage += 'Update Error for Contact ' + con.Id + ': ' + err.getMessage() + '\n';
                    }
                }
            }
        }
        
        // Process inserts
        if (!contactsToInsert.isEmpty()) {
            List<Database.SaveResult> insertResults = Database.insert(contactsToInsert, false);
            
            for (Integer i = 0; i < insertResults.size(); i++) {
                Database.SaveResult result = insertResults[i];
                FinnoneSync__c fs = newContactIndexToFinnoneMap.get(i);
                
                if (result.isSuccess()) {
                    recordsSucceeded++;
                    fs.SF_Contact_Id__c = insertResults[i].getId();
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Optionally capture error details
                    for (Database.Error err : result.getErrors()) {
                        jobMessage += 'Insert Error for new Contact: ' + err.getMessage() + '\n';
                    }
                }
            }
        }
        
        // Update FinnoneSync records with new Contact IDs and batch ID
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
                statusRecord.Status__c = 'Contact Completed';
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