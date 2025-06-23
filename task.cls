trigger PreventDuplicatesAdvanced on LocBrchJn__c (before insert, before update) {
    
    // Set to store composite keys for duplicate checking
    Set<String> compositeKeys = new Set<String>();
    
    // Map to store existing records
    Map<String, LocBrchJn__c> existingRecords = new Map<String, LocBrchJn__c>();
    
    // Build composite keys from incoming records
    for (LocBrchJn__c record : Trigger.new) {
        String compositeKey = '';
        System.debug('Trigger.new'  + Trigger.new);
        
        //ProductType__c, Branch__r.Name 
        
        // Build composite key - modify fields as needed
        if (record.Branch__r.Name  != null) {
            compositeKey += record.Branch__r.Name.toLowerCase().trim();
        }
        if (record.ProductType__c != null) {
            compositeKey += '|' + record.ProductType__c.toLowerCase().trim();
        }
        // Add more fields as needed
        
        if (String.isNotBlank(compositeKey)) {
            compositeKeys.add(compositeKey);
        }
         System.debug('compKey ===> ' + compositeKey);
    }
    
    //System.debug('compKey ===> ' + compositeKeys);
    
    
    // Query existing records
    if (!compositeKeys.isEmpty()) {
        for (LocBrchJn__c existingRecord : [
            SELECT Id,ProductType__c, Branch__r.Name 
            FROM LocBrchJn__c 
            WHERE ProductType__c != null AND Branch__r.Name != null
        ]) {
            String existingCompositeKey = '';
            
            if (existingRecord.Branch__r.Name != null) {
                existingCompositeKey += existingRecord.Branch__r.Name.toLowerCase().trim();
            }
            if (existingRecord.ProductType__c != null) {
                existingCompositeKey += '|' + existingRecord.ProductType__c.toLowerCase().trim();
            }
            
            if (String.isNotBlank(existingCompositeKey)) {
                existingRecords.put(existingCompositeKey, existingRecord);
            }
        }
    }
    
    System.debug('existingRecords ===> ' + existingRecords);
    
    // Check for duplicates
    for (LocBrchJn__c record : Trigger.new) {
        String compositeKey = '';
        
        if (record.Branch__r.Name  != null) {
            compositeKey += record.Branch__r.Name.toLowerCase().trim();
        }
        if (record.ProductType__c != null) {
            compositeKey += '|' + record.ProductType__c.toLowerCase().trim();
        }
        
        if (String.isNotBlank(compositeKey) && existingRecords.containsKey(compositeKey)) {
            LocBrchJn__c existingRecord = existingRecords.get(compositeKey);
            
            // Allow updates to the same record
            if (Trigger.isUpdate && record.Id == existingRecord.Id) {
                continue;
            }
            
            // Add error
            record.addError('A record with the same Name and Email already exists. Duplicate records are not allowed.');
        }
    }
}
