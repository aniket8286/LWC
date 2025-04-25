@AuraEnabled
public static Map<String, Integer> mapToBankObject() {
    Map<String, Integer> result = new Map<String, Integer>{'mappedCount' => 0, 'insertedCount' => 0, 'updatedCount' => 0};
    List<BankMstr__c> banksToUpsert = new List<BankMstr__c>();
    
    try {
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
        
        // Define record type ID
        Id recordTypeId = Schema.SObjectType.BankMstr__c.getRecordTypeInfosByName().get('Standard').getRecordTypeId();
        
        // Query FinnoneSync records
        String query = 'SELECT Id, SF_Bank_Id__c, Composite_Key_bank__c';
        for (String f : finnoneToBankFieldMap.keySet()) query += ', ' + f;
        query += ' FROM FinnoneSync__c LIMIT 10000';

        List<FinnoneSync__c> finnoneSyncRecords = Database.query(query);
        System.debug('query: ' + query);
        System.debug('finnoneSyncRecords size: ' + finnoneSyncRecords.size());
        
        if (finnoneSyncRecords.isEmpty()) return result;

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
        
        // Process FinnoneSync records
        for (FinnoneSync__c fs : finnoneSyncRecords) {
            BankMstr__c bank;
            
            // Check if SF_Bank_Id__c is present
            if (String.isNotBlank(fs.SF_Bank_Id__c) && existingBanksById.containsKey(fs.SF_Bank_Id__c)) {
                // Update existing bank record
                bank = existingBanksById.get(fs.SF_Bank_Id__c);
                result.put('updatedCount', result.get('updatedCount') + 1);
            } else {
                // Create new bank record
                bank = new BankMstr__c();
                result.put('insertedCount', result.get('insertedCount') + 1);
            }
            
            // Map fields from FinnoneSync to BankMstr
            for (String finnoneField : finnoneToBankFieldMap.keySet()) {
                String bankField = finnoneToBankFieldMap.get(finnoneField);
                Object value = fs.get(finnoneField);
                if (value != null) bank.put(bankField, value);
            }
            
            // Set record type
            bank.RecordTypeId = recordTypeId;
            
            banksToUpsert.add(bank);
        }
        
        // Perform DML operations
        if (!banksToUpsert.isEmpty()) {
            upsert banksToUpsert;
            result.put('mappedCount', banksToUpsert.size());
            
            // Update FinnoneSync records with new Bank IDs
            List<FinnoneSync__c> finnoneSyncToUpdate = new List<FinnoneSync__c>();
            for (Integer i = 0; i < finnoneSyncRecords.size(); i++) {
                FinnoneSync__c fs = finnoneSyncRecords[i];
                BankMstr__c bank = banksToUpsert[i];
                
                if (String.isBlank(fs.SF_Bank_Id__c) && bank.Id != null) {
                    fs.SF_Bank_Id__c = bank.Id;
                    finnoneSyncToUpdate.add(fs);
                }
            }
            
            if (!finnoneSyncToUpdate.isEmpty()) {
                update finnoneSyncToUpdate;
            }
        }
    } catch (Exception e) {
        throw new AuraHandledException('Error mapping to BankMstr__c: ' + e.getMessage() + ' at line ' + e.getLineNumber());
    }
    
    return result;
}
