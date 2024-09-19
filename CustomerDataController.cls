public with sharing class CustomerDataController {

    @AuraEnabled(cacheable=true)
    public static List<CustomerData__c> getCustomerData(Integer limitSize, Integer offsetValue, String sortedBy, String sortedDirection, String stageFilter) {
        String query = 'SELECT Customer_ID__c, Name, Stage__c, Product__c FROM CustomerData__c';

        // Apply filtering if the stageFilter is provided
        if (stageFilter != null && stageFilter != '') {
            query += ' WHERE Stage__c = :stageFilter';
        }

        // Apply sorting if provided
        if (sortedBy != null && sortedDirection != null) {
            query += ' ORDER BY ' + sortedBy + ' ' + sortedDirection;
        }
        
        query += ' LIMIT :limitSize OFFSET :offsetValue';
        
        return Database.query(query);
    }

    @AuraEnabled(cacheable=true)
    public static Integer countCustomerData() {
        return [SELECT COUNT() FROM CustomerData__c];
    }

    @AuraEnabled(cacheable=true)
    public static List<CustomerData__c> getAllCustomerData() {
        return [SELECT Customer_ID__c, Name, Stage__c, Product__c FROM CustomerData__c];
    }
}
