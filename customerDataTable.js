import { LightningElement, track } from 'lwc';
import getCustomerData from '@salesforce/apex/CustomerDataController.getCustomerData';
import countCustomerData from '@salesforce/apex/CustomerDataController.countCustomerData';
import getAllCustomerData from '@salesforce/apex/CustomerDataController.getAllCustomerData';

const PAGE_SIZE = 500;

export default class CustomerDataTable extends LightningElement {
    @track data = [];
    @track columns = [
        { label: 'Customer ID', fieldName: 'Customer_ID__c', sortable: true },
        { label: 'Name', fieldName: 'Name', sortable: true },
        { label: 'Stage', fieldName: 'Stage__c', sortable: true },
        { label: 'Product', fieldName: 'Product__c', sortable: true }
    ];
    @track pageNumber = 1;
    @track totalRecords = 0;
    @track totalPages = 0;
    @track sortedBy;
    @track sortedDirection;
    @track selectedFilter = ''; // Added for storing filter value

    @track filterOptions = [
        { label: 'All', value: '' },
        { label: 'Booked', value: 'Booked' },
        { label: 'Branch Queue', value: 'Branch Queue' },
        { label: 'OPS Queue', value: 'OPS Queue' }
    ];

    connectedCallback() {
        this.fetchData();
        this.fetchTotalRecords();
    }

    // Fetch filtered data with sorting and pagination
    fetchData() {
        const offsetValue = (this.pageNumber - 1) * PAGE_SIZE;

        getCustomerData({
            limitSize: PAGE_SIZE,
            offsetValue: offsetValue,
            sortedBy: this.sortedBy || 'Name', // Default sort by 'Name'
            sortedDirection: this.sortedDirection || 'ASC', // Default sort direction 'ASC'
            stageFilter: this.selectedFilter // Add the stage filter
        })
        .then((result) => {
            this.data = result;
        })
        .catch((error) => {
            console.error('Error fetching paginated, sorted, and filtered customer data:', error);
        });
    }

    fetchTotalRecords() {
        countCustomerData()
            .then((count) => {
                this.totalRecords = count;
                this.totalPages = Math.ceil(count / PAGE_SIZE);
            })
            .catch((error) => {
                console.error('Error fetching total customer count:', error);
            });
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
        this.fetchData(); // Re-fetch data with the new sort order
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber -= 1;
            this.fetchData();
        }
    }

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber += 1;
            this.fetchData();
        }
    }

    // Handle stage filter change from the UI
    handleFilterChange(event) {
        this.selectedFilter = event.target.value; // Capture selected filter
        this.pageNumber = 1; // Reset to the first page when filter changes
        this.fetchData(); // Fetch filtered data
    }

    // Handle changes in page size if needed
    handleLimitChange(event) {
        this.limitSize = parseInt(event.target.value, 10);
        this.currentOffset = 0; // Reset to first page
    }

    downloadAllData() {
        getAllCustomerData()
            .then((data) => {
                console.log('Customer Data:', data);
                if (data.length > 0) {
                    const csvData = this.convertArrayToCSV(data);
                    const blob = new Blob([csvData], { type: 'text/plain' });
                    const downloadLink = document.createElement('a');
                    downloadLink.href = URL.createObjectURL(blob);
                    downloadLink.setAttribute('download', 'AllCustomerData.csv');
                    document.body.appendChild(downloadLink);
                    downloadLink.click();
                    document.body.removeChild(downloadLink);
                } else {
                    console.error('No data found for download.');
                }
            })
            .catch((error) => {
                console.error('Error fetching all customer data:', error);
            });
    }

    convertArrayToCSV(data) {
        if (!data || data.length === 0) return '';

        const headers = ['Customer_ID__c', 'Name', 'Stage__c', 'Product__c'];
        const rows = data.map(record =>
            [record.Customer_ID__c, record.Name, record.Stage__c, record.Product__c]
            .map(field => `${field}`).join(',')
        );
        return [headers.join(','), ...rows].join('\n');
    }

    get isPreviousDisabled() {
        return this.pageNumber === 1;
    }

    get isNextDisabled() {
        return this.pageNumber === this.totalPages;
    }
}
 