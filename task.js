// eventScheduler.js
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

// Import Apex methods
import getEventsByDate from '@salesforce/apex/EventSchedulerController.getEventsByDate';
import registerForEvent from '@salesforce/apex/EventSchedulerController.registerForEvent';
import checkTimeConflicts from '@salesforce/apex/EventSchedulerController.checkTimeConflicts';

export default class EventScheduler extends LightningElement {
    // Tracking properties
    @track selectedDate = new Date().toISOString().split('T')[0]; // Default to today
    @track selectedEventId;
    @track selectedContactId;
    @track notes = '';
    @track events = [];
    @track selectedEvent;
    @track isLoading = false;
    @track noEventsAvailable = false;
    
    // Wire service to fetch events based on selected date
    @wire(getEventsByDate, { eventDate: '$selectedDate' })
    wiredEvents({ error, data }) {
        this.isLoading = true;
        if (data) {
            // Process and store events data
            this.events = data.map(event => {
                return {
                    ...event,
                    formattedDate: this.formatDate(event.Event_Date__c),
                    formattedTimeRange: this.formatTimeRange(event.Start_Time__c, event.End_Time__c),
                    capacityDisplay: `${event.registeredCount || 0} / ${event.Capacity__c}`,
                    waitlistDisplay: event.Allow_Waitlist__c ? 'Allowed' : 'Not Allowed'
                };
            });
            
            this.noEventsAvailable = this.events.length === 0;
            
            // Clear selected event if it's no longer in the list
            if (this.selectedEventId && !this.events.some(event => event.Id === this.selectedEventId)) {
                this.selectedEventId = null;
                this.selectedEvent = null;
            }
            
            this.isLoading = false;
        } else if (error) {
            this.handleError(error);
            this.events = [];
            this.noEventsAvailable = true;
            this.isLoading = false;
        }
    }

    // Computed property to get event options for the dropdown
    get eventOptions() {
        return this.events.map(event => {
            return {
                label: `${event.Name} - ${event.formattedTimeRange}`,
                value: event.Id
            };
        });
    }
    
    // Computed property to determine if submit should be disabled
    get isSubmitDisabled() {
        return !this.selectedEventId || !this.selectedContactId || !this.notes.trim() || this.isLoading;
    }

    // Event handlers
    handleDateChange(event) {
        this.selectedDate = event.target.value;
        this.selectedEventId = null;
        this.selectedEvent = null;
    }
    
    handleEventChange(event) {
        this.selectedEventId = event.detail.value;
        this.selectedEvent = this.events.find(evt => evt.Id === this.selectedEventId);
    }
    
    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
    }
    
    handleNotesChange(event) {
        this.notes = event.detail.value;
    }
    
    async handleSubmit() {
        if (this.isSubmitDisabled) return;
        
        try {
            this.isLoading = true;
            
            // First check for time conflicts
            const hasConflicts = await checkTimeConflicts({
                contactId: this.selectedContactId,
                eventId: this.selectedEventId,
                eventDate: this.selectedDate
            });
            
            if (hasConflicts) {
                this.showToast('Error', 'This contact has a scheduling conflict with another event at this time', 'error');
                this.isLoading = false;
                return;
            }
            
            // If no conflicts, proceed with registration
            const result = await registerForEvent({
                contactId: this.selectedContactId,
                eventId: this.selectedEventId,
                notes: this.notes
            });
            
            // Handle different responses
            if (result.success) {
                if (result.status === 'Registered') {
                    this.showToast('Success', 'Successfully registered for the event', 'success');
                } else if (result.status === 'Waitlisted') {
                    this.showToast('Information', 'Event is at capacity. You have been added to the waitlist.', 'info');
                }
                
                // Reset form
                this.resetForm();
                
                // Refresh the data
                refreshApex(this.wiredEvents);
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }
    
    // Helper methods
    resetForm() {
        this.notes = '';
        this.selectedContactId = null;
        
        // Reset the contact lookup field - need to query the DOM since it's not directly tracked
        const contactField = this.template.querySelector('lightning-input-field');
        if (contactField) {
            contactField.reset();
        }
    }
    
    formatDate(dateString) {
        if (!dateString) return '';
        const options = { year: 'numeric', month: 'long', day: 'numeric' };
        return new Date(dateString).toLocaleDateString(undefined, options);
    }
    
    formatTimeRange(startTime, endTime) {
        if (!startTime || !endTime) return '';
        
        const formatTime = (timeString) => {
            // Handle Salesforce time format conversion
            const [hours, minutes] = timeString.split(':');
            const date = new Date();
            date.setHours(parseInt(hours, 10));
            date.setMinutes(parseInt(minutes, 10));
            
            return date.toLocaleTimeString(undefined, {
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        };
        
        return `${formatTime(startTime)} to ${formatTime(endTime)}`;
    }
    
    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(toastEvent);
    }
    
    handleError(error) {
        let errorMessage = 'Unknown error';
        if (error.body && error.body.message) {
            errorMessage = error.body.message;
        } else if (typeof error === 'string') {
            errorMessage = error;
        } else if (error.message) {
            errorMessage = error.message;
        }
        
        this.showToast('Error', errorMessage, 'error');
        console.error('Error in EventScheduler component:', error);
    }
}