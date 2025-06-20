// THREE FIELD COMBINATION DUPLICATE PREVENTION
// Replace 'YourObject__c' with your actual object API name
// Replace field names: Name, Age__c, Designation__c with your actual field API names

trigger PreventDuplicates on YourObject__c (before insert, before update) {
    
    // Set to store composite keys for duplicate checking
    Set<String> compositeKeys = new Set<String>();
    
    // Map to store existing records with their composite keys
    Map<String, YourObject__c> existingRecords = new Map<String, YourObject__c>();
    
    // Build composite keys from incoming records
    for (YourObject__c record : Trigger.new) {
        // Check if all three mandatory fields are populated
        if (record.Name != null && record.Age__c != null && record.Designation__c != null) {
            // Build composite key: Name|Age|Designation
            String compositeKey = record.Name.toLowerCase().trim() + '|' + 
                                String.valueOf(record.Age__c).trim() + '|' + 
                                record.Designation__c.toLowerCase().trim();
            compositeKeys.add(compositeKey);
        }
    }
    
    // Query existing records to check for duplicates
    if (!compositeKeys.isEmpty()) {
        // Get all existing records that might match
        for (YourObject__c existingRecord : [
            SELECT Id, Name, Age__c, Designation__c 
            FROM YourObject__c 
            WHERE Name != null AND Age__c != null AND Designation__c != null
        ]) {
            // Build composite key for existing record
            String existingCompositeKey = existingRecord.Name.toLowerCase().trim() + '|' + 
                                        String.valueOf(existingRecord.Age__c).trim() + '|' + 
                                        existingRecord.Designation__c.toLowerCase().trim();
            
            if (compositeKeys.contains(existingCompositeKey)) {
                existingRecords.put(existingCompositeKey, existingRecord);
            }
        }
    }
    
    // Check each incoming record for duplicates
    for (YourObject__c record : Trigger.new) {
        // Check if all three mandatory fields are populated
        if (record.Name != null && record.Age__c != null && record.Designation__c != null) {
            // Build composite key for this record
            String compositeKey = record.Name.toLowerCase().trim() + '|' + 
                                String.valueOf(record.Age__c).trim() + '|' + 
                                record.Designation__c.toLowerCase().trim();
            
            if (existingRecords.containsKey(compositeKey)) {
                YourObject__c existingRecord = existingRecords.get(compositeKey);
                
                // For updates, allow if it's the same record
                if (Trigger.isUpdate && record.Id == existingRecord.Id) {
                    continue;
                }
                
                // Add error to prevent save
                record.addError('A record with the same Name (' + record.Name + '), Age (' + record.Age__c + '), and Designation (' + record.Designation__c + ') already exists. This combination must be unique.');
            }
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