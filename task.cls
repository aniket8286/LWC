trigger PreventDuplicatesAdvanced on LocBrchJn__c (before insert, before update) {
    
    // Set to store composite keys for duplicate checking
    Set<String> compositeKeys = new Set<String>();
    
    // Map to store existing records
    Map<String, LocBrchJn__c> existingRecords = new Map<String, LocBrchJn__c>();
    
    // Set to collect Branch IDs to query Branch names
    Set<Id> branchIds = new Set<Id>();
    
    // Map to store Branch ID to Branch Name mapping
    Map<Id, String> branchIdToNameMap = new Map<Id, String>();
    
    // Collect Branch IDs from incoming records
    for (LocBrchJn__c record : Trigger.new) {
        if (record.Branch__c != null) {
            branchIds.add(record.Branch__c);
        }
    }
    
    // Query Branch names if we have Branch IDs
    if (!branchIds.isEmpty()) {
        // Replace 'Branch__c' with your actual Branch object API name
        // Replace 'Name' with the actual field name you want to use from Branch
        for (Branch__c branch : [SELECT Id, Name FROM Branch__c WHERE Id IN :branchIds]) {
            branchIdToNameMap.put(branch.Id, branch.Name);
        }
    }
    
    System.debug('Trigger.new: ' + Trigger.new);
    System.debug('branchIdToNameMap: ' + branchIdToNameMap);
    
    // Build composite keys from incoming records
    for (LocBrchJn__c record : Trigger.new) {
        String compositeKey = '';
        
        // Build composite key using Branch ID to get Branch Name
        if (record.Branch__c != null && branchIdToNameMap.containsKey(record.Branch__c)) {
            String branchName = branchIdToNameMap.get(record.Branch__c);
            compositeKey += branchName.toLowerCase().trim();
        }
        if (record.ProductType__c != null) {
            compositeKey += '|' + record.ProductType__c.toLowerCase().trim();
        }
        
        if (String.isNotBlank(compositeKey)) {
            compositeKeys.add(compositeKey);
        }
        System.debug('compositeKey for record: ' + compositeKey);
    }
    
    System.debug('All compositeKeys: ' + compositeKeys);
    
    // Query existing records
    if (!compositeKeys.isEmpty()) {
        for (LocBrchJn__c existingRecord : [
            SELECT Id, ProductType__c, Branch__c, Branch__r.Name 
            FROM LocBrchJn__c 
            WHERE ProductType__c != null AND Branch__c != null
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
    
    System.debug('existingRecords: ' + existingRecords);
    
    // Check for duplicates
    for (LocBrchJn__c record : Trigger.new) {
        String compositeKey = '';
        
        if (record.Branch__c != null && branchIdToNameMap.containsKey(record.Branch__c)) {
            String branchName = branchIdToNameMap.get(record.Branch__c);
            compositeKey += branchName.toLowerCase().trim();
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
            
            // Add error with correct message
            record.addError('A record with the same Branch (' + branchIdToNameMap.get(record.Branch__c) + ') and Product Type (' + record.ProductType__c + ') already exists. Duplicate records are not allowed.');
        }
    }
}

// ADVANCED VERSION - Multiple Field Duplicate Prevention
// Uncomment and modify this version if you need to check multiple fields

/*
trigger PreventDuplicatesAdvanced on YourObject__c (before insert, before update) {
    
    // Set to store composite keys for duplicate checking
    Set<String> compositeKeys = new Set<String>();
    
    // Map to store existing records
    Map<String, YourObject__c> existingRecords = new Map<String, YourObject__c>();
    
    // Build composite keys from incoming records
    for (YourObject__c record : Trigger.new) {
        String compositeKey = '';
        
        // Build composite key - modify fields as needed
        if (record.Name != null) {
            compositeKey += record.Name.toLowerCase().trim();
        }
        if (record.Email__c != null) {
            compositeKey += '|' + record.Email__c.toLowerCase().trim();
        }
        // Add more fields as needed
        
        if (String.isNotBlank(compositeKey)) {
            compositeKeys.add(compositeKey);
        }
    }
    
    // Query existing records
    if (!compositeKeys.isEmpty()) {
        for (YourObject__c existingRecord : [
            SELECT Id, Name, Email__c 
            FROM YourObject__c 
            // Add WHERE clause based on your fields
        ]) {
            String existingCompositeKey = '';
            
            if (existingRecord.Name != null) {
                existingCompositeKey += existingRecord.Name.toLowerCase().trim();
            }
            if (existingRecord.Email__c != null) {
                existingCompositeKey += '|' + existingRecord.Email__c.toLowerCase().trim();
            }
            
            if (String.isNotBlank(existingCompositeKey)) {
                existingRecords.put(existingCompositeKey, existingRecord);
            }
        }
    }
    
    // Check for duplicates
    for (YourObject__c record : Trigger.new) {
        String compositeKey = '';
        
        if (record.Name != null) {
            compositeKey += record.Name.toLowerCase().trim();
        }
        if (record.Email__c != null) {
            compositeKey += '|' + record.Email__c.toLowerCase().trim();
        }
        
        if (String.isNotBlank(compositeKey) && existingRecords.containsKey(compositeKey)) {
            YourObject__c existingRecord = existingRecords.get(compositeKey);
            
            // Allow updates to the same record
            if (Trigger.isUpdate && record.Id == existingRecord.Id) {
                continue;
            }
            
            // Add error
            record.addError('A record with the same Name and Email already exists. Duplicate records are not allowed.');
        }
    }
}
*/