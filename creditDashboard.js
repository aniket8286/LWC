import { LightningElement,track,wire,api } from 'lwc';

import getState from '@salesforce/apex/CreditDashboard.getState';
import getBranchName from '@salesforce/apex/CreditDashboard.getBranchName';
import getProductCode from '@salesforce/apex/CreditDashboard.getProductCode';
import getLoanApplicationData from '@salesforce/apex/CreditDashboard.getLoanApplicationData';
import getLoanApplicationExport from '@salesforce/apex/CreditDashboard.getLoanApplicationExport';
import getLoanApplicationSummary from '@salesforce/apex/CreditDashboard.getLoanApplicationSummary';
import getEmpRole from '@salesforce/apex/CreditDashboard.getEmpRole';

import { ShowToastEvent } from "lightning/platformShowToastEvent";


export default class CreditDashboard extends LightningElement {
 
///////////////////fetched multiselect-data from apex /////////////
 
    hrefdata ='';
    templist = [];
    @track stageOptions = [];
    @track showTable = false;
    @track selectedStageValues = [];
    @track employeeRole = false;


    //State Variables
    @track stateOptions = [];
    @track visibleOptions = [];
    @track selectedStateValues = [];
    @track placeholder = '';
    @track showDD = false;
    @track isSelectAll = false;
    init = false;

    //Branch variables
    @track branchOptions = [];
    @track showBranchComponent = false;
    @track visibleOptionsBranch = [];
    @track selectedBranchValues = [];
    @track placeholderBranch = '';
    @track showDDBranch = false;
    @track isSelectAllBranch = false;
    @track isBranchLoading = false;
    @track isBranchClickProcessing = false;
    initBranch = false;

      // Product variables
    @track productOptions = [];
    @track showProductComponent = false;
    @track visibleOptionsProduct = [];
    @track selectedProductValues = [];
    @track placeholderProduct = '';
    @track showDDProduct = false;
    @track isSelectAllProduct = false;
    initProduct = false;

    // Stage variables
    @track stageOptions = [];
    @track showStageComponent = false;
    @track visibleOptionsStage = [];
    @track selectedStageValues = [];
    @track placeholderStage = '';
    @track showDDStage = false;
    @track isSelectAllStage = false;
    initStage = false;


///////////////////////date//////////////////
    startDate = this.getYesterday();
    endDate = this.getTodayDate();
    startMonth;
    endMonth;
////////////////////////////data///////////
    @track loanData=[];

    debounceTimeout;
    debounce(func, delay) {
        clearTimeout(this.debounceTimeout);
        this.debounceTimeout = setTimeout(() => {
            func.call(this);
        }, delay);
    }

    
    @track loanColumns = [
            { label: 'Loan Application ID', fieldName: 'loanApplicationName', type: 'text' },
            { label: 'Branch Name', fieldName: 'branchName', type: 'text' },
            { label: 'State Name', fieldName: 'state', type: 'text' },
            { label: 'Scheme Code', fieldName: 'schemeCode', type: 'text' },
            { label: 'Product Code', fieldName: 'productCode', type: 'text' },
            { label: 'Program Type', fieldName: 'programType', type: 'text' },
            { label: 'Stage', fieldName: 'stage', type: 'text' },
            { label: 'Sub Stage', fieldName: 'subStage', type: 'text' },
            { label: 'Status', fieldName: 'status', type: 'text' },
            { label: 'Owner Name', fieldName: 'ownerName', type: 'text'},
            { label: 'Lead End Date', fieldName: 'leadEndDate', type: 'text'},
            { label: 'Last Modified Date', fieldName: 'lastModifiedDate', type: 'text'},
        ];
    @track showLoan = false;
///////////////////////////////page/////////////////
    @track pageSize = 50;
    @track pageNumber = 1;
    @track totalPages;
    @track noDataMessage = ''; 
    @track noPage = true;
    @track error;
    @track loading = true;
    @track totalRecordCount;
    
//////////////////////////////////////Summary Total Count Data////////////////
    summaryColumns = [
        { label: 'Stage', fieldName: 'stage', type: 'text' },
        { label: 'Record Count', fieldName: 'recordCount', type: 'number' }
    ];

    @track summaryData = [
        { id: 1, stage: 'QDE', recordCount: 0, rowClass: '' },
        { id: 2, stage: 'DDE', recordCount: 0, rowClass: '' },
        { id: 3, stage: 'Verifications', recordCount: 0, rowClass: '' },
        { id: 4, stage: 'UW', recordCount: 0, rowClass: '' },
        { id: 5, stage: 'Post Sanction', recordCount: 0, rowClass: '' },
        { id: 6, stage: 'Total', recordCount: 0, rowClass: 'blue-row' } // Add class to highlight row
    ];

    @track stageOptions = [
        { label: 'QDE', value: 'QDE' },
        { label: 'DDE', value: 'DDE' },
        { label: 'Verifications', value: 'Verifications'},
        { label: 'UW', value: 'UW'},
        { label: 'Post Sanction', value: 'Post Sanction' }
    ];

    @track visibleOptionsStage = this.stageOptions.map(opt => opt.value);
    
    connectedCallback() {
        this.fetchEmpRole();
        // State
            document.addEventListener("click", (event) => {
                const stateContainer = this.template.querySelector(
                "[data-id='state-picklist']"
                );
                if (!stateContainer?.contains(event.target)) {
                this.showDD = false;
                }
            });
        // // Branch
            document.addEventListener('click', (event) => {
                // Only process if we're not handling our own click
                if (!this.isBranchClickProcessing) {
                    const branchContainer = this.template.querySelector(
                        "[data-id='branch-picklist']"
                    );
                    if (!branchContainer?.contains(event.target)) {
                        this.showDDBranch = false;
                    }
                }
            });
        // // Product
        document.addEventListener('click', (event) => {
            const productContainer = this.template.querySelector(
                "[data-id='product-picklist']"
                );
                if (!productContainer?.contains(event.target)) {
                    this.showDDProduct = false;
                }
        });
        // // Stage
        document.addEventListener('click', (event) => {
            const stageContainer = this.template.querySelector(
                "[data-id='stage-picklist']"
                );
                if (!stageContainer?.contains(event.target)) {
                    this.showDDStage = false;
                }
            
        });
    
        this.fetchProduct();
        this.fetchState();
    }

    renderedCallback() {    
        try {        
             // First dropdown initialization        
             if (!this.init) {
                const stateContainer = this.template.querySelector("[data-id='state-picklist']");
                if (stateContainer) {
                  stateContainer.addEventListener("click", (event) => {
                    event.stopPropagation(); // Stop propagation at the container level
                    this.showDD = !this.showDD;
                  });
                  this.init = true;
                }
              }
            
              if (!this.initBranch) {      
                const branchDropdown = this.template.querySelector("[data-id='branch-picklist']");       
                if (branchDropdown) {           
                    branchDropdown.addEventListener('click', this.handleBranchClick.bind(this));                
                    this.initBranch = true;  
                }    
             } 

              

              if (!this.initProduct) {      
                const productDropdown = this.template.querySelector("[data-id='product-picklist']");       
                if (productDropdown) {           
                    productDropdown.addEventListener('click', (event) => {   
                             
                    event.stopPropagation();    
                   this.showDDProduct = !this.showDDProduct;   
                  });                
                  this.initProduct = true;     
                }    
              } 

              if (!this.initStage) {      
                const stageDropdown = this.template.querySelector("[data-id='stage-picklist']");       
                if (stageDropdown) {           
                    stageDropdown.addEventListener('click', (event) => {   
                             
                    event.stopPropagation();    
                   this.showDDStage = !this.showDDStage;   
                  });                
                  this.initStage = true;     
                }    
              } 
            
            
        } catch (error) {        
            console.error('Error in renderedCallback:', error);   
        }
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    fetchState() {
        getState()
            .then((data) => {
                const fetchedOptions = data.map(state => ({
                    label: state,
                    value: state
                }));
                this.stateOptions = [...this.stateOptions, ...fetchedOptions];
                this.visibleOptions = this.stateOptions.map(opt => opt.value);
            })
            .catch((error) => {
                console.error('Error fetching state:', error);
            });
    }

    fetchEmpRole(){
        getEmpRole()
        .then((data)=>{
            if(!data){
                this.dispatchEvent(
                    new ShowToastEvent({
                      title: "Employee role not met",
                      message: "You are not Eligilbe.",
                      variant: "Error"
                    })
                  );
                throw new Error('You are not Eligilbe')
            }
            this.employeeRole = data;
        }).catch((error)=>{
            console.error('Error EmpRole data:', error);
        })    
    }

    handleBranchClick(event) {
        // Prevent event propagation
        event.stopPropagation();
        
        // Set flag to true to indicate we're processing a branch dropdown click
        this.isBranchClickProcessing = true;
        
        // Toggle dropdown state
        this.showDDBranch = !this.showDDBranch;
        
        // Reset the flag after a short delay
        setTimeout(() => {
            this.isBranchClickProcessing = false;
        }, 100);
    }

    fetchBranch() {
        this.isBranchLoading = true;
        this.branchOptions = []; // Clear immediately
        
        return getBranchName({selectedState : this.selectedStateValues})
            .then((data) => {
                // Create brand new options array (don't append)
                this.branchOptions = data.map(branch => ({
                    label: branch,
                    value: branch
                }));
                this.visibleOptionsBranch = this.branchOptions.map(opt => opt.value);
                return this.branchOptions; // Return for chaining
            })
            .catch((error) => {
                console.error('Error fetching branch:', error);
                this.branchOptions = []; // Clear on error
                throw error; // Propagate error
            })
            .finally(() => {
                this.isBranchLoading = false;
            });
    }

    fetchProduct() {
        getProductCode()
            .then((data) => {
                
                const fetchedOptions = data.map(Pro => ({
                    label: Pro,
                    value: Pro
                }));
                this.productOptions = [...this.productOptions, ...fetchedOptions];
                this.visibleOptionsProduct = this.productOptions.map(opt => opt.value);
                
            })
            .catch((error) => {
                console.error('Error fetching state:', error);
            });
    }

    

    


    ////////////multiselect state///////////////////

    get displayOptions() {
        return this.stateOptions.map(opt => ({
            ...opt,
            show: this.visibleOptions.includes(opt.value),
            checked: this.selectedStateValues.includes(opt.value)
        }));
    }
    
    handleSearch(event) {
        const searchTerm = event.target.value.toLowerCase();
        this.visibleOptions = [];
        
        this.stateOptions.forEach(option => {
            if (option.label.toLowerCase().includes(searchTerm)) {
                this.visibleOptions.push(option.value);
            }
        });
        
        this.showDD = this.visibleOptions.length > 0;
    }

    handleSelect(event) {
        const value = event.target.value;
        const checked = event.target.checked;
    
        if (value === 'SelectAll') {
            if (checked) {
                this.selectedStateValues = this.stateOptions.map(opt => opt.value);
            } else {
                this.selectedStateValues = [];
            }
        } else {
            if (checked) {
                if (!this.selectedStateValues.includes(value)) {
                    this.selectedStateValues.push(value);
                }
            } else {
                this.selectedStateValues = this.selectedStateValues.filter(item => item !== value);
            }
        }
    
        this.updateSelectAllState();
        this.updatePlaceholder();
        this.updateDataBasedOnStateChanges();
    }
    


    updateSelectAllState() {
        this.isSelectAll = this.selectedStateValues.length === this.stateOptions.length;
    }
    

    updatePlaceholder() {
        const count = this.selectedStateValues.length;
        this.placeholder = count > 0 ? `${count} Item(s) Selected` : '';
    }

    ////state pills////////

    get hasMultipleStates() {
        return this.selectedStateValues && this.selectedStateValues.length > 1;
    }
    
    
    handleStateRemove(event) {
        try {
            const valueToRemove = event.detail.name;
            this.selectedStateValues = this.selectedStateValues.filter(value => value !== valueToRemove);
    
            if (!this.visibleOptions || this.visibleOptions.length === 0) {
                this.visibleOptions = this.stateOptions.map(opt => opt.value);
            }
    
            this.updateSelectAllState();
            this.updatePlaceholder();
            this.updateDataBasedOnStateChanges();
        } catch (error) {
            console.error('Error in handleStateRemove:', error);
        }
    }



   // Modify the updateDataBasedOnStateChanges method
updateDataBasedOnStateChanges() {
    // Cancel any previous pending operations
    clearTimeout(this.debounceTimeout);
    
    // Reset branch selections when state changes
    this.selectedBranchValues = [];
    
    this.updatePlaceholderBranch();
    
    if (this.selectedStateValues.length > 0) {
        this.showBranchComponent = true;
        this.isSelectAllBranch = false;
        // Clear branch data immediately
        this.branchOptions = [];
        this.isBranchLoading = true;
        
        this.debounceTimeout = setTimeout(() => {
            this.fetchBranch()
                .then(() => {
                    // Verify the branch data is correctly filtered
                    console.log('Fetched branch count:', this.branchOptions.length);
                    return Promise.all([
                        this.wiredLoanData(),
                        this.summaryLoanData()
                    ]);
                })
                .catch(error => {
                    console.error('Error in sequence:', error);
                });
        }, 300);
    } else {
        this.showBranchComponent = false;
        this.showDDBranch = false;
        this.branchOptions = [];
        
        this.debounceTimeout = setTimeout(() => {
            this.wiredLoanData();
            this.summaryLoanData();
        }, 300);
    }
}

get hasMoreThanOne() {
    return this.selectedStateValues?.length > 1;
}

get showMoreLabel() {
    return this.isExpanded ? 'Show Less' : `Show More (${this.remainingPillsCount})`;
}

get remainingPillsCount() {
    return Math.max(this.selectedStateValues?.length - 1, 0);
}

toggleShowMore() {
    this.isExpanded = !this.isExpanded;
    this.toggleExpand('state', this.isExpanded);
}

toggleExpand(type, expand) {
    const listboxElement = this.template.querySelector(`[data-element="${type}-listbox"]`);
    if (listboxElement) {
        listboxElement.classList.toggle('expanded', expand);
    }
}

get selectedStatePills() {
    try {
        if (!Array.isArray(this.selectedStateValues) || !Array.isArray(this.stateOptions)) {
            return [];
        }
        return this.selectedStateValues.map(value => {
            const option = this.stateOptions.find(opt => opt.value === value);
            return { label: option?.label || value, value: value };
        });
    } catch (error) {
        console.error('Error in selectedStatePills getter:', error);
        return [];
    }
}



  //////////branch /////////

  get displayOptionsBranch() {
    return this.branchOptions.map(opt => ({
        ...opt,
        show: this.visibleOptionsBranch.includes(opt.value),
        checked: this.selectedBranchValues.includes(opt.value)
    }));
}

handleSearchBranch(event) {
    const searchTerm = event.target.value.toLowerCase();
    this.visibleOptionsBranch = [];
    this.branchOptions.forEach(option => {
        if (option.label.toLowerCase().includes(searchTerm)) {
            this.visibleOptionsBranch.push(option.value);
        }
    });
    this.showDDBranch = this.visibleOptionsBranch.length > 0;
}


handleSelectBranch(event) {
    const value = event.target.value;
    const checked = event.target.checked;
    if (value === 'SelectAll') {
        if (checked) {
            this.selectedBranchValues = this.branchOptions.map(opt => opt.value);
        } else {
            this.selectedBranchValues = [];
        }
    } else {
        if (checked) {
            if (!this.selectedBranchValues.includes(value)) {
                this.selectedBranchValues.push(value);
            }
        } else {
            this.selectedBranchValues = this.selectedBranchValues.filter(item => item !== value);
        }
    }
    this.updateSelectAllBranch();
   this.updatePlaceholderBranch();

    // if(this.selectedBranchValues.length>0){
    
       
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // }
    // else{
       
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // }
    this.wiredLoanData();
    this.summaryLoanData();
   
}

updateSelectAllBranch() {
    this.isSelectAllBranch = this.selectedBranchValues.length === this.branchOptions.length;
}

updatePlaceholderBranch() {
    const count = this.selectedBranchValues.length;
    this.placeholderBranch = count > 0 ? `${count} Item(s) Selected` : '';
}



get hasMultipleBranch() {
    return this.selectedBranchValues && this.selectedBranchValues.length > 1;
}


   handleBranchRemove(event) {
    try {
        const valueToRemove = event.detail.name;
        this.selectedBranchValues = this.selectedBranchValues.filter(value => value !== valueToRemove);


        // Ensure visibleOptionsBranch is initialized to all options if not set
        if (!this.visibleOptionsBranch || this.visibleOptionsBranch.length === 0) {
            this.visibleOptionsBranch = this.branchOptions.map(opt => opt.value);
        }

        this.updateSelectAllBranch();
        this.updatePlaceholderBranch();
        this.wiredLoanData();
        this.summaryLoanData();


    } catch (error) {
        console.error('Error in handleBranchRemove:', error);
    }
}

get hasMoreThanOneBranch() {
    return this.selectedBranchValues?.length > 1;
}

get showMoreLabelBranch() {
    return this.isExpanded ? 'Show Less' : `Show More (${this.remainingBranchPillsCount})`;
}

get remainingBranchPillsCount() {
    return Math.max(this.selectedBranchValues?.length - 1, 0);
}

toggleShowMoreBranch() {
    this.isExpanded = !this.isExpanded;
    this.toggleExpand('branch', this.isExpanded);
}

toggleExpand(type, expand) {
    const listboxElement = this.template.querySelector(`[data-element="${type}-listbox"]`);
    if (listboxElement) {
        listboxElement.classList.toggle('expanded', expand);
    }
}


// Fix selectedBranchPills getter to ensure it only shows selected values
get selectedBranchPills() {
    try {
        if (!Array.isArray(this.selectedBranchValues) || !Array.isArray(this.branchOptions)) {
            return [];
        }
        
        // Only return pills for actual selected values
        const validSelections = this.selectedBranchValues.filter(value => 
            this.branchOptions.some(opt => opt.value === value)
        );
        
        return validSelections.map(value => {
            const option = this.branchOptions.find(opt => opt.value === value);
            return { label: option?.label || value, value: value };
        });
    } catch (error) {
        console.error('Error in selectedBranchPills getter:', error);
        return [];
    }
}


// Product Logic /////////////////////////////////////////

get displayOptionsProduct() {
    return this.productOptions.map(opt => ({
        ...opt,
        show: this.visibleOptionsProduct.includes(opt.value),
        checked: this.selectedProductValues.includes(opt.value)
    }));
}

handleSearchProduct(event) {
    const searchTerm = event.target.value.toLowerCase();
    this.visibleOptionsProduct = [];
    this.productOptions.forEach(option => {
        if (option.label.toLowerCase().includes(searchTerm)) {
            this.visibleOptionsProduct.push(option.value);
        }
    });
    this.showDDProduct = this.visibleOptionsProduct.length > 0;
}

handleSelectProduct(event) {
    const value = event.target.value;
    const checked = event.target.checked;
    if (value === 'SelectAll') {
        if (checked) {
            this.selectedProductValues = this.productOptions.map(opt => opt.value);
        } else {
            this.selectedProductValues = [];
        }
    } else {
        if (checked) {
            if (!this.selectedProductValues.includes(value)) {
                this.selectedProductValues.push(value);
            }
        } else {
            this.selectedProductValues = this.selectedProductValues.filter(item => item !== value);
        }
    }
    this.updateSelectAllProduct();
    this.updatePlaceholderProduct();

    // if(this.selectedProductValues.length>0){
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // }
    // else{
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // }

    this.wiredLoanData();
    this.summaryLoanData();
}

updateSelectAllProduct() {
    this.isSelectAllProduct = this.selectedProductValues.length === this.productOptions.length;
}

updatePlaceholderProduct() {
    const count = this.selectedProductValues.length;
    this.placeholderProduct = count > 0 ? `${count} Item(s) Selected` : '';
}

get hasMultipleProduct() {
    return this.selectedProductValues && this.selectedProductValues.length > 1;
}

handleProductRemove(event) {
    try {
        const valueToRemove = event.detail.name;
        this.selectedProductValues = this.selectedProductValues.filter(value => value !== valueToRemove);
        if (!this.visibleOptionsProduct || this.visibleOptionsProduct.length === 0) {
            this.visibleOptionsProduct = this.productOptions.map(opt => opt.value);
        }
        this.updateSelectAllProduct();
        this.updatePlaceholderProduct();
        this.wiredLoanData();
        this.summaryLoanData();

    } catch (error) {
        console.error('Error in handleProductRemove:', error);
    }
}

get hasMoreThanOneProduct() {
    return this.selectedProductValues?.length > 1;
}

get showMoreLabelProduct() {
    return this.isExpanded ? 'Show Less' : `Show More (${this.remainingProductPillsCount})`;
}

get remainingProductPillsCount() {
    return Math.max(this.selectedProductValues?.length - 1, 0);
}

toggleShowMoreProduct() {
    this.isExpanded = !this.isExpanded;
    this.toggleExpand('product', this.isExpanded);
}

toggleExpand(type, expand) {
    const listboxElement = this.template.querySelector(`[data-element="${type}-listbox"]`);
    if (listboxElement) {
        listboxElement.classList.toggle('expanded', expand);
    }
}

get selectedProductPills() {
    try {
        if (!Array.isArray(this.selectedProductValues) || !Array.isArray(this.productOptions)) {
            return [];
        }
        return this.selectedProductValues.map(value => {
            const option = this.productOptions.find(opt => opt.value === value);
            return { label: option?.label || value, value: value };
        });
    } catch (error) {
        console.error('Error in selectedProductPills getter:', error);
        return [];
    }
}

//////////////////////////stage/////////////////

get displayOptionsStage() {
    return this.stageOptions.map(opt => ({
        ...opt,
        show: this.visibleOptionsStage.includes(opt.value),
        checked: this.selectedStageValues.includes(opt.value)
    }));
}

handleSearchStage(event) {
    const searchTerm = event.target.value.toLowerCase();
    this.visibleOptionsStage = [];
    this.stageOptions.forEach(option => {
        if (option.label.toLowerCase().includes(searchTerm)) {
            this.visibleOptionsStage.push(option.value);
        }
    });
    this.showDDStage = this.visibleOptionsStage.length > 0;
}

handleSelectStage(event) {
    const value = event.target.value;
    const checked = event.target.checked;
    if (value === 'SelectAll') {
        if (checked) {
            this.selectedStageValues = this.stageOptions.map(opt => opt.value);
        } else {
            this.selectedStageValues = [];
        }
    } else {
        if (checked) {
            if (!this.selectedStageValues.includes(value)) {
                this.selectedStageValues.push(value);
            }
        } else {
            this.selectedStageValues = this.selectedStageValues.filter(item => item !== value);
        }
    }
    this.updateSelectAllStage();
    this.updatePlaceholderStage();

    // if (this.selectedStageValues.length > 0) {
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // } else {
    //     this.wiredLoanData();
    //     this.summaryLoanData();
    // }

    this.wiredLoanData();
    this.summaryLoanData();
}

updateSelectAllStage() {
    this.isSelectAllStage = this.selectedStageValues.length === this.stageOptions.length;
}

updatePlaceholderStage() {
    const count = this.selectedStageValues.length;
    this.placeholderStage = count > 0 ? `${count} Item(s) Selected` : '';
}

get hasMultipleStage() {
    return this.selectedStageValues && this.selectedStageValues.length > 1;
}

handleStageRemove(event) {
    try {
        const valueToRemove = event.detail.name;
        this.selectedStageValues = this.selectedStageValues.filter(value => value !== valueToRemove);
        if (!this.visibleOptionsStage || this.visibleOptionsStage.length === 0) {
            this.visibleOptionsStage = this.stageOptions.map(opt => opt.value);
        }
        this.updateSelectAllStage();
        this.updatePlaceholderStage();
        this.wiredLoanData();
        this.summaryLoanData();
    } catch (error) {
        console.error('Error in handleStageRemove:', error);
    }
}

get hasMoreThanOneStage() {
    return this.selectedStageValues?.length > 1;
}

get showMoreLabelStage() {
    return this.isExpanded ? 'Show Less' : `Show More (${this.remainingStagePillsCount})`;
}

get remainingStagePillsCount() {
    return Math.max(this.selectedStageValues?.length - 1, 0);
}

toggleShowMoreStage() {
    this.isExpanded = !this.isExpanded;
    this.toggleExpand('stage', this.isExpanded);
}

toggleExpand(type, expand) {
    const listboxElement = this.template.querySelector(`[data-element="${type}-listbox"]`);
    if (listboxElement) {
        listboxElement.classList.toggle('expanded', expand);
    }
}

get selectedStagePills() {
    try {
        if (!Array.isArray(this.selectedStageValues) || !Array.isArray(this.stageOptions)) {
            return [];
        }
        return this.selectedStageValues.map(value => {
            const option = this.stageOptions.find(opt => opt.value === value);
            return { label: option?.label || value, value: value };
        });
    } catch (error) {
        console.error('Error in selectedStagePills getter:', error);
        return [];
    }
}

    ///////////////////date section///////////////

handleStartDateChange(event) {
        this.startDate = event.target.value;
        let startDateObj = new Date(this.startDate);
        this.startMonth = startDateObj.getMonth()+1;
        this.endMonth = new Date(this.endDate).getMonth()+1;
        
        if(this.startMonth != this.endMonth){
            this.loanData = null;
            this.noDataMessage = 'No records returned in preview. Try running the report or editing report date range';
            this.dispatchEvent(
                new ShowToastEvent({
                  title: "Date Range Error",
                  message: "Sorry, Start date and end date should be of same month. ",
                  variant: "Error"
                })
              );
        }
        else{
                this.wiredLoanData();
                this.summaryLoanData();
        }
    }

    handleEndDateChange(event) {
        let today=new Date().toISOString().split('T')[0];
        this.startMonth = new Date(this.startDate).getMonth()+1;
        this.endDate=event.target.value;
        let endDateObj = new Date(this.endDate);
        this.endMonth = endDateObj.getMonth()+1;

        if(event.target.value<this.startDate){
            this.loanData = null;
            this.noDataMessage = 'No records returned in preview. Try running the report or editing report date range';
            event.target.value=this.endDate;
            this.dispatchEvent(
                new ShowToastEvent({
                  title: "End Date Range Error",
                  message: "Sorry, End date cannot be less than start date please select the valid date range.",
                  variant: "Error"
                })
              );
        }
        else if(event.target.value>today){
            this.loanData = null;
            this.noDataMessage = 'No records returned in preview. Try running the report or editing report date range';
            this.dispatchEvent(
                new ShowToastEvent({
                  title: "Date Validation Error",
                  message: "Sorry, End date cannot be more than today's date please select the valid date range.",
                  variant: "Error"
                })
              );
        }
        else if(this.startMonth!=this.endMonth){
            this.loanData = null;
            this.noDataMessage = 'No records returned in preview. Try running the report or editing report date range';
            this.dispatchEvent(
                new ShowToastEvent({
                  title: "Date Validation Error",
                  message: "Sorry, End date should be of same month as start date please select the valid date range.",
                  variant: "Error"
                })
              );
        }
        else{
            this.endDate = event.target.value;
            this.wiredLoanData();
            this.summaryLoanData();
            this.loading = false;
        }
       
    }

    getTodayDate() {
        let today = new Date();
        return today.toISOString().split('T')[0]; // Format YYYY-MM-DD
    }
 
    getYesterday() {
        let now = new Date();
        let yesterday = new Date();
        yesterday.setDate(now.getDate() - 1);
        return yesterday.toISOString().split('T')[0]; // Format YYYY-MM-DD

    }

    //////////////////////////////////Summmary Table////////////////

    summaryLoanData(){
        getLoanApplicationSummary({startDate: this.startDate, endDate: this.endDate, selectedState: this.selectedStateValues, selectedBranch: this.selectedBranchValues, selectedStage: this.selectedStageValues, selectedProduct: this.selectedProductValues})
        .then(data => {
            if (data) {
                this.populateSummaryData(data);
            } else {
                this.resetSummaryData();
            }
        })
        .catch(error => {
            console.error(error);
            this.error = error;
            this.noDataMessage = 'An error occurred while fetching data.';
            this.resetSummaryData(); 
        });
    }

    populateSummaryData(data) {
        const stageCountMap = new Map();
        data.forEach(item => {
            if (item.Stage !== 'Total') {
                stageCountMap.set(item.Stage, item.Count);
            }
        });
        let total = 0; 
        this.summaryData = this.summaryData.map(item => {
            if (item.stage !== 'Total') {
                const count = stageCountMap.get(item.stage) || 0; // Default to 0 if not found
                total += count; // Accumulate total count
                return { ...item, recordCount: count };
            } else {
                return { ...item, recordCount: total  }; // Update total count
            }
        });
    }

    resetSummaryData() {
        this.summaryData = this.summaryData.map(item => ({ ...item, recordCount: item.stage === 'Total' ? 0 : 0 }));
    }

    ////////////////////////////////// main table data //////////////

    wiredLoanData(){
        this.loanData=[];
        getLoanApplicationData({pageSize: this.pageSize, pageNumber: this.pageNumber, startDate: this.startDate, endDate: this.endDate, selectedState: this.selectedStateValues, selectedBranch: this.selectedBranchValues, selectedStage: this.selectedStageValues, selectedProduct: this.selectedProductValues})
           .then(data => {
            this.loading = false;
            if(data){
            
                if (data.loanList.length === 0 ) {
                    this.showTable = false;
                    this.loanData = null;
                    this.noPage = true;
                    this.totalPages = 0;
                    this.disableNext = true;
                    this.disablePrevious = true;
                    this.noDataMessage = 'No records returned in preview. Try changing the filter values.';
                }
                else if (data.totalRecords > 50000) {
                    this.showTable = false;
                    this.loanData = null;
                    this.noPage = true;
                    this.totalPages = 0;
                    this.disableNext = true;
                    this.disablePrevious = true;
                    this.noDataMessage = 'Data limit of 50000 record Exceeded.Please select another month.';
                }
                else{
                    this.loanData = data.loanList; 
                    this.showTable = true;
                    this.noPage = false;
                    this.totalPages = Math.ceil(data.totalRecords / this.pageSize);
                    this.totalRecordCount = data.totalRecords;
                    this.noDataMessage = ''; // Clear any previous message
                    this.disableNext = this.pageNumber >= this.totalPages;
                    this.disablePrevious = this.pageNumber === 1;
                    this.error = undefined;
                }
                this.error = undefined;
            }
            
           }).catch(error=>{
            console.log(error);
            this.error = error;
            this.loanData = undefined;
            this.totalPages = 0;
            this.disableNext = true;
            this.disablePrevious = true;
            this.noPage = true;
            this.noDataMessage = 'An error occurred while fetching data.';
        });
    
    }

    /////////////////////////next and previous button//////////////

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.loading = true;
            this.pageNumber++;
            this.wiredLoanData();
        }
    }
 
    handlePrevious() {
        if (this.pageNumber > 1) {
            this.loading = true;
            this.pageNumber--;
            this.wiredLoanData();
        }
    }
    

    //////////////////////////////////export csv ///////////////////////

    handleExportToCSV(){

        let columnHeader = ["Loan Application ID","Branch Name","State Name","Scheme Code","Product Code","Program Type","Stage","Sub Stage","Status","Owner Name","Lead End Date","Last Modified Date"];  // This array holds the Column headers to be displayd
        let jsonKeys = ["loanApplicationName","branchName","state","schemeCode","productCode","programType","stage","subStage","status","ownerName","leadEndDate","lastModifiedDate"];
          
        getLoanApplicationExport({ startDate: this.startDate, endDate: this.endDate, selectedState: this.selectedStateValues, selectedBranch: this.selectedBranchValues, selectedStage: this.selectedStageValues, selectedProduct: this.selectedProductValues})
        .then((result)=>{            
 
            let today = new Date();
                  this.templist =[];
                    this.templist = result.loanList;     
                    var jsonRecordsData = this.templist;  
                    let csvIterativeData;  
                    let csvSeperator  
                    let newLineCharacter;  
                    csvSeperator = ",";  
                    newLineCharacter = "\n";  
                    csvIterativeData = "";  
                    csvIterativeData += columnHeader.join(csvSeperator);  
                    csvIterativeData += newLineCharacter;  
                    for (let i = 0; i < jsonRecordsData.length; i++) {  
                      let counter = 0;  
                      for (let iteratorObj in jsonKeys) {  
                        let dataKey = jsonKeys[iteratorObj];  
                        if (counter > 0) {  csvIterativeData += csvSeperator;  }  
                        if (  jsonRecordsData[i][dataKey] !== null &&  
                          jsonRecordsData[i][dataKey] !== undefined  
                        ) {  csvIterativeData += '"' + jsonRecordsData[i][dataKey] + '"';  
                        }
                        else {  csvIterativeData += '""';  
                        }  
                        counter++;  
                      }  
                      csvIterativeData += newLineCharacter;  
                    }  
                    this.hrefdata = "data:text/csv;charset=utf-8," + encodeURI(csvIterativeData);
                    let downloadElement = document.createElement('a');
                    downloadElement.href = this.hrefdata ;
                    downloadElement.target = '_self';
                    downloadElement.download = 'DashBoard Report ' + today.toISOString().split('T')[0] + '.csv' ;
                    document.body.appendChild(downloadElement);
                    downloadElement.click();
                    this.CSVDownloading=false;
                })
                .catch((error)=>{
                    console.log('error in Application details',error);
                    this.CSVDownloading=false;
                    this.isLoaded=true;
     
                })

    }

}