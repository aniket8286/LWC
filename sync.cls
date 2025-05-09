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
            'FirstName__c' => 'FirstName',
            'Email__c' => 'Email',
            'Phone__c' => 'Phone'
            // Add more field mappings as needed
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
            'FirstName__c' => 'FirstName',
            'Email__c' => 'Email',
            'Phone__c' => 'Phone'
            // Add more field mappings as needed
        };
        
        // Create a map to store existing contacts by their Id
        Map<Id, Contact> existingContactsById = new Map<Id, Contact>();
        Set<Id> existingContactIds = new Set<Id>();
        
        // Set to collect Account IDs for looking up existing contacts
        Set<Id> accountIds = new Set<Id>();
        
        // Collect all existing contact IDs and account IDs from the FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Contact_Id__c)) {
                existingContactIds.add(fs.SF_Contact_Id__c);
            }
            if (String.isNotBlank(fs.SF_Account_Id__c)) {
                accountIds.add(fs.SF_Account_Id__c);
            }
        }
        
        // Query for existing contacts by ID
        if (!existingContactIds.isEmpty()) {
            existingContactsById = new Map<Id, Contact>(
                [SELECT Id, LastName, FirstName, Email, Phone, AccountId 
                 FROM Contact WHERE Id IN :existingContactIds]
            );
        }

        // Map to store contacts by Account ID
        Map<Id, List<Contact>> contactsByAccountId = new Map<Id, List<Contact>>();
        
        // Query for existing contacts by Account ID
        if (!accountIds.isEmpty()) {
            for (Contact con : [SELECT Id, LastName, FirstName, Email, Phone, AccountId 
                              FROM Contact WHERE AccountId IN :accountIds]) {
                if (!contactsByAccountId.containsKey(con.AccountId)) {
                    contactsByAccountId.put(con.AccountId, new List<Contact>());
                }
                contactsByAccountId.get(con.AccountId).add(con);
                
                // Also add to the ID map if not already there
                if (!existingContactsById.containsKey(con.Id)) {
                    existingContactsById.put(con.Id, con);
                }
            }
        }

        System.Debug('Existing contacts by ID count: ' + existingContactsById.size());
        System.Debug('Accounts with existing contacts: ' + contactsByAccountId.size());
        
        // Lists for update and insert operations
        List<Contact> contactsToUpdate = new List<Contact>();
        List<Contact> contactsToInsert = new List<Contact>();
        
        // Maps to track which finnoneSync record corresponds to which Contact
        Map<Id, FinnoneSync__c> contactToFinnoneMap = new Map<Id, FinnoneSync__c>();
        Map<Integer, FinnoneSync__c> newContactIndexToFinnoneMap = new Map<Integer, FinnoneSync__c>();
        
        // Process each FinnoneSync record
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            Contact contactToProcess;
            Boolean isUpdate = false;
            
            // Case 1: Contact ID is provided and exists
            if (String.isNotBlank(fs.SF_Contact_Id__c) && existingContactsById.containsKey(fs.SF_Contact_Id__c)) {
                contactToProcess = existingContactsById.get(fs.SF_Contact_Id__c);
                isUpdate = true;
            } 
            // Case 2: No Contact ID but Account ID exists and has contacts
            else if (String.isNotBlank(fs.SF_Account_Id__c) && contactsByAccountId.containsKey(fs.SF_Account_Id__c) 
                    && !contactsByAccountId.get(fs.SF_Account_Id__c).isEmpty()) {
                // Choose the first contact associated with this account
                // You may want to implement more sophisticated matching logic here
                contactToProcess = contactsByAccountId.get(fs.SF_Account_Id__c)[0];
                isUpdate = true;
            }
            // Case 3: New contact needs to be created
            else {
                contactToProcess = new Contact();
                isUpdate = false;
            }
            
            // Update contact fields from FinnoneSync record
            for (String finnoneField : finnoneToContactFieldMap.keySet()) {
                String contactField = finnoneToContactFieldMap.get(finnoneField);
                Object value = fs.get(finnoneField);
                if (value != null) contactToProcess.put(contactField, value);
            }
            
            // Always set AccountId if present
            if (String.isNotBlank(fs.SF_Account_Id__c)) {
                contactToProcess.AccountId = (Id)fs.SF_Account_Id__c;
            }
            
            if (isUpdate) {
                contactsToUpdate.add(contactToProcess);
                contactToFinnoneMap.put(contactToProcess.Id, fs);
            } else {
                contactsToInsert.add(contactToProcess);
                newContactIndexToFinnoneMap.put(contactsToInsert.size() - 1, fs);
            }
        }
        
        System.Debug('Contacts to update: ' + contactsToUpdate.size());
        System.Debug('Contacts to insert: ' + contactsToInsert.size());
        
        // Get the previous processing stats if needed
        Integer previousRecordsProcessed = 0;
        try {
            FinnoneSync__c temp = [SELECT RecordsProcessed__c FROM FinnoneSync__c 
                                  WHERE JobType__c = 'CSV Processing' AND Status__c = 'Completed' 
                                  ORDER BY CreatedDate DESC LIMIT 1];
            previousRecordsProcessed = (Integer)temp.RecordsProcessed__c;
            System.debug('Previous records processed: ' + previousRecordsProcessed);
        } catch (Exception e) {
            System.debug('No previous processing stats found: ' + e.getMessage());
        }
        
        // Update record counts
        recordsInserted += contactsToInsert.size();
        recordsUpdated += contactsToUpdate.size();
        
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
                    fs.SF_Contact_Id__c = con.Id; // Ensure the Contact ID is set
                    fs.SF_BatchId__c = batchId;
                    finnoneSyncToUpdate.add(fs);
                } else {
                    recordsFailed++;
                    // Capture error details
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
                    // Capture error details
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
        
        recordsProcessed += finnoneSyncRecords.size();
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
                statusRecord.RecordsProcessed__c = this.recordsProcessed;
                statusRecord.RecordsInserted__c = this.recordsInserted;
                statusRecord.RecordsSucceeded__c = this.recordsSucceeded;
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