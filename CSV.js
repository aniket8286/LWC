public with sharing class FinnoneMappingController {
    
    public class ProcessResult {
        @AuraEnabled public Integer upsertCount { get; set; }
        @AuraEnabled public Integer insertCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public List<Id> processedRecords { get; set; }
        
        public ProcessResult() {
            upsertCount = 0;
            insertCount = 0;
            failedCount = 0;
            processedRecords = new List<Id>();
        }
    }
    
    /**
     * Process CSV file using ContentDocument ID
     * @param contentDocumentId The ContentDocument ID of the uploaded file
     * @return ProcessResult with counts of successful operations and failures
     */
    
     @AuraEnabled
     public static ProcessResult processCSVData(String contentDocumentId) {
         ProcessResult result = new ProcessResult();
         
         try {
             // Retrieve the file content
             ContentVersion contentVersion = [
                 SELECT VersionData 
                 FROM ContentVersion 
                 WHERE ContentDocumentId = :contentDocumentId 
                 AND IsLatest = true
                 LIMIT 1
             ];
             
             if (contentVersion == null) {
                 throw new AuraHandledException('File not found');
             }
             
             // Get the file content as a string
             String csvContent = contentVersion.VersionData.toString();
             
             // Parse the CSV content
             List<FinnoneSync__c> recordsToProcess = new List<FinnoneSync__c>();
             
             // Process CSV content
             List<String> csvLines = csvContent.split('\n');
             
             if (csvLines.size() <= 1) {
                 throw new AuraHandledException('CSV file appears to be empty or contains only headers');
             }
             
             // Get headers (first line)
             List<String> headers = parseCSVLine(csvLines[0]);
              //list of namesOf agency
              List<String> agencyName = new List<String>();
             // Process each data line
             for (Integer i = 1; i < csvLines.size(); i++) {
                 String line = csvLines[i].trim();
                 if (String.isBlank(line)) continue; // Skip empty lines
                 
                 List<String> values = parseCSVLine(line);
                 Map<String, String> recordMap = new Map<String, String>();

                
                 // Map each header to its value
                 for (Integer j = 0; j < headers.size() && j < values.size(); j++) {
                     recordMap.put(headers[j].trim(), values[j].trim());
                     if(recordMap.containsKey('Name')){
                        agencyName.add(recordMap.get('Name'));
                     }
                 }

                 
                 // Create a FinnoneSync record
                 FinnoneSync__c finnoneRecord = createFinnoneSyncRecord(recordMap);
                 //recordMap has comma seperated values 
                 System.debug('recordMap========>' + recordMap + '    ');
                 System.debug('agencyName========>' + agencyName + '    ');

                 recordsToProcess.add(finnoneRecord);
            }

            Map<String, FinnoneSync__c> existingAgenciesMap = new Map<String, FinnoneSync__c>();
            for (FinnoneSync__c existing : [SELECT Id, Name FROM FinnoneSync__c WHERE Name IN :agencyName]) {
                existingAgenciesMap.put(existing.Name, existing);
            }
             
            //  if (!recordsToProcess.isEmpty()) {
            //      // For now, let's just insert records to avoid external ID issues
            //      List<Database.SaveResult> insertResults = Database.insert(recordsToProcess, false);
                 
            //      for (Database.SaveResult sr : insertResults) {
            //          if (sr.isSuccess()) {
            //              result.insertCount++;
            //              result.processedRecords.add(sr.getId());
            //          } else {
            //              result.failedCount++;
            //              System.debug('Error inserting record: ' + sr.getErrors()[0].getMessage());
            //          }
            //      }
            //  }

            //update logic
        Set<FinnoneSync__c> recordsToInsertSet = new Set<FinnoneSync__c>();
        Set<FinnoneSync__c> recordsToUpdateSet = new Set<FinnoneSync__c>();

        for (FinnoneSync__c record : recordsToProcess) {
            if (existingAgenciesMap.containsKey(record.Name)) {
                // Set the ID of the existing record so it updates
                record.Id = existingAgenciesMap.get(record.Name).Id;
                recordsToUpdateSet.add(record);
            } else {
                recordsToInsertSet.add(record);
            }
        }

        System.debug('existingAgenciesMap==========>' + existingAgenciesMap);
        System.debug('recordsToInsertSet==========>' +recordsToInsertSet );
        System.debug('recordsToUpdateSet==========>' + recordsToUpdateSet);
        //set to list for unique fields
        List<FinnoneSync__c> recordsToInsert = new List<FinnoneSync__c>(recordsToInsertSet);
        List<FinnoneSync__c> recordsToUpdate = new List<FinnoneSync__c>(recordsToUpdateSet);


        if (!recordsToUpdate.isEmpty()) {
            List<Database.SaveResult> updateResults = Database.update(recordsToUpdate);
            for (Database.SaveResult sr : updateResults) {
                if (sr.isSuccess()) {
                    result.upsertCount++; 
                    result.processedRecords.add(sr.getId());
                } else {
                    result.failedCount++;
                    System.debug('Update Error: ' + sr.getErrors()[0].getMessage());
                }
            }
        }

        // Insert new records
        if (!recordsToInsert.isEmpty()) {
            List<Database.SaveResult> insertResults = Database.insert(recordsToInsert);
            for (Database.SaveResult sr : insertResults) {
                if (sr.isSuccess()) {
                    result.insertCount++;
                    result.processedRecords.add(sr.getId());
                } else {
                    result.failedCount++;
                    System.debug('Insert Error: ' + sr.getErrors()[0].getMessage());
                }
            }
        }

        // Update existing records
        


         } catch (Exception e) {
             String fullError = 'Error processing CSV data: ' + e.getMessage() + ' at line ' + e.getLineNumber() + '\n' + e.getStackTraceString();
             System.debug('FULL ERROR: ' + fullError);
             throw new AuraHandledException(fullError);
         }
         
         return result;
     }
        
    /**
     * Parse a CSV line, handling quoted values and commas properly
     */
    private static List<String> parseCSVLine(String line) {
        List<String> results = new List<String>();
        Boolean inQuotes = false;
        String currentValue = '';
        
        for (Integer i = 0; i < line.length(); i++) {
            String currentChar = line.substring(i, i+1);
            
            if (currentChar == '"') {
                // Check for escaped quotes
                if (i + 1 < line.length() && line.substring(i+1, i+2) == '"') {
                    currentValue += '"';
                    i++; // Skip the next quote
                } else {
                    // Toggle quote mode
                    inQuotes = !inQuotes;
                }
            } else if (currentChar == ',' && !inQuotes) {
                // End of field
                results.add(currentValue);
                currentValue = '';
            } else {
                currentValue += currentChar;
            }
        }
        
        // Add the last value
        results.add(currentValue);
        return results;
    }
    
    /**
     * Create a FinnoneSync__c record from CSV data using static field mapping
     */
    private static FinnoneSync__c createFinnoneSyncRecord(Map<String, String> recordMap) {
        FinnoneSync__c record = new FinnoneSync__c();
        
        // Define explicit mappings from CSV headers to FinnoneSync__c field names
        Map<String, String> headerToFieldMap = new Map<String, String>{
            'Name' => 'Name',
            'Partner_Type__c' => 'Partner_Type__c',
            'Product__c' => 'Product__c',
            'AgencyCode__c' => 'AgencyCode__c',
            'BillingAddress.City' => 'City_ID__c',
            'Bank_Ac_No__c' => 'BnfName__c',
            'AccountNumber' => 'Cash_Bank_Acc_Desc__c',
            'Status__c' => 'Disburse_To__c'
            // 'State' => 'State__c',
            // 'Country' => 'Country__c',
            // 'PostalCode' => 'Postal_Code__c',
            // 'LoanAmount' => 'Loan_Amount__c',
            // 'LoanType' => 'Loan_Type__c',
            // 'ApplicationDate' => 'Application_Date__c',
            // 'ApplicationStatus' => 'Application_Status__c',
            // 'CustomerID' => 'Customer_ID__c',
            // 'AccountNumber' => 'Account_Number__c',
            // 'DateOfBirth' => 'Date_Of_Birth__c',
            // 'Gender' => 'Gender__c',
            // 'AnnualIncome' => 'Annual_Income__c',
            // 'EmploymentStatus' => 'Employment_Status__c',
            // 'Employer' => 'Employer__c',
            // 'CreditScore' => 'Credit_Score__c'
            // Add more mappings as needed
        };
        
        // Map fields from CSV to FinnoneSync object using the explicit mapping
        for (String headerName : recordMap.keySet()) {
            String value = recordMap.get(headerName);
            
            // Skip if value is blank
            if (String.isBlank(value)) continue;
            
            // Use the explicit mapping if it exists
            if (headerToFieldMap.containsKey(headerName)) {
                String apiFieldName = headerToFieldMap.get(headerName);
                
                // Get field type to perform appropriate conversion
                Schema.SObjectField field = Schema.SObjectType.FinnoneSync__c.fields.getMap().get(apiFieldName);
                if (field != null) {
                    Schema.DisplayType fieldType = field.getDescribe().getType();
                    
                    try {
                        // Convert value to the appropriate type
                        if (fieldType == Schema.DisplayType.Boolean) {
                            record.put(apiFieldName, Boolean.valueOf(value));
                        } else if (fieldType == Schema.DisplayType.Integer || fieldType == Schema.DisplayType.Double) {
                            record.put(apiFieldName, Decimal.valueOf(value));
                        } else if (fieldType == Schema.DisplayType.Date) {
                            record.put(apiFieldName, Date.valueOf(value));
                        } else if (fieldType == Schema.DisplayType.DateTime) {
                            record.put(apiFieldName, DateTime.valueOf(value));
                        } else {
                            record.put(apiFieldName, value);
                        }
                    } catch (Exception e) {
                        // Handle conversion errors
                        System.debug('Error setting field ' + apiFieldName + ': ' + e.getMessage());
                    }
                } else {
                    System.debug('Field not found in FinnoneSync__c: ' + apiFieldName);
                }
            } else {
                // Log when a CSV header doesn't have a mapping
                System.debug('No mapping found for CSV header: ' + headerName);
            }
        }
        
        return record;
    }
    
    /**
     * Map FinnoneSync__c records to Account object
     */
    @AuraEnabled
    public static Map<String, Integer> mapToAccountObject() {
        Map<String, Integer> result = new Map<String, Integer>{'mappedCount' => 0};
        
        try {
            // Define explicit field mappings from FinnoneSync__c to Account
            Map<String, String> finnoneToAccountFieldMap = new Map<String, String>{
                'Name' => 'Name'
            };
            
            // Build the query string with all FinnoneSync__c fields that need to be mapped
            String query = 'SELECT Id';
            for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                query += ', ' + finnoneField;
            }
            query += ' FROM FinnoneSync__c WHERE Mapped_To_Account__c = false LIMIT 10000';
            
            // Query records
            List<FinnoneSync__c> finnoneSyncRecords = Database.query(query);
            
            if (!finnoneSyncRecords.isEmpty()) {
                List<Account> accountsToUpsert = new List<Account>();
                
                for (FinnoneSync__c fsRecord : finnoneSyncRecords) {
                    Account acc = new Account();
                    
                    // Copy fields using explicit mapping
                    for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                        String accountField = finnoneToAccountFieldMap.get(finnoneField);
                        Object value = fsRecord.get(finnoneField);
                        if (value != null) {
                            acc.put(accountField, value);
                        }
                    }
                    
                    accountsToUpsert.add(acc);
                }
                
                // Upsert accounts
                if (!accountsToUpsert.isEmpty()) {
                    Schema.SObjectField externalIdField = Account.Fields.Id;
                    List<Database.UpsertResult> upsertResults = Database.upsert(accountsToUpsert, externalIdField, false);
                    
                    // Update FinnoneSync records as mapped
                    List<FinnoneSync__c> recordsToUpdate = new List<FinnoneSync__c>();
                    
                    for (Integer i = 0; i < upsertResults.size(); i++) {
                        if (upsertResults[i].isSuccess()) {
                            result.put('mappedCount', result.get('mappedCount') + 1);
                            //finnoneSyncRecords[i].Mapped_To_Account__c = true;
                            recordsToUpdate.add(finnoneSyncRecords[i]);
                        }
                    }
                    
                    if (!recordsToUpdate.isEmpty()) {
                        update recordsToUpdate;
                    }
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error mapping to Account: ' + e.getMessage());
        }
        
        return result;
    }

    @AuraEnabled
    public static Map<String, Integer> mapToContactObject() {
        Map<String, Integer> result = new Map<String, Integer>{'mappedCount' => 0};
        
        try {
            // Define explicit field mappings from FinnoneSync__c to Contact
            Map<String, String> finnoneToAccountFieldMap = new Map<String, String>{
                'Name' => 'LastName'
            };
            
            // Build the query string with all FinnoneSync__c fields that need to be mapped
            String query = 'SELECT Id';
            for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                query += ', ' + finnoneField;
            }
            query += ' FROM FinnoneSync__c WHERE Mapped_To_Account__c = false LIMIT 10000';
            
            // Query records
            List<FinnoneSync__c> finnoneSyncRecords = Database.query(query);
            
            if (!finnoneSyncRecords.isEmpty()) {
                List<Contact> contactToUpsert = new List<Contact>();
                
                for (FinnoneSync__c fsRecord : finnoneSyncRecords) {
                    Contact con = new Contact();
                    
                    // Copy fields using explicit mapping
                    for (String finnoneField : finnoneToAccountFieldMap.keySet()) {
                        String accountField = finnoneToAccountFieldMap.get(finnoneField);
                        Object value = fsRecord.get(finnoneField);
                        if (value != null) {
                            con.put(accountField, value);
                        }
                    }
                    
                    contactToUpsert.add(con);
                }
                
                // Upsert accounts
                if (!contactToUpsert.isEmpty()) {
                    Schema.SObjectField externalIdField = Contact.Fields.Id;
                    List<Database.UpsertResult> upsertResults = Database.upsert(contactToUpsert, externalIdField, false);
                    
                    // Update FinnoneSync records as mapped
                    List<FinnoneSync__c> recordsToUpdate = new List<FinnoneSync__c>();
                    
                    for (Integer i = 0; i < upsertResults.size(); i++) {
                        if (upsertResults[i].isSuccess()) {
                            result.put('mappedCount', result.get('mappedCount') + 1);
                            finnoneSyncRecords[i].Mapped_To_Account__c = true;
                            recordsToUpdate.add(finnoneSyncRecords[i]);
                        }
                    }
                    
                    if (!recordsToUpdate.isEmpty()) {
                        update recordsToUpdate;
                    }
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error mapping to Contact: ' + e.getMessage());
        }
        
        return result;
    }


}
