// csvUploaderComponent.js
import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processCSVData from '@salesforce/apex/CSVUploaderController.processCSVData';

export default class CsvUploaderComponent extends LightningElement {
    @track csvFile;
    @track isLoading = false;
    @track isSuccess = false;
    @track isError = false;
    @track errorMessage = '';
    @track successMessage = '';
    @track isUploadDisabled = true;
    @track showResults = false;
    @track totalRecords = 0;
    @track successRecords = 0;
    @track failedRecords = 0;

    // Handle file selection
    handleFileChange(event) {
        const file = event.target.files[0];
        if (file) {
            // Check if the file is a CSV
            if (file.type !== 'text/csv' && !file.name.endsWith('.csv')) {
                this.showError('Please upload a CSV file.');
                this.csvFile = null;
                this.isUploadDisabled = true;
                return;
            }
            
            this.csvFile = file;
            this.isUploadDisabled = false;
            this.clearMessages();
        } else {
            this.csvFile = null;
            this.isUploadDisabled = true;
        }
    }

    // Handle upload button click
    handleUpload() {
        if (!this.csvFile) {
            this.showError('Please select a CSV file to upload.');
            return;
        }

        this.isLoading = true;
        this.clearMessages();
        
        // Read the file contents
        const reader = new FileReader();
        reader.onload = () => {
            const fileContents = reader.result;
            this.uploadCSV(fileContents);
        };
        reader.readAsText(this.csvFile);
    }

    // Process CSV data and send to Apex controller
    uploadCSV(csvData) {
        processCSVData({ csvFileData: csvData })
            .then(result => {
                this.isLoading = false;
                
                // Parse the result from the Apex controller
                const resultObj = JSON.parse(result);
                
                this.totalRecords = resultObj.totalRecords;
                this.successRecords = resultObj.successRecords;
                this.failedRecords = resultObj.failedRecords;
                this.showResults = true;
                
                if (resultObj.successRecords > 0) {
                    this.showSuccess(`Successfully imported ${resultObj.successRecords} account records.`);
                }
                
                if (resultObj.failedRecords > 0) {
                    this.showError(`Failed to import ${resultObj.failedRecords} records. Please check your CSV format.`);
                }
                
                // Show toast notification
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Import Complete',
                        message: `Imported ${resultObj.successRecords} of ${resultObj.totalRecords} records.`,
                        variant: resultObj.failedRecords > 0 ? 'warning' : 'success',
                    }),
                );
                
                // Reset file input
                const fileInput = this.template.querySelector('lightning-input[type="file"]');
                if (fileInput) {
                    fileInput.value = null;
                }
                this.csvFile = null;
                this.isUploadDisabled = true;
            })
            .catch(error => {
                this.isLoading = false;
                this.showError('Error processing CSV: ' + (error.body ? error.body.message : error.message));
                console.error('Error processing CSV:', error);
            });
    }

    // Show success message
    showSuccess(message) {
        this.successMessage = message;
        this.isSuccess = true;
    }

    // Show error message
    showError(message) {
        this.errorMessage = message;
        this.isError = true;
    }

    // Clear all messages
    clearMessages() {
        this.isSuccess = false;
        this.isError = false;
        this.errorMessage = '';
        this.successMessage = '';
    }
}
