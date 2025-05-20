// EventSchedulerController.cls
public with sharing class EventSchedulerController {
    
    /**
     * Get events for a specific date, sorted by start time
     * Includes count of registered attendees for capacity calculation
     * 
     * @param eventDate - The date to retrieve events for
     * @return List<Event__c> - List of events with additional information
     */
    @AuraEnabled(cacheable=true)
    public static List<Event__c> getEventsByDate(Date eventDate) {
        // Validate input
        if (eventDate == null) {
            throw new AuraHandledException('Event date is required');
        }
        
        // Get today's date to exclude past events
        Date today = Date.today();
        
        if (eventDate < today) {
            throw new AuraHandledException('Cannot register for events in the past');
        }
        
        // Query events for the selected date
        List<Event__c> events = [
            SELECT Id, Name, Event_Date__c, Start_Time__c, End_Time__c, 
                   Capacity__c, Description__c, Allow_Waitlist__c,
                   (SELECT Id FROM Event_Attendees__r WHERE Status__c = 'Registered')
            FROM Event__c
            WHERE Event_Date__c = :eventDate
            ORDER BY Start_Time__c ASC
        ];
        
        // Add count of registered attendees to each event
        for (Event__c event : events) {
            event.put('registeredCount', event.Event_Attendees__r.size());
        }
        
        return events;
    }
    
    /**
     * Register a contact for an event with validation logic for capacity and duplicates
     * 
     * @param contactId - The ID of the contact to register
     * @param eventId - The ID of the event to register for
     * @param notes - Any additional notes for the registration
     * @return Map<String, Object> - Result with success flag, status, and message
     */
    @AuraEnabled
    public static Map<String, Object> registerForEvent(Id contactId, Id eventId, String notes) {
        Map<String, Object> result = new Map<String, Object>{
            'success' => false,
            'status' => '',
            'message' => ''
        };
        
        try {
            // Validate inputs
            if (contactId == null || eventId == null) {
                throw new AuraHandledException('Contact and Event are required');
            }
            
            // Query the event with its attendees
            Event__c event = [
                SELECT Id, Name, Event_Date__c, Capacity__c, Allow_Waitlist__c,
                       (SELECT Id, Status__c FROM Event_Attendees__r)
                FROM Event__c 
                WHERE Id = :eventId
            ];
            
            // Check for past event
            if (event.Event_Date__c < Date.today()) {
                throw new AuraHandledException('Cannot register for events in the past');
            }
            
            // Check for existing registration
            for (Event_Attendee__c attendee : event.Event_Attendees__r) {
                if (attendee.Status__c == 'Registered' && attendee.Contact__c == contactId) {
                    throw new AuraHandledException('This contact is already registered for this event');
                }
            }
            
            // Count registered attendees
            Integer registeredCount = 0;
            for (Event_Attendee__c attendee : event.Event_Attendees__r) {
                if (attendee.Status__c == 'Registered') {
                    registeredCount++;
                }
            }
            
            // Determine registration status based on capacity
            String status = 'Registered';
            if (registeredCount >= event.Capacity__c) {
                if (event.Allow_Waitlist__c) {
                    status = 'Waitlisted';
                } else {
                    throw new AuraHandledException('This event is at full capacity and does not allow waitlisting');
                }
            }
            
            // Create new event attendee record
            Event_Attendee__c newAttendee = new Event_Attendee__c(
                Event__c = eventId,
                Contact__c = contactId,
                Notes__c = notes,
                Status__c = status,
                Registered_On__c = Datetime.now()
            );
            
            // Insert with sharing context to respect security
            insert newAttendee;
            
            // Check if we need to promote any waitlisted attendees
            if (status == 'Registered' && registeredCount == event.Capacity__c - 1) {
                promoteWaitlistedAttendee(eventId);
            }
            
            // Return success result
            result.put('success', true);
            result.put('status', status);
            result.put('message', 'Registration successful');
            
        } catch (Exception e) {
            result.put('success', false);
            result.put('message', e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Check if the contact has any time conflicts with existing events
     * 
     * @param contactId - The ID of the contact to check
     * @param eventId - The ID of the event being registered for
     * @param eventDate - The date of the event
     * @return Boolean - True if conflicts exist, false otherwise
     */
    @AuraEnabled
    public static Boolean checkTimeConflicts(Id contactId, Id eventId, Date eventDate) {
        try {
            // Get the time range for the selected event
            Event__c selectedEvent = [
                SELECT Id, Start_Time__c, End_Time__c
                FROM Event__c
                WHERE Id = :eventId
            ];
            
            // Find all events where the contact is already registered on the same date
            List<Event_Attendee__c> existingAttendees = [
                SELECT Id, Event__c, Event__r.Start_Time__c, Event__r.End_Time__c
                FROM Event_Attendee__c
                WHERE Contact__c = :contactId
                AND Status__c = 'Registered'
                AND Event__r.Event_Date__c = :eventDate
            ];
            
            // Check for time overlaps with existing registrations
            for (Event_Attendee__c attendee : existingAttendees) {
                // Skip if it's the same event (though this shouldn't happen due to duplicate check)
                if (attendee.Event__c == eventId) continue;
                
                // Check for overlap
                Boolean overlap = timeRangesOverlap(
                    selectedEvent.Start_Time__c, selectedEvent.End_Time__c,
                    attendee.Event__r.Start_Time__c, attendee.Event__r.End_Time__c
                );
                
                if (overlap) {
                    return true; // Conflict found
                }
            }
            
            return false; // No conflicts
            
        } catch (Exception e) {
            throw new AuraHandledException('Error checking for time conflicts: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to check if two time ranges overlap
     */
    private static Boolean timeRangesOverlap(Time start1, Time end1, Time start2, Time end2) {
        // If one range ends before the other starts, there's no overlap
        if (end1 <= start2 || end2 <= start1) {
            return false;
        }
        return true;
    }
    
    /**
     * Promote the first waitlisted attendee to Registered status when a slot becomes available
     */
    private static void promoteWaitlistedAttendee(Id eventId) {
        List<Event_Attendee__c> waitlistedAttendees = [
            SELECT Id
            FROM Event_Attendee__c
            WHERE Event__c = :eventId
            AND Status__c = 'Waitlisted'
            ORDER BY Registered_On__c ASC
            LIMIT 1
        ];
        
        if (!waitlistedAttendees.isEmpty()) {
            Event_Attendee__c attendee = waitlistedAttendees[0];
            attendee.Status__c = 'Registered';
            update attendee;
        }
    }
}