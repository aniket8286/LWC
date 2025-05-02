public with sharing class FinnoneMappingController {
    private static String recordNameId = [Select id from RecordType where Name = 'Business Account' LIMIT 1].Id;
    
    public class ProcessResult {
        @AuraEnabled public Integer upsertCount { get; set; }
        @AuraEnabled public Integer insertCount { get; set; }
        @AuraEnabled public Integer failedCount { get; set; }
        @AuraEnabled public List<Id> processedRecords { get; set; }
        @AuraEnabled public String batchJobId { get; set; }
        @AuraEnabled public String status { get; set; }
        
        public ProcessResult() {
            upsertCount = 0;
            insertCount = 0;
            failedCount = 0;
            processedRecords = new List<Id>();
            status = 'Processing';
        }
    }
    
    /**
     * Process CSV file using ContentDocument ID
     * @param contentDocumentId The ContentDocument ID of the uploaded file
     * @return ProcessResult with batch job ID and initial status
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
            
            // Parse the CSV content and start batch process
            CSVProcessingBatch batchProcess = new CSVProcessingBatch(csvContent);
            Id batchId = Database.executeBatch(batchProcess, 200);
            
            // Store batch ID for reference
            result.batchJobId = batchId;
            result.processedRecords.add(batchId);
            
            // Create a batch job status record to track results
            BatchJobStatus__c status = new BatchJobStatus__c(
                BatchId__c = batchId,
                JobType__c = 'CSV Processing',
                Status__c = 'Processing',
                StartTime__c = Datetime.now()
            );
            insert status;
            
        } catch (Exception e) {
            String fullError = 'Error processing CSV data: ' + e.getMessage() + ' at line ' + e.getLineNumber() + '\n' + e.getStackTraceString();
            System.debug('FULL ERROR: ' + fullError);
            throw new AuraHandledException(fullError);
        }
        
        return result;
    }
    
    /**
     * Check the status of a batch job
     * @param batchId The ID of the batch job to check
     * @return ProcessResult with current status and counts
     */
    @AuraEnabled
    public static ProcessResult checkBatchStatus(String batchId) {
        ProcessResult result = new ProcessResult();
        
        try {
            // Query for the status record
            BatchJobStatus__c status = [
                SELECT Id, Status__c, RecordsProcessed__c, RecordsFailed__c, 
                       RecordsSucceeded__c, RecordsUpdated__c, RecordsInserted__c 
                FROM BatchJobStatus__c 
                WHERE BatchId__c = :batchId 
                LIMIT 1
            ];
            
            // Also check the AsyncApexJob for more accurate status
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CompletedDate
                FROM AsyncApexJob 
                WHERE Id = :batchId
            ];
            
            // Update our status based on the AsyncApexJob status
            if (job.Status == 'Completed' || job.Status == 'Failed' || job.Status == 'Aborted') {
                status.Status__c = job.Status;
                update status;
            }
            
            // Set result values
            result.batchJobId = batchId;
            result.status = status.Status__c;
            result.upsertCount = status.RecordsUpdated__c != null ? Integer.valueOf(status.RecordsUpdated__c) : 0;
            result.insertCount = status.RecordsInserted__c != null ? Integer.valueOf(status.RecordsInserted__c) : 0;
            result.failedCount = status.RecordsFailed__c != null ? Integer.valueOf(status.RecordsFailed__c) : 0;
            
            // Add the batch ID to processed records
            result.processedRecords.add(batchId);
            
        } catch (Exception e) {
            System.debug('Error checking batch status: ' + e.getMessage());
            result.status = 'Error: ' + e.getMessage();
        }
        
        return result;
    }
}