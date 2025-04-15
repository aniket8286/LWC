/**
 * Controller for CSV Account Uploader component
 * Handles processing CSV data and creating Account records
 */
public with sharing class CSVUploaderController {
    
    /**
     * Process CSV data and create Account records
     * @param csvFileData The CSV file data as a string
     * @return String JSON string with import results
     */
    @AuraEnabled
    public static String processCSVData(String csvFileData) {
        try {
            // Parse the CSV data
            List<List<String>> csvRows = parseCSV(csvFileData);
            
            // The first row should be the header
            if (csvRows.isEmpty()) {
                return createResultJSON(0, 0, 0);
            }
            
            List<String> headers = csvRows.remove(0);
            
            // Validate required headers
            validateHeaders(headers);
            
            // Process the data rows and create Account records
            List<Account> accountsToInsert = new List<Account>();
            
            for (List<String> row : csvRows) {
                try {
                    Account acc = createAccountFromRow(headers, row);
                    accountsToInsert.add(acc);
                } catch (Exception e) {
                    // Log the error (would be better with a more robust error handling)
                    System.debug('Error processing row: ' + e.getMessage());
                }
            }
            
            // Insert the accounts with partial success allowed
            Database.SaveResult[] saveResults = Database.insert(accountsToInsert, false);
            
            // Count successes and failures
            Integer successCount = 0;
            Integer failureCount = 0;
            
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    // Log errors
                    for (Database.Error err : sr.getErrors()) {
                        System.debug('Error: ' + err.getMessage());
                    }
                }
            }
            
            // Return results as JSON
            return createResultJSON(csvRows.size(), successCount, failureCount);
        } catch (Exception e) {
            throw new AuraHandledException('Error processing CSV: ' + e.getMessage());
        }
    }
    
    /**
     * Parse CSV string into list of rows
     * @param csvString The CSV data as a string
     * @return List<List<String>> List of rows, each row being a list of column values
     */
    private static List<List<String>> parseCSV(String csvString) {
        List<List<String>> results = new List<List<String>>();
        
        // Split the CSV by lines
        List<String> lines = csvString.split('\\n');
        
        for (String line : lines) {
            if (String.isBlank(line)) continue;
            
            // Handle CSV parsing with quoted values
            List<String> row = new List<String>();
            Boolean inQuotes = false;
            String currentValue = '';
            
            for (Integer i = 0; i < line.length(); i++) {
                String currentChar = line.substring(i, i+1);
                
                if (currentChar == '"') {
                    inQuotes = !inQuotes;
                } else if (currentChar == ',' && !inQuotes) {
                    row.add(currentValue.trim());
                    currentValue = '';
                } else {
                    currentValue += currentChar;
                }
            }
            
            // Add the last value
            row.add(currentValue.trim());
            
            // Clean up quotes from values
            for (Integer i = 0; i < row.size(); i++) {
                String val = row[i];
                if (val.startsWith('"') && val.endsWith('"')) {
                    row[i] = val.substring(1, val.length() - 1);
                }
            }
            
            results.add(row);
        }
        
        return results;
    }
    
    /**
     * Validate that required headers are present in the CSV
     * @param headers List of header names from the CSV
     */
    private static void validateHeaders(List<String> headers) {
        // Convert headers to lowercase for case-insensitive comparison
        Set<String> headerSet = new Set<String>();
        for (String header : headers) {
            headerSet.add(header.toLowerCase());
        }
        
        // Check for mandatory fields
        Set<String> requiredHeaders = new Set<String>{'name'};
        
        for (String required : requiredHeaders) {
            if (!headerSet.contains(required.toLowerCase())) {
                throw new AuraHandledException('Missing required column: ' + required);
            }
        }
    }
    
    /**
     * Create an Account record from a CSV row
     * @param headers List of column headers
     * @param values List of column values
     * @return Account The Account object with fields set from the CSV
     */
    private static Account createAccountFromRow(List<String> headers, List<String> values) {
        Account acc = new Account();
        
        // Ensure values list is at least as long as headers list
        while (values.size() < headers.size()) {
            values.add('');
        }
        
        // Map CSV columns to Account fields
        for (Integer i = 0; i < headers.size(); i++) {
            String header = headers[i].toLowerCase();
            String value = values[i];
            
            // Skip empty values
            if (String.isBlank(value)) continue;
            
            // Map common Account fields
            // Add more field mappings as needed
            switch on header {
                when 'name' {
                    acc.Name = value;
                }
                when 'accountnumber', 'account number', 'account_number' {
                    acc.AccountNumber = value;
                }
                when 'phone' {
                    acc.Phone = value;
                }
                when 'website' {
                    acc.Website = value;
                }
                when 'industry' {
                    acc.Industry = value;
                }
                when 'type' {
                    acc.Type = value;
                }
                when 'billingstreet', 'billing street', 'billing_street' {
                    acc.BillingStreet = value;
                }
                when 'billingcity', 'billing city', 'billing_city' {
                    acc.BillingCity = value;
                }
                when 'billingstate', 'billing state', 'billing_state' {
                    acc.BillingState = value;
                }
                when 'billingpostalcode', 'billing postalcode', 'billing_postalcode' {
                    acc.BillingPostalCode = value;
                }
                when 'billingcountry', 'billing country', 'billing_country' {
                    acc.BillingCountry = value;
                }
                when 'description' {
                    acc.Description = value;
                }
                when 'employees', 'numberofemployees', 'number of employees' {
                    try {
                        acc.NumberOfEmployees = Integer.valueOf(value);
                    } catch (Exception e) {
                        // Handle parsing error
                        System.debug('Error converting NumberOfEmployees: ' + e.getMessage());
                    }
                }
                when 'annualrevenue', 'annual revenue', 'annual_revenue' {
                    try {
                        acc.AnnualRevenue = Decimal.valueOf(value);
                    } catch (Exception e) {
                        // Handle parsing error
                        System.debug('Error converting AnnualRevenue: ' + e.getMessage());
                    }
                }
            }
        }
        
        return acc;
    }
    
    /**
     * Create a JSON string with import results
     * @param totalRecords Total number of records processed
     * @param successRecords Number of records successfully inserted
     * @param failedRecords Number of records that failed to insert
     * @return String JSON string with results
     */
    private static String createResultJSON(Integer totalRecords, Integer successRecords, Integer failedRecords) {
        return '{"totalRecords":' + totalRecords + 
               ',"successRecords":' + successRecords + 
               ',"failedRecords":' + failedRecords + '}';
    }
}
