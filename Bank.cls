@AuraEnabled
    public static Map<String, Integer> mapToAccountObject() {
        Map<String, Integer> result = new Map<String, Integer>{'mappedCount' => 0, 'insertedCount' => 0, 'updatedCount' => 0};

        try {
            Map<String, String> finnoneToAccountFieldMap = new Map<String, String>{
                'Name' => 'Name',
                'AgencyCode__c' => 'AgencyCode__c',
                'Bank_Ac_No__c' => 'AccountNumber'
                // 'City_Id__c' => 'BillingCity'

            };

            // Query records (get all where ID is null or not)
            String query = 'SELECT Id, SF_Account_Id__c, SF_Contact_Id__c';
            for (String f : finnoneToAccountFieldMap.keySet()) query += ', ' + f;
            query += ' FROM FinnoneSync__c LIMIT 10000';

            List<FinnoneSync__c> finnoneSyncRecords = Database.query(query);
            if (finnoneSyncRecords.isEmpty()) return result;

            Map<Id, Account> existingAccountsMap = new Map<Id, Account>();
            Set<Id> existingIds = new Set<Id>();

            for (FinnoneSync__c fs : finnoneSyncRecords) {
                if (String.isNotBlank(fs.SF_Account_Id__c)) existingIds.add((Id)fs.SF_Account_Id__c);
            }

            if (!existingIds.isEmpty()) {
                existingAccountsMap = new Map<Id, Account>(
                    [SELECT Id, Name FROM Account WHERE Id IN :existingIds]
                );
            }

            List<Account> accountsToUpsert = new List<Account>();

            for (FinnoneSync__c fs : finnoneSyncRecords) {
                Account acc;
                if (existingAccountsMap.containsKey(fs.SF_Account_Id__c)) {
                    result.put('updatedCount', result.get('updatedCount') + 1);
                    acc = existingAccountsMap.get(fs.SF_Account_Id__c);
                } else {
                    result.put('insertedCount', result.get('insertedCount') + 1);
                    acc = new Account();
                }

                for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                    String accountField = finnoneToAccountFieldMap.get(finnoneField);
                    Object value = fs.get(finnoneField);
                    if (value != null) acc.put(accountField, value);
                }
               // acc.RecordTypeId = recordNameId;
                acc.put('Partner_Type__c' , 'Dealer');
                //acc.Partner_Type__c = 'Dealer';
                accountsToUpsert.add(acc);
            }

            if (!accountsToUpsert.isEmpty()) {
                List<Database.UpsertResult> results = Database.upsert(accountsToUpsert, Account.Id, false);

                List<FinnoneSync__c> toUpdate = new List<FinnoneSync__c>();
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        result.put('mappedCount', result.get('mappedCount') + 1);
                        if (String.isBlank(finnoneSyncRecords[i].SF_Account_Id__c)) {
                            finnoneSyncRecords[i].SF_Account_Id__c = results[i].getId();
                            toUpdate.add(finnoneSyncRecords[i]);
                        }
                    }
                }

                if (!toUpdate.isEmpty()) update toUpdate;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error mapping to Account: ' +  e.getMessage() + '  '+ e.getLineNumber());
        }

        return result;
    }
