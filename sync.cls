// MapToContactBatch.cls
public class MapToContactBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Map<String, Integer> result;

    private Integer recordsProcessed = 0;
    private Integer recordsInserted = 0;
    private Integer recordsUpdated = 0;
    private Integer recordsSucceeded = 0;
    private Integer recordsFailed = 0;
    private String jobMessage = '';
    
    public MapToContactBatch() {
        this.result = new Map<String, Integer>{
            'mappedCount' => 0, 
            'insertedCount' => 0, 
            'updatedCount' => 0
        };
    }
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        Map<String, String> finnoneToContactFieldMap = new Map<String, String>{
            'Name' => 'LastName'
        };
        
        String query = 'SELECT Id, SF_Account_Id__c, SF_Contact_Id__c';
        for (String f : finnoneToContactFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c LIMIT 10000';
        
        return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<FinnoneSync__c> finnoneSyncRecords = (List<FinnoneSync__c>)scope;
        
        Map<String, String> finnoneToContactFieldMap = new Map<String, String>{
            'Name' => 'LastName'
        };
        
        Map<Id, Contact> existingContactsMap = new Map<Id, Contact>();
        Set<Id> existingIds = new Set<Id>();
        
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            if (String.isNotBlank(fs.SF_Contact_Id__c)) existingIds.add((Id)fs.SF_Contact_Id__c);
        }
        
        if (!existingIds.isEmpty()) {
            existingContactsMap = new Map<Id, Contact>(
                [SELECT Id, LastName, AccountId FROM Contact WHERE Id IN :existingIds]
            );
        }
        
        List<Contact> contactsToUpsert = new List<Contact>();
        
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            Contact con;
            if (String.isNotBlank(fs.SF_Contact_Id__c) && existingContactsMap.containsKey(fs.SF_Contact_Id__c)) {
                // result.put('updatedCount', result.get('updatedCount') + 1);
                recordsUpdated++;
                con = existingContactsMap.get(fs.SF_Contact_Id__c);
            } else {
                // result.put('insertedCount', result.get('insertedCount') + 1);
                recordsInserted++;
                con = new Contact();
            }
            
            for (String finnoneField : finnoneToContactFieldMap.keySet()) {
                String contactField = finnoneToContactFieldMap.get(finnoneField);
                Object value = fs.get(finnoneField);
                if (value != null) con.put(contactField, value);
            }
            
            // Always set AccountId if present
            if (String.isNotBlank(fs.SF_Account_Id__c)) {
                con.AccountId = (Id)fs.SF_Account_Id__c;
            }
            
            contactsToUpsert.add(con);
        }
        
        if (!contactsToUpsert.isEmpty()) {
            List<Database.UpsertResult> results = Database.upsert(contactsToUpsert, Contact.Id, false);
            
            List<FinnoneSync__c> toUpdate = new List<FinnoneSync__c>();
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    // result.put('mappedCount', result.get('mappedCount') + 1);
                    if (String.isBlank(finnoneSyncRecords[i].SF_Contact_Id__c)) {
                        finnoneSyncRecords[i].SF_Contact_Id__c = results[i].getId();
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
