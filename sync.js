// csvUploader.js
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processCSVData from '@salesforce/apex/FinnoneMappingController.processCSVData';
import checkBatchStatus from '@salesforce/apex/FinnoneMappingController.checkBatchStatus';

export default class CsvUploader extends LightningElement {
    @track isLoading = false;
    @track uploadedFileName = '';
    @track contentDocumentId = '';
    @track batchJobId = '';
    @track statusMessage = '';
    @track progress = 0;
    @track showResults = false;
    @track result = {
        upsertCount: 0,
        insertCount: 0,
        failedCount: 0,
        status: ''
    };
    
    // Polling mechanism variables
    pollingTimer;
    pollingInterval = 5000; // 5 seconds
    maxPollingAttempts = 30; // Max 2.5 minutes of polling
    pollingAttempts = 0;
    
    handleFileUpload(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles.length > 0) {
            this.uploadedFileName = uploadedFiles[0].name;
            this.contentDocumentId = uploadedFiles[0].documentId;
        }
    }
    
    handleProcessData() {
        if (!this.contentDocumentId) {
            this.showToast('Error', 'Please upload a CSV file first', 'error');
            return;
        }
        
        this.isLoading = true;
        this.statusMessage = 'Processing file...';
        this.progress = 10;
        
        processCSVData({ contentDocumentId: this.contentDocumentId })
            .then(result => {
                this.batchJobId = result.batchJobId;
                this.statusMessage = 'Processing started. Checking status...';
                this.progress = 20;
                
                // Start polling for status
                this.startPolling();
            })
            .catch(error => {
                this.handleError(error);
            });
    }
    
    startPolling() {
        // Clear any existing polling
        if (this.pollingTimer) {
            clearInterval(this.pollingTimer);
        }
        
        this.pollingAttempts = 0;
        
        // Set up polling at regular intervals
        this.pollingTimer = setInterval(() => {
            this.pollBatchStatus();
        }, this.pollingInterval);
    }
    
    pollBatchStatus() {
        this.pollingAttempts++;
        
        checkBatchStatus({ batchId: this.batchJobId })
            .then(result => {
                // Update the status and progress
                this.result = result;
                
                // Calculate progress (just an estimate)
                this.progress = Math.min(20 + (this.pollingAttempts * 2), 90);
                
                if (result.status === 'Completed') {
                    this.progress = 100;
                    this.statusMessage = 'Processing complete!';
                    this.showResults = true;
                    this.stopPolling();
                    this.showToast('Success', 'CSV processing completed', 'success');
                } else if (result.status === 'Failed' || result.status === 'Aborted') {
                    this.progress = 100;
                    this.statusMessage = 'Processing failed!';
                    this.showResults = true;
                    this.stopPolling();
                    this.showToast('Error', 'CSV processing failed', 'error');
                } else {
                    this.statusMessage = `Processing... (Attempt ${this.pollingAttempts})`;
                    
                    // Check if we've reached max attempts
                    if (this.pollingAttempts >= this.maxPollingAttempts) {
                        this.stopPolling();
                        this.statusMessage = 'Processing is taking longer than expected. Check back later.';
                        this.showToast('Warning', 'Processing is taking longer than expected', 'warning');
                    }
                }
            })
            .catch(error => {
                this.handleError(error);
                this.stopPolling();
            });
    }
    
    stopPolling() {
        if (this.pollingTimer) {
            clearInterval(this.pollingTimer);
            this.pollingTimer = null;
        }
        this.isLoading = false;
    }
    
    handleError(error) {
        this.isLoading = false;
        this.statusMessage = 'An error occurred';
        console.error('Error:', error);
        this.showToast('Error', this.extractErrorMessage(error), 'error');
    }
    
    extractErrorMessage(error) {
        let message = 'Unknown error';
        if (typeof error === 'string') {
            message = error;
        } else if (error.body && error.body.message) {
            message = error.body.message;
        } else if (error.message) {
            message = error.message;
        }
        return message;
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}