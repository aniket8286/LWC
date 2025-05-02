// syncStatus.js
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startSyncProcess from '@salesforce/apex/SyncController.startSyncProcess';

export default class SyncStatus extends LightningElement {
    @api recordId;
    @track isSyncing = false;
    @track totalRecords = 0;
    @track objectStatuses = [
        {
            name: 'Account',
            icon: 'standard:account',
            inserts: '100',
            insertClass: 'success-text',
            updates: '50',
            updateClass: 'warning-text',
            failed: '0',
            failedClass: 'error-text',
            statusClass: 'success-icon'
        },
        {
            name: 'Contact',
            icon: 'standard:contact',
            inserts: '-',
            insertClass: '',
            updates: '-',
            updateClass: '',
            failed: '-',
            failedClass: '',
            statusClass: 'locked-icon'
        },
        {
            name: 'Bank Master',
            icon: 'standard:asset_relationship',
            inserts: '-',
            insertClass: '',
            updates: '-',
            updateClass: '',
            failed: '-',
            failedClass: '',
            statusClass: 'locked-icon'
        }
    ];

    connectedCallback() {
        // Calculate total records from actual data
        this.calculateTotalRecords();
    }

    calculateTotalRecords() {
        let total = 0;
        this.objectStatuses.forEach(obj => {
            if (obj.inserts !== '-') {
                total += parseInt(obj.inserts, 10);
            }
            if (obj.updates !== '-') {
                total += parseInt(obj.updates, 10);
            }
            // Don't count failed records in total as they're already counted in attempted inserts/updates
        });
        this.totalRecords = total;
    }

    handleStartSync() {
        this.isSyncing = true;
        
        // Call Apex method to start synchronization
        startSyncProcess({ recordId: this.recordId })
            .then(result => {
                this.processResult(result);
                this.showToast('Success', 'Synchronization completed successfully', 'success');
            })
            .catch(error => {
                console.error('Error during sync process', error);
                this.showToast('Error', 'Synchronization failed: ' + error.body.message, 'error');
            })
            .finally(() => {
                this.isSyncing = false;
            });
    }

    processResult(result) {
        // Update component with returned sync results
        if (result && result.objectStatuses) {
            this.objectStatuses = result.objectStatuses.map(obj => {
                return {
                    ...obj,
                    insertClass: obj.inserts > 0 ? 'success-text' : '',
                    updateClass: obj.updates > 0 ? 'warning-text' : '',
                    failedClass: obj.failed > 0 ? 'error-text' : '',
                    statusClass: obj.failed > 0 ? 'error-icon' : 'success-icon'
                };
            });
            this.calculateTotalRecords();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}